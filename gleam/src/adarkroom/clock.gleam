//// Time access for the engine: wall-clock time (for timestamps and saves) and
//// a monotonic clock (for measuring elapsed durations).

/// Milliseconds since the Unix epoch (`Date.now`).
@external(javascript, "./clock_ffi.mjs", "now")
pub fn now() -> Float

/// Monotonic milliseconds (`performance.now`), for measuring durations.
/// Falls back to `Date.now` when `performance` is unavailable.
@external(javascript, "./clock_ffi.mjs", "perfNow")
pub fn perf_now() -> Float
