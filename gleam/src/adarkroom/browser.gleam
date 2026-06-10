//// Browser window FFI: the odd corners of `window` the game needs.

/// Open a URL in a new tab (`window.open`).
@external(javascript, "./browser_ffi.mjs", "openUrl")
pub fn open_url(url: String) -> Nil

/// Listen for key presses and releases on the document (the ascent's
/// controls). Registered once; the handlers receive `event.key`.
@external(javascript, "./browser_ffi.mjs", "onKeys")
pub fn on_keys(down: fn(String) -> Nil, up: fn(String) -> Nil) -> Nil
