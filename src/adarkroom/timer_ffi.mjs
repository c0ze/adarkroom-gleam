import { getSpeed } from "./clock_ffi.mjs";

// Game timers run on the game clock (`Engine.setTimeout` / `setInterval`):
// their delays shrink with the speed. The raw ones are the original's plain
// browser timers, which hyper mode never touches.

export function setTimeout(callback, delayMs) {
  return globalThis.setTimeout(() => callback(), delayMs / getSpeed());
}

export function setTimeoutRaw(callback, delayMs) {
  return globalThis.setTimeout(() => callback(), delayMs);
}

export function clearTimeout(id) {
  globalThis.clearTimeout(id);
  return undefined;
}

// A game interval re-arms itself one timeout at a time, reading the speed
// afresh each lap, so switching hyper mode on or off takes hold at the next
// beat instead of at the next page load.
export function setInterval(callback, intervalMs) {
  const handle = { id: null, stopped: false };
  const arm = () => {
    handle.id = globalThis.setTimeout(() => {
      if (handle.stopped) return;
      arm();
      callback();
    }, intervalMs / getSpeed());
  };
  arm();
  return handle;
}

export function clearInterval(handle) {
  handle.stopped = true;
  globalThis.clearTimeout(handle.id);
  return undefined;
}

function monotonicNow() {
  return typeof performance !== "undefined" &&
    typeof performance.now === "function"
    ? performance.now()
    : Date.now();
}

export function requestAnimationFrame(callback) {
  if (typeof globalThis.requestAnimationFrame === "function") {
    // Native rAF passes a DOMHighResTimeStamp (performance.now-based).
    return globalThis.requestAnimationFrame(callback);
  }
  // Fallback: ~60fps. Use the same monotonic clock so the callback receives a
  // timestamp consistent with native rAF semantics.
  return globalThis.setTimeout(() => callback(monotonicNow()), 16);
}

export function cancelAnimationFrame(id) {
  // `id` may come from the native rAF path or the setTimeout fallback;
  // cancelling the wrong space is a harmless no-op.
  if (typeof globalThis.cancelAnimationFrame === "function") {
    globalThis.cancelAnimationFrame(id);
  }
  globalThis.clearTimeout(id);
  return undefined;
}
