// One-off generator: emits the Gleam `city()` setpiece from the real
// `events/setpieces.js`, so the 52-scene transcription is exact rather than
// hand-typed. Run: `node scripts/gen_city.mjs > /tmp/city.gleam`.
import { readFileSync } from "node:fs";
import vm from "node:vm";

// Shim the globals setpieces.js touches, instrumenting the world/state effects
// so we can tell what each scene's `onLoad` does.
let effect = { clear: false, city: false };
const ctx = {
  _: (s) => s,
  World: {
    curPos: [30, 30],
    clearDungeon: () => (effect.clear = true),
    markVisited: () => {},
    drawRoad: () => {},
    state: {},
    useOutpost: () => {},
  },
  $SM: { set: (k) => { if (String(k).includes("cityCleared")) effect.city = true; }, add: () => {}, get: () => 0 },
  Prestige: { collectStores: () => {} },
  AudioLibrary: new Proxy({}, { get: () => "audio" }),
  Events: { _LEAVE_COOLDOWN: 0, _PAUSE_COOLDOWN: 0 },
};
vm.createContext(ctx);
vm.runInContext(readFileSync(new URL("../../script/events/setpieces.js", import.meta.url), "utf8"), ctx);

const city = ctx.Events.Setpieces.city;
const q = (s) => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
// A Gleam Float literal (integers need an explicit `.0`).
const fl = (n) => (Number.isInteger(n) ? n + ".0" : String(n));
const loot = (l) =>
  Object.entries(l || {}).map(([n, d]) => `combat.LootEntry(${q(n)}, ${d.min}, ${d.max}, ${fl(d.chance)})`);
const lootList = (l) => {
  const e = loot(l);
  return e.length ? `[\n          ${e.join(",\n          ")},\n        ]` : "[]";
};

// nextScene -> the Branch target list (or null for 'end').
const targets = (ns) =>
  ns === "end" || ns === undefined
    ? null
    : Object.entries(ns)
        .sort((a, b) => Number(a[0]) - Number(b[0]))
        .map(([t, s]) => `#(${Number(t) === 1 ? "1.0" : t}, ${q(s)})`)
        .join(", ");

const button = (id, b) => {
  const t = targets(b.nextScene);
  let inner;
  if (t === null) inner = `leave(${q(b.text)})`;
  else if (b.cost) {
    const cost = Object.entries(b.cost).map(([n, v]) => `#(${q(n)}, ${v})`).join(", ");
    inner = `cost_branch(${q(b.text)}, [${cost}], [${t}])`;
  } else inner = `branch(${q(b.text)}, [${t}])`;
  return `#(${q(id)}, ${inner})`;
};
const buttons = (bs) => Object.entries(bs).map(([id, b]) => "          " + button(id, b)).join(",\n");

const enemy = (s) =>
  `enemy(${q(s.enemy)}, ${q(s.chara)}, ${s.health}, ${s.damage}, ${fl(s.hit)}, ${fl(s.attackDelay)}, ${s.ranged ? "True" : "False"}, ${lootList(s.loot)})`;

const story = (text) => `story([\n          ${text.map(q).join(",\n          ")},\n        ])`;

function scene(key, s) {
  effect = { clear: false, city: false };
  if (s.onLoad) s.onLoad();
  const btns = `[\n${buttons(s.buttons)},\n        ]`;
  let body;
  if (s.combat) {
    body = `fight(\n        ${q(s.notification)},\n        NoWorldEffect,\n        ${enemy(s)},\n        ${btns},\n      )`;
  } else if (effect.clear) {
    // An end: clear the dungeon + flag the city cleared, then take the loot.
    body = `Scene(\n        ..${story(s.text)},\n        on_load: Some(city_cleared),\n        setpiece: extra(${lootList(s.loot)}, ClearDungeon),\n        buttons: ${btns},\n      )`;
  } else {
    const notif = s.notification ? `\n        notification: Some(${q(s.notification)}),` : "";
    const setp = s.loot ? `\n        setpiece: extra(${lootList(s.loot)}, NoWorldEffect),` : "";
    body = `Scene(\n        ..${story(s.text || [])},${notif}${setp}\n        buttons: ${btns},\n      )`;
  }
  return `    #(\n      ${q(key)},\n      ${body},\n    )`;
}

const scenes = Object.entries(city.scenes).map(([k, s]) => scene(k, s)).join(",\n");
console.log(`/// ${city.title.replace(/^A /, "A ")} — the largest setpiece (52 scenes). Generated from\n/// the source by scripts/gen_city.mjs, then folded into the suite.\nfn city() -> Event {\n  Event(title: ${q(city.title)}, is_available: always, scenes: [\n${scenes},\n  ])\n}`);
