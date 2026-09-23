# A Dark Room — Gleam + Lustre Port — Design

**Status:** Delivered 2026-06-11 — M0–M7 complete; the port is on `master`
and live at [adarkroom.coze.org](https://adarkroom.coze.org). M8
(localization, #34/#35) and accessibility (#42) followed on 2026-07-02.
A 2026-09 audit closed a round of parity and playability gaps (combat
timers and ammo, the ascent's layout, the corner menu, saves).
*(Approved 2026-06-07.)*
**Target:** Faithful 1:1 port of the current upstream JS game
(`doublespeakgames/adarkroom` @ `1fada46`, 2025-05-23) to **Gleam + Lustre**.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Language / framework | Gleam compiled to JS, **Lustre** (Elm-style MVU) |
| Location | the repo root (`c0ze/adarkroom-gleam`); the original JS is kept in `adarkroom-js/` as the **reference implementation** |
| Localization | **English-first**; the 18-language gettext/`.po` pipeline is deferred to M8 |
| Fidelity | **Faithful 1:1** (behavior, balance, RNG) before any improvements |
| Tracking | GitHub milestones + issues on `c0ze/adarkroom-gleam` |

## Architecture

A single-page **MVU** app:

- **`Model`** — one typed record tree replacing the global stringly-typed `State`
  (categories: `stores`, `features`, `character`, `game`, `income`, `timers`,
  `playStats`, `previous`, `outfit`). Items / buildings / perks / events become
  **variants** so the compiler enforces exhaustive handling.
- **`Msg` + `update`** — every action, tick, and event outcome is a typed
  message; `update(Model, Msg) -> #(Model, Effect(Msg))`.
- **Effects (FFI)** — for the things the browser owns: `localStorage`
  (save/load), timers (`setInterval`/`setTimeout`/`requestAnimationFrame`),
  **seeded RNG** (combat & worldgen parity), and audio.
- **`view`** — per-screen view modules (Room, Outside, World, Path, Ship, Space,
  Fabricator). Reuse the existing `css/` and `img/` assets as-is.
- **Build** — Gleam → JS via Lustre, bundled with Vite, deployed as static files
  (same hosting model as today).

## Source map (JS → port)

| JS source | Ported into |
| --- | --- |
| `engine.js` | Core loop, perks, save orchestration, navigation |
| `state_manager.js` | Typed `Model` + persistence |
| `room/outside/world/path/ship/space/fabricator.js` | Per-screen modules |
| `events.js` + `events/*` | Event runtime + typed scenes / encounters / setpieces |
| `notifications.js`, `header.js`, `Button.js` | UI infrastructure |
| `audio.js`, `audioLibrary.js` | Audio (M7) |
| `prestige.js`, `scoring.js` | Endgame (M6) |
| `localization.js`, `lang/`, `tools/po2js.py` | i18n (M8) |
| `dropbox.js` | Dropped (dead integration) |

## Verification strategy

Run the reference JS build alongside the port and compare progression, balance,
and RNG outcomes (seeded). The systematic parity checklist lives in M7.

## Milestones & issues

**M0 · Scaffolding & infrastructure**
- Set up Gleam + Lustre project & build pipeline (Vite, static build, layout shell)
- Browser FFI shims (localStorage, timers, seeded RNG, now)
- CI — format check, build, test

**M1 · Core engine & state**
- Typed core `State`/`Model`
- MVU skeleton + main game loop tick
- Notifications + running message log
- Button + cooldown component
- Header, location tabs & panel navigation
- Save/load to localStorage (new format; Dropbox dropped)

**M2 · The Room** *(first playable vertical slice)*
- Fire & temperature
- Wood gathering + stores panel
- Room builds & crafts
- Trader / nomad interactions

**M3 · The Outside (village)**
- Village & population
- Worker assignment & income
- Outside buildings & gather/trap loop

**M4 · World map & combat**
- World map generation
- World rendering, movement & survival
- Combat engine
- Path / outfitting screen

**M5 · Events, encounters & setpieces**
- Event runtime & scene UI
- Typed scene schema + Room/Outside/global events
- Encounters (combat events)
- Setpieces (scripted multi-scene events; may split per setpiece)
- Newer event sets (marketing, executioner)

**M6 · Endgame**
- Ship / starship upgrades
- Space ascent minigame + ending
- Fabricator (alien crafting)
- Death, prestige & scoring

**M7 · Feel, audio & parity** ✅
- Match the feel (animation & timing)
- Audio system
- Parity pass & bug bash (string audit + side-by-side lockstep + live
  playthroughs via the journal; ongoing finds become individual PRs)

**M8 · Localization** ✅ *(#34/#35)*
- String catalog + gettext/`.po` pipeline
- Load the 25 converted languages + language switcher (in the bottom menu,
  with sound, lights, restart and save)

---

*Dependency spine:* M0 → M1 → M2 → M3/M4 → M5 → M6 → M7; M8 last.
M2 is the proof-of-architecture checkpoint.

---

## Beyond the original (deliberate additions)

Kept small and clearly marked in code; everything else is bug-for-bug:

- **PWA**: manifest, icons, offline service worker (the build precaches
  the shell); `viewport width=920`, the board's real width.
- **Pause button** (the original has no global pause).
- **Playthrough journal**: every notification timestamped into a
  localStorage ring buffer — `adrLog()` / `adrLogClear()` in the console.
- **Touch direction buttons** under the world map (the original used swipe).
- **A refused import**: a save code that won't read is turned away, where
  the original would load it and lose the game; an unreadable local save is
  set aside under `gameState.unreadable` rather than overwritten.
- **No Penrose mid-ascent**: the cross-promo event can come up anywhere
  else, as in the original, but not over the asteroid field.

## Known divergences (documented)

- Mid-trip world changes live in the running page only; a reload returns
  the wanderer home with the outfit intact (matches the original).
- Button cooldowns don't persist across reloads (the original saves some).
- The corner menu has no `hyper.`, `share.`, `get the app.` or `github.`;
  the ascent has no star field.
- The forest-unlock reload window resumes instead of softlocking (the
  original's resume check is dead code).
- During the location slide, each panel carries its own stores column
  (the original counter-animates a single riding container).
