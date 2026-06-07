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

// --- income -----------------------------------------------------------------

pub fn collect_income_gives_builder_wood_when_helping_test() {
  let s = state.new() |> state.set_game("builder", 4)
  outside.collect_income(s) |> state.get_store("wood") |> should.equal(2)
}

pub fn collect_income_idle_before_builder_helps_test() {
  let s = state.new() |> state.set_game("builder", 3)
  outside.collect_income(s) |> state.get_store("wood") |> should.equal(0)
}

pub fn collect_income_accumulates_over_collections_test() {
  let s = state.new() |> state.set_game("builder", 4)
  outside.collect_income(outside.collect_income(s))
  |> state.get_store("wood")
  |> should.equal(4)
}

// --- village & population ---------------------------------------------------

pub fn max_population_is_four_per_hut_test() {
  outside.max_population(state.new()) |> should.equal(0)
  outside.max_population(state.new() |> state.set_game("building.hut", 2))
  |> should.equal(8)
}

pub fn increase_population_adds_and_notifies_test() {
  // 2 huts → room for 8; empty, roll 0.0 → num = floor(0*4 + 4) = 4.
  let s = state.new() |> state.set_game("building.hut", 2)
  let #(s2, msgs) = outside.increase_population(s, 0.0)
  outside.population(s2) |> should.equal(4)
  msgs |> should.equal(["a weathered family takes up in one of the huts."])
}

pub fn increase_population_single_stranger_test() {
  // 1 hut (room 4), 3 already → space 1, roll 0.0 → num = max(floor(0.5), 1) = 1.
  let s =
    state.new()
    |> state.set_game("building.hut", 1)
    |> state.set_game("population", 3)
  let #(s2, msgs) = outside.increase_population(s, 0.0)
  outside.population(s2) |> should.equal(4)
  msgs |> should.equal(["a stranger arrives in the night"])
}

pub fn increase_population_noop_when_full_test() {
  let s =
    state.new()
    |> state.set_game("building.hut", 1)
    |> state.set_game("population", 4)
  let #(s2, msgs) = outside.increase_population(s, 0.5)
  outside.population(s2) |> should.equal(4)
  msgs |> should.equal([])
}

pub fn increase_population_message_scales_with_size_test() {
  let with_huts = fn(n) { state.new() |> state.set_game("building.hut", n) }
  // small group: 2 huts, roll 0.5 → floor(0.5*4 + 4) = 6.
  outside.increase_population(with_huts(2), 0.5).1
  |> should.equal(["a small group arrives, all dust and bones."])
  // convoy: 5 huts, roll 0.5 → floor(0.5*10 + 10) = 15.
  outside.increase_population(with_huts(5), 0.5).1
  |> should.equal(["a convoy lurches in, equal parts worry and hope."])
  // booming: 20 huts, roll 0.5 → floor(0.5*40 + 40) = 60.
  outside.increase_population(with_huts(20), 0.5).1
  |> should.equal(["the town's booming. word does get around."])
}

pub fn outside_title_tracks_the_huts_test() {
  outside.title(state.new()) |> should.equal("A Silent Forest")
  outside.title(state.new() |> state.set_game("building.hut", 1))
  |> should.equal("A Lonely Hut")
  outside.title(state.new() |> state.set_game("building.hut", 3))
  |> should.equal("A Tiny Village")
  outside.title(state.new() |> state.set_game("building.hut", 12))
  |> should.equal("A Large Village")
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
