//// The playthrough journal: every notification, timestamped, kept in a
//// localStorage ring buffer for parity debugging. From the browser console:
//// `copy(adrLog())` to grab it, `adrLogClear()` to start fresh.
////
//// Recording is best-effort and write-only — a debugging sink, not game
//// state. Where storage is unavailable (tests, private browsing) it
//// degrades to a no-op.

@external(javascript, "./journal_ffi.mjs", "record")
pub fn record(location: String, message: String) -> Nil
