let mem = null;

function backing() {
  try {
    if (typeof localStorage !== "undefined" && localStorage !== null) {
      return localStorage;
    }
  } catch (_) {
    // Accessing localStorage can throw (e.g. disabled cookies).
  }
  if (mem === null) mem = new Map();
  return mem;
}

export function hasItem(key) {
  const b = backing();
  return b instanceof Map ? b.has(key) : b.getItem(key) !== null;
}

export function getItem(key) {
  const b = backing();
  const v = b instanceof Map ? b.get(key) : b.getItem(key);
  return v === undefined || v === null ? "" : v;
}

export function setItem(key, value) {
  const b = backing();
  if (b instanceof Map) b.set(key, value);
  else b.setItem(key, value);
  return undefined;
}

export function removeItem(key) {
  const b = backing();
  if (b instanceof Map) b.delete(key);
  else b.removeItem(key);
  return undefined;
}
