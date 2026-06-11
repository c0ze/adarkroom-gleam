//// Persistent key/value storage backed by the browser's `localStorage`.
////
//// When `localStorage` is unavailable (Node during tests, SSR, or disabled
//// cookies) an in-memory `Map` is used instead, so the API is always usable.

import gleam/option.{type Option, None, Some}

/// Read a value. Returns `None` when the key is absent.
pub fn get(key: String) -> Option(String) {
  case has(key) {
    True -> Some(do_get(key))
    False -> None
  }
}

@external(javascript, "./storage_ffi.mjs", "hasItem")
fn has(key: String) -> Bool

@external(javascript, "./storage_ffi.mjs", "getItem")
fn do_get(key: String) -> String

/// Write a value.
@external(javascript, "./storage_ffi.mjs", "setItem")
pub fn set(key: String, value: String) -> Nil

/// Remove a value. A no-op if the key is absent.
@external(javascript, "./storage_ffi.mjs", "removeItem")
pub fn remove(key: String) -> Nil
