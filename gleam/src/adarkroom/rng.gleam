//// Random number generation for the port.
////
//// `random` wraps `Math.random` (non-deterministic) for ordinary gameplay.
//// `Seed` is a pure, deterministic Park–Miller (minimal-standard) generator
//// used where reproducibility matters: tests, debugging, replayable worldgen.
//// Every seeded operation is pure — it threads a fresh `Seed` through its
//// return value rather than mutating in place.

import gleam/float
import gleam/int

/// Non-deterministic float in `[0.0, 1.0)`, backed by `Math.random`.
@external(javascript, "./rng_ffi.mjs", "random")
pub fn random() -> Float

const modulus = 2_147_483_647

/// An opaque, deterministic PRNG state.
pub opaque type Seed {
  Seed(state: Int)
}

/// Build a `Seed` from any integer, normalising the state into the
/// generator's valid range `[1, modulus - 1]`.
pub fn seed(from: Int) -> Seed {
  let s = int.absolute_value(from) % modulus
  case s < 1 {
    True -> Seed(state: 1)
    False -> Seed(state: s)
  }
}

/// Advance the generator, returning the next raw value in `[1, modulus - 1]`
/// together with the new `Seed`.
pub fn next(s: Seed) -> #(Int, Seed) {
  let next_state = s.state * 16_807 % modulus
  #(next_state, Seed(state: next_state))
}

/// Next float in `[0.0, 1.0)` and the new `Seed`.
pub fn next_float(s: Seed) -> #(Float, Seed) {
  let #(v, s2) = next(s)
  #(int.to_float(v) /. int.to_float(modulus), s2)
}

/// Next integer in the inclusive range `[min, max]` and the new `Seed`.
///
/// Requires `min <= max`.
pub fn next_int(s: Seed, min min: Int, max max: Int) -> #(Int, Seed) {
  let #(f, s2) = next_float(s)
  let span = int.to_float(max - min + 1)
  #(min + float.truncate(f *. span), s2)
}
