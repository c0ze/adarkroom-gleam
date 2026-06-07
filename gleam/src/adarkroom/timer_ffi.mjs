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

export function requestAnimationFrame(callback) {
  if (typeof globalThis.requestAnimationFrame === "function") {
    return globalThis.requestAnimationFrame(callback);
  }
  return globalThis.setTimeout(() => callback(Date.now()), 16);
}
