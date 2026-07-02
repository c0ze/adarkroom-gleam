// Browser entry point: install the selected language's catalog (if any),
// then import the compiled Gleam program and start it. The catalog must be
// in place before the first render — the original blocks on a synchronous
// script tag for the same reason.
import { main } from "./build/dev/javascript/adarkroom/adarkroom.mjs";
import { initLanguage } from "./build/dev/javascript/adarkroom/adarkroom/i18n_ffi.mjs";

// The catalog is a nicety; the game must boot even if loading it rejects
// (t() falls back to the English msgids when no table was installed).
initLanguage()
  .catch((error) => {
    console.error("language catalog failed to load:", error);
  })
  .finally(main);
