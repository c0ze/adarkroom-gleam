# A Dark Room — Gleam + Lustre Port — Design

**Status:** Approved 2026-06-07
**Target:** Faithful 1:1 port of the current upstream JS game
(`doublespeakgames/adarkroom` @ `1fada46`, 2025-05-23) to **Gleam + Lustre**.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Language / framework | Gleam compiled to JS, **Lustre** (Elm-style MVU) |
| Location | `gleam/` subdirectory of this repo; the current JS is kept as the **reference implementation** |
| Localization | **English-first**; the 18-language gettext/`.po` pipeline is deferred to M8 |
| Fidelity | **Faithful 1:1** (behavior, balance, RNG) before any improvements |
| Tracking | GitHub milestones + issues on `c0ze/adarkroom` |

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
- Set up Gleam + Lustre project & build pipeline (`gleam/` subdir, Vite, static build, layout shell)
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

**M7 · Feel, audio & parity**
- Match the feel (animation & timing)
- Audio system
- Parity pass & bug bash

**M8 · Localization** *(deferred)*
- String catalog + gettext/`.po` pipeline
- Load 18 languages + language switcher

---

*Dependency spine:* M0 → M1 → M2 → M3/M4 → M5 → M6 → M7; M8 last.
M2 is the proof-of-architecture checkpoint.
