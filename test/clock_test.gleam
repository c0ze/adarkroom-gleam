import adarkroom/clock
import gleeunit/should

pub fn now_is_positive_test() {
  should.be_true(clock.now() >. 0.0)
}

pub fn perf_now_is_non_negative_test() {
  should.be_true(clock.perf_now() >=. 0.0)
}

pub fn the_game_clock_starts_at_the_wall_clock_test() {
  clock.speed() |> should.equal(1)
  let gap = clock.now() -. clock.wall_now()
  should.be_true(gap >=. -5.0 && gap <=. 5.0)
}

pub fn changing_speed_carries_the_clock_on_without_a_jump_test() {
  let before = clock.now()
  clock.set_speed(2)
  clock.speed() |> should.equal(2)
  let after = clock.now()
  should.be_true(after >=. before && after -. before <. 50.0)
  clock.set_speed(1)
  clock.speed() |> should.equal(1)
  should.be_true(clock.now() >=. after)
}
