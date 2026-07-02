// The translation table and its boot loader — the port of `lib/translate.js`
// plus the language plumbing from the original `index.html` / `engine.js`.

// The msgid → msgstr table. `null` means English: lookups are the identity.
// A prototype-less object so msgids like "constructor" stay honest.
let table = null;

export function setTranslation(map) {
  table = Object.assign(Object.create(null), map);
}

export function setTranslationJson(json) {
  setTranslation(JSON.parse(json));
}

export function clearTranslation() {
  table = null;
}

export function lookup(msgid) {
  if (table === null) return msgid;
  const hit = table[msgid];
  return typeof hit === "string" && hit !== "" ? hit : msgid;
}

// Which language the page wants: the `?lang=` query parameter wins and is
// remembered (the original `Engine.saveLanguage`), else the remembered choice.
function detectLanguage() {
  let lang = null;
  const match = /[?&]lang=([^&;#]+)/.exec(window.location.search);
  if (match) {
    lang = decodeURIComponent(match[1].replace(/\+/g, "%20"));
  }
  try {
    if (lang) {
      localStorage.lang = lang;
    } else if (localStorage.lang) {
      lang = localStorage.lang;
    }
  } catch {
    // Storage may be walled off; the query parameter alone still works.
  }
  return lang;
}

// Fetch and install the selected language before the game starts — the
// original's `document.write('<script src="lang/…/strings.js">')`, done with
// a fetch of the pipeline's JSON. Also hangs the language's stylesheet
// (CJK/Thai font fixes and the like), as the original index.html does.
export async function initLanguage() {
  const lang = detectLanguage();
  if (!lang || lang === "en" || !/^[a-zA-Z_]+$/.test(lang)) return;
  try {
    const response = await fetch(`/lang/${lang}/strings.json`);
    if (!response.ok) return;
    setTranslation(await response.json());
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = `/lang/${lang}/main.css`;
    document.head.appendChild(link);
  } catch {
    // No catalog, no translation — the game speaks English.
  }
}

// Reload the page with `?lang=` pointing at the chosen language — the
// original `Engine.switchLanguage`. The boot loader persists the choice.
export function switchLanguage(code) {
  const href = window.document.location.href;
  if (/[?&]lang=[a-zA-Z_]+/.test(href)) {
    window.document.location.href = href.replace(
      /([?&]lang=)([a-zA-Z_]+)/gi,
      "$1" + code,
    );
  } else {
    window.document.location.href =
      href + (href.includes("?") ? "&" : "?") + "lang=" + code;
  }
}
