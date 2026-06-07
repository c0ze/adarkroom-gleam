import adarkroom/outside
import adarkroom/state
import gleeunit/should

pub fn gather_wood_gives_ten_by_hand_test() {
  let #(s, msgs) = outside.gather_wood(state.new())
  state.get_store(s, "wood") |> should.equal(10)
  msgs
  |> should.equal(["dry brush and dead branches litter the forest floor"])
}

pub fn gather_wood_gives_fifty_with_a_cart_test() {
  let s = state.new() |> state.set_game("building.cart", 1)
  let #(s2, _) = outside.gather_wood(s)
  state.get_store(s2, "wood") |> should.equal(50)
}

pub fn gather_wood_accumulates_test() {
  let #(s, _) = outside.gather_wood(state.new())
  let #(s2, _) = outside.gather_wood(s)
  state.get_store(s2, "wood") |> should.equal(20)
}

pub fn first_arrival_notes_the_forest_once_test() {
  let #(s, msgs) = outside.see_forest(state.new())
  msgs
  |> should.equal(["the sky is grey and the wind blows relentlessly"])
  // A second arrival is quiet.
  let #(_, msgs2) = outside.see_forest(s)
  msgs2 |> should.equal([])
}

// --- check traps ------------------------------------------------------------

pub fn num_drops_counts_traps_plus_capped_bait_test() {
  let two_traps = state.new() |> state.set_game("building.trap", 2)
  // No bait: one drop per trap.
  outside.num_drops(two_traps) |> should.equal(2)
  // Bait adds drops, capped at the number of traps.
  outside.num_drops(two_traps |> state.set_store("bait", 1)) |> should.equal(3)
  outside.num_drops(two_traps |> state.set_store("bait", 5)) |> should.equal(4)
}

pub fn check_traps_yields_a_single_drop_test() {
  let s = state.new() |> state.set_game("building.trap", 1)
  let #(s2, msgs) = outside.check_traps(s, [0.1])
  state.get_store(s2, "fur") |> should.equal(1)
  msgs |> should.equal(["the traps contain scraps of fur"])
}

pub fn check_traps_lists_distinct_drops_with_and_test() {
  let s = state.new() |> state.set_game("building.trap", 3)
  // fur, meat, scales
  let #(s2, msgs) = outside.check_traps(s, [0.1, 0.6, 0.8])
  state.get_store(s2, "fur") |> should.equal(1)
  state.get_store(s2, "meat") |> should.equal(1)
  state.get_store(s2, "scales") |> should.equal(1)
  msgs
  |> should.equal([
    "the traps contain scraps of fur, bits of meat and strange scales",
  ])
}

pub fn check_traps_accumulates_duplicates_but_names_each_once_test() {
  let s = state.new() |> state.set_game("building.trap", 3)
  // fur, fur, meat
  let #(s2, msgs) = outside.check_traps(s, [0.1, 0.2, 0.6])
  state.get_store(s2, "fur") |> should.equal(2)
  state.get_store(s2, "meat") |> should.equal(1)
  msgs |> should.equal(["the traps contain scraps of fur and bits of meat"])
}

pub fn check_traps_consumes_capped_bait_test() {
  let s =
    state.new()
    |> state.set_game("building.trap", 2)
    |> state.set_store("bait", 3)
  // num_drops = 2 + min(3,2) = 4; bait used = 2.
  let #(s2, _) = outside.check_traps(s, [0.1, 0.1, 0.1, 0.1])
  state.get_store(s2, "fur") |> should.equal(4)
  state.get_store(s2, "bait") |> should.equal(1)
}

pub fn check_traps_classifies_each_roll_bucket_test() {
  let s = state.new() |> state.set_game("building.trap", 6)
  // lower bound of each bucket: fur/meat/scales/teeth/cloth/charm
  let #(s2, _) = outside.check_traps(s, [0.0, 0.5, 0.75, 0.85, 0.93, 0.999])
  state.get_store(s2, "fur") |> should.equal(1)
  state.get_store(s2, "meat") |> should.equal(1)
  state.get_store(s2, "scales") |> should.equal(1)
  state.get_store(s2, "teeth") |> should.equal(1)
  state.get_store(s2, "cloth") |> should.equal(1)
  state.get_store(s2, "charm") |> should.equal(1)
}
