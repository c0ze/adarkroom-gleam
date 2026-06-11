import adarkroom/clock
import gleeunit/should

pub fn now_is_positive_test() {
  should.be_true(clock.now() >. 0.0)
}

pub fn perf_now_is_non_negative_test() {
  should.be_true(clock.perf_now() >=. 0.0)
}
