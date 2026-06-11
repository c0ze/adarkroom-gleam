//// Time access for the engine: wall-clock time (for timestamps and saves) and
//// a monotonic clock (for measuring elapsed durations).

/// Milliseconds since the Unix epoch (`Date.now`).
@external(javascript, "./clock_ffi.mjs", "now")
pub fn now() -> Float

/// Monotonic milliseconds (`performance.now`), for measuring durations.
///
/// Falls back to `Date.now` when `performance` is unavailable; in that case the
/// result is **not** guaranteed monotonic (the wall clock can jump backwards),
/// so callers measuring elapsed time should clamp negative deltas to zero.
@external(javascript, "./clock_ffi.mjs", "perfNow")
pub fn perf_now() -> Float
