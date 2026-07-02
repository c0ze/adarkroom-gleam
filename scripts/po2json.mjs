#!/usr/bin/env node
// The localization pipeline: regenerate everything the port needs from the
// original's untouched translation assets in adarkroom-js/lang/.
//
//   adarkroom-js/lang/<code>/strings.po  →  public/lang/<code>/strings.json
//   adarkroom-js/lang/<code>/main.css    →  public/lang/<code>/main.css
//   adarkroom-js/lang/adarkroom.pot      →  public/lang/msgids.json
//   adarkroom-js/lang/langs.js           →  src/adarkroom/i18n/languages.gleam
//   t("…") literals in src/**/*.gleam    →  src/adarkroom/i18n/catalog.gleam
//
// The JSON mirrors tools/po2js.py: entries with an empty msgstr, or one equal
// to the msgid, are dropped, so a lookup miss falls back to English. Run via
// `npm run i18n` (also runs ahead of `npm run dev` / `npm run build`).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const langRoot = path.join(root, "adarkroom-js", "lang");
const outRoot = path.join(root, "public", "lang");
const genRoot = path.join(root, "src", "adarkroom", "i18n");

// --- .po parsing -------------------------------------------------------------

// Decode one C-style quoted segment body ("…" already stripped).
function unescapePo(s) {
  return s.replace(/\\(.)/g, (_, c) => {
    switch (c) {
      case "n":
        return "\n";
      case "t":
        return "\t";
      case "r":
        return "\r";
      case '"':
        return '"';
      case "\\":
        return "\\";
      default:
        return c;
    }
  });
}

// Parse a .po/.pot file into [{ msgid, msgstr }], skipping obsolete (#~)
// entries. Multiline strings (a run of "…" continuation lines) are joined.
export function parsePo(text) {
  const entries = [];
  let msgid = null;
  let msgstr = null;
  let current = null; // which field "…" continuation lines append to

  const push = () => {
    if (msgid !== null && msgid !== "") {
      entries.push({ msgid, msgstr: msgstr ?? "" });
    }
    msgid = null;
    msgstr = null;
    current = null;
  };

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.startsWith("#~")) continue; // obsolete
    if (line === "" || line.startsWith("#")) {
      if (current === "msgstr") push();
      if (line === "") current = null;
      continue;
    }
    let match;
    if ((match = /^msgid\s+"(.*)"$/.exec(line))) {
      if (current === "msgstr") push();
      msgid = unescapePo(match[1]);
      current = "msgid";
    } else if ((match = /^msgstr\s+"(.*)"$/.exec(line))) {
      msgstr = unescapePo(match[1]);
      current = "msgstr";
    } else if ((match = /^"(.*)"$/.exec(line))) {
      const piece = unescapePo(match[1]);
      if (current === "msgid") msgid += piece;
      else if (current === "msgstr") msgstr += piece;
    }
    // msgid_plural / msgstr[n] never appear in these catalogs; ignore anything else.
  }
  push();
  return entries;
}

// The runtime table, filtered exactly as tools/po2js.py filters.
function toTable(entries) {
  const table = {};
  for (const { msgid, msgstr } of entries) {
    if (msgstr === "" || msgstr === msgid) continue;
    table[msgid] = msgstr;
  }
  return table;
}

// --- Gleam code generation ---------------------------------------------------

function gleamString(s) {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

// A formatted `pub const name = [...]` matching `gleam format` output.
function gleamListConst(comment, name, type, items) {
  const body = items.map((item) => `  ${item},`).join("\n");
  return `${comment}pub const ${name}: ${type} = [\n${body}\n]\n`;
}

// --- steps -------------------------------------------------------------------

function readLangs() {
  // langs.js is a bare `var langs = {…};` — evaluate it in a sandboxed function.
  const source = fs.readFileSync(path.join(langRoot, "langs.js"), "utf8");
  const langs = new Function(`${source}; return langs;`)();
  return Object.entries(langs); // [code, native name] in the original's order
}

function convertLanguages() {
  const converted = [];
  for (const code of fs.readdirSync(langRoot).sort()) {
    const poPath = path.join(langRoot, code, "strings.po");
    if (!fs.existsSync(poPath)) continue;
    const table = toTable(parsePo(fs.readFileSync(poPath, "utf8")));
    const sorted = Object.fromEntries(
      Object.entries(table).sort(([a], [b]) => (a < b ? -1 : 1)),
    );
    const outDir = path.join(outRoot, code);
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, "strings.json"),
      JSON.stringify(sorted, null, 1) + "\n",
    );
    // The language's stylesheet rides along (fonts for CJK/Thai and friends);
    // languages without one get an empty sheet so the link never 404s.
    const cssPath = path.join(langRoot, code, "main.css");
    const css = fs.existsSync(cssPath) ? fs.readFileSync(cssPath) : "";
    fs.writeFileSync(path.join(outDir, "main.css"), css);
    converted.push({ code, entries: Object.keys(sorted).length });
  }
  return converted;
}

