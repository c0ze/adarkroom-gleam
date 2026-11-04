//// Time access for the engine: wall-clock time (for timestamps and saves) and
//// a monotonic clock (for measuring elapsed durations).

/// The game clock, in milliseconds: the wall clock at page load, then
/// running at the game's speed (twice as fast in hyper mode). Every game
/// deadline is measured on it.
@external(javascript, "./clock_ffi.mjs", "now")
pub fn now() -> Float

/// Milliseconds since the Unix epoch (`Date.now`), whatever the game's speed:
/// for the ascent and the other moments the original times on raw timers.
@external(javascript, "./clock_ffi.mjs", "wallNow")
pub fn wall_now() -> Float

/// How many times faster than the wall clock the game runs (1 or 2).
@external(javascript, "./clock_ffi.mjs", "getSpeed")
pub fn speed() -> Int

/// Set the game's speed; the game clock carries on from where it stands.
@external(javascript, "./clock_ffi.mjs", "setSpeed")
pub fn set_speed(speed: Int) -> Nil

/// Monotonic milliseconds (`performance.now`), for measuring durations.
///
/// Falls back to `Date.now` when `performance` is unavailable; in that case the
/// result is **not** guaranteed monotonic (the wall clock can jump backwards),
/// so callers measuring elapsed time should clamp negative deltas to zero.
@external(javascript, "./clock_ffi.mjs", "perfNow")
pub fn perf_now() -> Float
