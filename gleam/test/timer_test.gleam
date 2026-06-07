import adarkroom/timer

// Smoke test: scheduling then immediately clearing must not crash (and must not
// leave a pending timer that keeps Node alive). Timer firing is covered by
// integration once the game loop is wired up in M1.
pub fn set_and_clear_timeout_test() {
  let id = timer.set_timeout(fn() { Nil }, 100_000)
  timer.clear_timeout(id)
}

pub fn set_and_clear_interval_test() {
  let id = timer.set_interval(fn() { Nil }, 100_000)
  timer.clear_interval(id)
}
