// Browser entry point: install the selected language's catalog (if any),
// then import the compiled Gleam program and start it. The catalog must be
// in place before the first render — the original blocks on a synchronous
// script tag for the same reason.
import { main } from "./build/dev/javascript/adarkroom/adarkroom.mjs";
import { initLanguage } from "./build/dev/javascript/adarkroom/adarkroom/i18n_ffi.mjs";

initLanguage().then(main);
