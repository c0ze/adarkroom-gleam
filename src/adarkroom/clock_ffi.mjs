// The game clock. In the original, hyper mode is `Engine.options.doubleTime`:
// every `Engine.setTimeout` / `Engine.setInterval` runs at half its delay. Here
// the game's own clock runs at `speed` times the wall clock instead, and the
// game's timers (timer_ffi.mjs) divide their delays by the same speed, so
// deadlines measured against `now()` and timeouts scheduled in game time agree.
//
// The clock never jumps: a speed change re-bases it where it stands. It starts
// at the wall clock on every page load; nothing saved holds a game-clock
// timestamp across a reload (the fire's deadline is reset at boot).
let speed = 1;
let baseWall = Date.now();
let baseGame = baseWall;

export function now() {
  return baseGame + (Date.now() - baseWall) * speed;
}

// The wall clock, for what the original times with raw browser timers and
// jQuery animations (the ascent, poison ticks, stuns, the ending).
export function wallNow() {
  return Date.now();
}

export function getSpeed() {
  return speed;
}

export function setSpeed(next) {
  const at = now();
  baseWall = Date.now();
  baseGame = at;
  speed = next > 0 ? next : 1;
  return undefined;
}

export function perfNow() {
  if (
    typeof performance !== "undefined" &&
    typeof performance.now === "function"
  ) {
    return performance.now();
  }
  return Date.now();
}
