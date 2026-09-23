// The playthrough journal — a localStorage ring buffer of every
// notification, for parity debugging. Best-effort everywhere.
const KEY = "adrJournal";
const CAP = 5000;
// Writes are batched: serializing the whole buffer on every message cost a
// half-megabyte stringify per line of news.
const FLUSH_MS = 2000;

let buffer = null;
let flushTimer = null;

function load() {
  if (buffer) return buffer;
  try {
    buffer = JSON.parse(localStorage.getItem(KEY)) ?? [];
  } catch {
    buffer = [];
  }
  return buffer;
}

function flush() {
  flushTimer = null;
  try {
    localStorage.setItem(KEY, JSON.stringify(buffer));
  } catch {
    // Storage full or absent — the journal is a luxury.
  }
}

export function record(location, message) {
  const log = load();
  log.push(`${new Date().toISOString()} [${location}] ${message}`);
  if (log.length > CAP) {
    log.splice(0, log.length - CAP);
  }
  if (flushTimer === null && typeof setTimeout === "function") {
    flushTimer = setTimeout(flush, FLUSH_MS);
  }
}

if (typeof window !== "undefined") {
  window.adrLog = () => load().join("\n");
  window.adrLogClear = () => {
    buffer = [];
    try {
      localStorage.removeItem(KEY);
    } catch {
      // Nothing to clear.
    }
  };
  // Don't lose the last batch to a closed tab.
  window.addEventListener("pagehide", () => {
    if (flushTimer !== null) {
      clearTimeout(flushTimer);
      flush();
    }
  });
}
