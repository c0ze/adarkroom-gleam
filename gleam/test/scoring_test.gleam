import adarkroom/scoring
import adarkroom/state
import gleam/list
import gleeunit/should

pub fn the_score_weighs_the_roster_test() {
  // 10 wood ×1 + 10 fur ×1.5 + 2 rifles ×150 = 325, floored once.
  let s =
    state.new()
    |> state.set_store("wood", 10)
    |> state.set_store("fur", 10)
    |> state.set_store("rifle", 2)
  scoring.calculate_score(s) |> should.equal(325)
}

pub fn fractions_accumulate_before_the_floor_test() {
  // 1 fur (1.5) + 1 bait (1.5) = 3.0 — two halves make a whole point.
  let s =
    state.new()
    |> state.set_store("fur", 1)
    |> state.set_store("bait", 1)
  scoring.calculate_score(s) |> should.equal(3)
}

pub fn the_endgame_currencies_count_extra_test() {
  let s =
    state.new()
    |> state.set_store("alien alloy", 2)
    |> state.set_store("fleet beacon", 1)
    |> state.set_game("spaceShip.hull", 3)
  // 20 + 500 + 150.
  scoring.calculate_score(s) |> should.equal(670)
}

pub fn reduction_divides_by_the_rolled_divisors_test() {
  // wood is first (a good): roll 0.55 → divisor 5; everything else empty.
  let s = state.new() |> state.set_store("wood", 100)
  let rolls = list.repeat(0.55, scoring.rolls_needed())
  let assert [wood, ..rest] = scoring.reduced_stores(s, rolls)
  wood |> should.equal(20)
  list.all(rest, fn(v) { v == 0 }) |> should.be_true
}

pub fn a_zero_divisor_is_coerced_to_one_test() {
  // A 0.05 roll gives floor(0.5) = 0 → divisor 1: the store carries whole.
  let s = state.new() |> state.set_store("wood", 7)
  let rolls = list.repeat(0.05, scoring.rolls_needed())
  let assert [wood, ..] = scoring.reduced_stores(s, rolls)
  wood |> should.equal(7)
}

pub fn ammunition_takes_two_rolls_test() {
  scoring.rolls_needed() |> should.equal(28)
}
