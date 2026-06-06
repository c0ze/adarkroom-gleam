# A Dark Room — Gleam + Lustre port

A faithful 1:1 port of [A Dark Room](https://github.com/doublespeakgames/adarkroom)
to **Gleam** + **[Lustre](https://lustre.build)** (Elm-style MVU), compiled to
JavaScript and bundled with Vite.

See [`../docs/gleam-port-design.md`](../docs/gleam-port-design.md) for the
architecture and the M0–M8 milestone plan.

## Prerequisites

- [Gleam](https://gleam.run) 1.15+ (pinned via `mise.toml`)
- Node.js 18+ (for Vite)

## Develop

```sh
npm install        # once: install Vite
npm run dev        # gleam build + Vite dev server (http://localhost:5173)
```

Gleam sources live in `src/`. After changing `.gleam` files, re-run `npm run dev`
(or `gleam build`) to recompile — live-reload of Gleam sources is a TODO.

## Build / preview

```sh
npm run build      # gleam build + vite build -> dist/
npm run preview    # serve the production build locally
```

## Test

```sh
gleam test
```

## Layout

- `src/adarkroom.gleam` — app entry (Model / update / view)
- `main.js` — browser entry; imports the compiled Gleam and starts Lustre
- `index.html` — Vite entry; mounts into `#app`, links the existing stylesheet
- `public/css`, `public/img` — symlinks to the repo-root assets (single source of truth)
