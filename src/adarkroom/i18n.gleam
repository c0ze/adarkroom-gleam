//// Runtime string translation — the port of the original's `lib/translate.js`.
////
//// The original wraps every user-facing string in `_('msgid')`; a language's
//// `strings.js` installs a msgid → msgstr table and lookups fall back to the
//// msgid itself. Here the table is a module-level map behind an FFI: the boot
//// script (`main.js` → `initLanguage`) installs the selected language's JSON
//// catalog before the Lustre app starts, so every `t` call after that speaks
//// the chosen tongue. English needs no table at all — the msgids *are* the
//// English strings, exactly as upstream.

import gleam/string

/// Translate a msgid, falling back to the msgid itself when the current
/// catalog has nothing for it (the original `_()`).
@external(javascript, "./i18n_ffi.mjs", "lookup")
pub fn t(msgid: String) -> String

/// Translate a one-hole template and fill `{0}` — `_('the room is {0}', x)`.
pub fn t1(template: String, arg: String) -> String {
  string.replace(t(template), "{0}", arg)
}

/// Translate a two-hole template and fill `{0}` and `{1}`.
pub fn t2(template: String, first: String, second: String) -> String {
  t(template)
  |> string.replace("{0}", first)
  |> string.replace("{1}", second)
}

/// Install a catalog from its JSON text (`{"msgid": "msgstr", …}`) — what the
/// boot loader does with a fetched `strings.json`, and what tests use to
/// speak a small language of their own.
@external(javascript, "./i18n_ffi.mjs", "setTranslationJson")
pub fn load(json: String) -> Nil

/// Drop the installed catalog; lookups become the identity again.
@external(javascript, "./i18n_ffi.mjs", "clearTranslation")
pub fn clear() -> Nil

/// Navigate to the same page with `?lang=` set to the chosen code — the
/// original `Engine.switchLanguage`. The reload boots the game back up from
/// the save with the new catalog installed.
@external(javascript, "./i18n_ffi.mjs", "switchLanguage")
pub fn switch_language(code: String) -> Nil
