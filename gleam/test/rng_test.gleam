import adarkroom/rng
import gleam/list
import gleeunit/should

// The same seed produces the same sequence.
pub fn deterministic_test() {
  let a = rng.seed(42)
  let #(x1, a2) = rng.next(a)
  let #(x2, _) = rng.next(a2)

  let b = rng.seed(42)
  let #(y1, b2) = rng.next(b)
  let #(y2, _) = rng.next(b2)

  should.equal(x1, y1)
  should.equal(x2, y2)
}

// Different seeds diverge.
pub fn distinct_seeds_test() {
  let #(x, _) = rng.next(rng.seed(1))
  let #(y, _) = rng.next(rng.seed(2))
  should.be_true(x != y)
}

// next_float stays within [0.0, 1.0).
pub fn float_unit_interval_test() {
  let #(f, _) = rng.next_float(rng.seed(7))
  should.be_true(f >=. 0.0)
  should.be_true(f <. 1.0)
}

// next_int respects an inclusive range across many draws.
pub fn int_range_test() {
  let s = rng.seed(123)
  let _ =
    list.repeat(Nil, 200)
    |> list.fold(s, fn(acc, _) {
      let #(v, acc2) = rng.next_int(acc, min: 3, max: 7)
      should.be_true(v >= 3)
      should.be_true(v <= 7)
      acc2
    })
  Nil
}

// A single-value range always returns that value.
pub fn int_single_value_test() {
  let #(v, _) = rng.next_int(rng.seed(99), min: 5, max: 5)
  should.equal(v, 5)
}
