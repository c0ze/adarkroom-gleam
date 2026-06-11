// The playthrough journal — a localStorage ring buffer of every
// notification, for parity debugging. Best-effort everywhere.
const KEY = "adrJournal";
const CAP = 5000;

let buffer = null;

function load() {
  if (buffer) return buffer;
  try {
    buffer = JSON.parse(localStorage.getItem(KEY)) ?? [];
  } catch {
    buffer = [];
  }
  return buffer;
}

export function record(location, message) {
  try {
    const log = load();
    log.push(`${new Date().toISOString()} [${location}] ${message}`);
    if (log.length > CAP) {
      log.splice(0, log.length - CAP);
    }
    localStorage.setItem(KEY, JSON.stringify(log));
  } catch {
    // Storage full or absent — the journal is a luxury.
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
}
