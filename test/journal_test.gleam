import adarkroom/journal

// The journal is best-effort: in Node (no localStorage, no window) recording
// must quietly do nothing rather than crash the game.
pub fn the_journal_degrades_gracefully_test() {
  journal.record("room", "the fire is dead.")
  journal.record("world", "the trees yield to dry grass.")
}
