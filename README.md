# A Dark Room — Gleam + Lustre port

> "awake. head throbbing. vision blurry. come light the fire."

A faithful 1:1 port of [A Dark Room](https://github.com/doublespeakgames/adarkroom)
to **Gleam** + **[Lustre](https://lustre.build)** (Elm-style MVU), compiled to
JavaScript and bundled with Vite. Installable as a PWA, playable offline.

**[Play it at adarkroom.coze.org](https://adarkroom.coze.org)**

The original JavaScript game lives unchanged in
[`adarkroom-js/`](adarkroom-js/) — it is the port's reference, run side by
side during parity testing, and the home of the shared art, audio and
stylesheets. See [`docs/gleam-port-design.md`](docs/gleam-port-design.md) for
the architecture and milestone plan, and
[`docs/gleam-README.md`](docs/gleam-README.md) for the longer development
notes.

## Develop

```sh
mise trust         # once: allow the pinned toolchain (mise users)
npm install        # once: install Vite
npm run dev        # gleam build + Vite dev server (http://localhost:5173)
gleam test         # the test suite
gleam format src test
```

## Release

Every push runs the test suite (CI). Pushing a `v*` tag builds the bundle,
publishes a GitHub release, and deploys to GitHub Pages:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## License

[MPL-2.0](LICENSE.md), as the original.
