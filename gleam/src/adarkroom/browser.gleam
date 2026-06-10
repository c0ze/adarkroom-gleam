//// Browser window FFI: the odd corners of `window` the game needs.

/// Open a URL in a new tab (`window.open`).
@external(javascript, "./browser_ffi.mjs", "openUrl")
pub fn open_url(url: String) -> Nil
