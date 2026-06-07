//// Thin wrappers over the browser timer APIs. These drive the game loop and
//// button cooldowns from the MVU runtime (wired up in M1).

/// An opaque handle identifying a scheduled timer or animation frame.
pub type TimerId

@external(javascript, "./timer_ffi.mjs", "setTimeout")
pub fn set_timeout(callback: fn() -> Nil, delay_ms: Int) -> TimerId

@external(javascript, "./timer_ffi.mjs", "clearTimeout")
pub fn clear_timeout(id: TimerId) -> Nil

@external(javascript, "./timer_ffi.mjs", "setInterval")
pub fn set_interval(callback: fn() -> Nil, interval_ms: Int) -> TimerId

@external(javascript, "./timer_ffi.mjs", "clearInterval")
pub fn clear_interval(id: TimerId) -> Nil

/// Schedule `callback` for the next animation frame; it receives a monotonic
/// timestamp in milliseconds. Falls back to a ~60fps timeout when rAF is
/// unavailable. Returns a `TimerId` for use with `cancel_animation_frame`.
@external(javascript, "./timer_ffi.mjs", "requestAnimationFrame")
pub fn request_animation_frame(callback: fn(Float) -> Nil) -> TimerId

/// Cancel a frame previously scheduled with `request_animation_frame`.
@external(javascript, "./timer_ffi.mjs", "cancelAnimationFrame")
pub fn cancel_animation_frame(id: TimerId) -> Nil