// Strings the original wraps in `_()` that its (stale) adarkroom.pot never
// caught — they fall back to English on the live site in every language:
//   perks — script/path.js `'data-legend': _('perks')`
//   stun  — script/world.js weapon `verb: _('stun')`
const sourceOnlyMsgids = ["perks", "stun"];

function writeMsgids() {
  const pot = parsePo(
    fs.readFileSync(path.join(langRoot, "adarkroom.pot"), "utf8"),
  );
  const msgids = [...pot.map((e) => e.msgid), ...sourceOnlyMsgids].sort();
  fs.mkdirSync(outRoot, { recursive: true });
  fs.writeFileSync(
    path.join(outRoot, "msgids.json"),
    JSON.stringify(msgids, null, 1) + "\n",
  );
  return msgids;
}

function writeLanguagesGleam(langs, converted) {
  const available = new Set(["en", ...converted.map((c) => c.code)]);
  const items = langs
    .filter(([code]) => available.has(code))
    .map(([code, name]) => `#(${gleamString(code)}, ${gleamString(name)})`);
  const comment = `//// GENERATED by scripts/po2json.mjs from adarkroom-js/lang/langs.js — do
//// not edit. The selectable languages, as \`#(code, native name)\`, in the
//// original menu's order.

`;
  fs.mkdirSync(genRoot, { recursive: true });
  fs.writeFileSync(
    path.join(genRoot, "languages.gleam"),
    gleamListConst(comment, "languages", "List(#(String, String))", items),
  );
  return items.length;
}

// Every string literal passed whole to i18n.t / t1 / t2 in the port's source.
// Composed lookups — t("not enough " <> x) — resolve at runtime and are not
// captured here.
function extractCatalog() {
  const found = new Set();
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (full === genRoot) continue; // not our own output
        walk(full);
      } else if (entry.name.endsWith(".gleam")) {
        const source = fs.readFileSync(full, "utf8");
        // t("…") | t1("…", | t2("…",  — a whole-literal first argument only:
        // the closing quote must be followed by `)` or `,`.
        const re = /\bt[12]?\(\s*"((?:[^"\\]|\\.)*)"\s*[),]/g;
        let match;
        while ((match = re.exec(source))) {
          found.add(unescapePo(match[1]));
        }
      }
    }
  };
  walk(path.join(root, "src"));
  return [...found].sort();
}

function writeCatalogGleam(msgids) {
  const items = msgids.map(gleamString);
  const comment = `//// GENERATED by scripts/po2json.mjs — do not edit. The typed catalog: every
//// string literal the port passes whole to \`i18n.t\`/\`t1\`/\`t2\`. Each one is a
//// gettext msgid; the test suite holds them against the original's
//// adarkroom.pot so the port never drifts from the reference catalog.

`;
  fs.mkdirSync(genRoot, { recursive: true });
  fs.writeFileSync(
    path.join(genRoot, "catalog.gleam"),
    gleamListConst(comment, "msgids", "List(String)", items),
  );
  return items.length;
}

const langs = readLangs();
const converted = convertLanguages();
const msgids = writeMsgids();
const languageCount = writeLanguagesGleam(langs, converted);
const catalogCount = writeCatalogGleam(extractCatalog());

console.log(
  `po2json: ${converted.length} languages → public/lang/ ` +
    `(${converted.reduce((n, c) => n + c.entries, 0)} strings), ` +
    `${msgids.length} msgids, ${languageCount} menu entries, ` +
    `${catalogCount} catalogued literals`,
);
