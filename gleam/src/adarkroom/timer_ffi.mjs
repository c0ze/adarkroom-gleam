export function setTimeout(callback, delayMs) {
  return globalThis.setTimeout(() => callback(), delayMs);
}

export function clearTimeout(id) {
  globalThis.clearTimeout(id);
  return undefined;
}

export function setInterval(callback, intervalMs) {
  return globalThis.setInterval(() => callback(), intervalMs);
}

export function clearInterval(id) {
  globalThis.clearInterval(id);
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
