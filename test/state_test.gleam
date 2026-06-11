import adarkroom/state
import gleam/list
import gleeunit/should

pub fn new_state_is_empty_test() {
  let s = state.new()
  state.get_store(s, "wood") |> should.equal(0)
  state.has_feature(s, "fire") |> should.equal(False)
}

pub fn set_and_get_store_test() {
  let s = state.new() |> state.set_store("wood", 5)
  state.get_store(s, "wood") |> should.equal(5)
}

pub fn add_store_test() {
  let s =
    state.new()
    |> state.set_store("wood", 5)
    |> state.add_store("wood", 3)
  state.get_store(s, "wood") |> should.equal(8)
}

pub fn stores_clamp_negative_test() {
  let s =
    state.new()
    |> state.set_store("wood", 5)
    |> state.add_store("wood", -10)
  state.get_store(s, "wood") |> should.equal(0)
}

pub fn stores_clamp_max_test() {
  let s =
    state.new()
    |> state.set_store("wood", state.max_store)
    |> state.add_store("wood", 100)
  state.get_store(s, "wood") |> should.equal(state.max_store)
}

// Direct set_store boundary tests, so the invariant holds independently of
// add_store.
pub fn set_store_clamp_negative_test() {
  let s = state.new() |> state.set_store("wood", -1)
  state.get_store(s, "wood") |> should.equal(0)
}

pub fn set_store_clamp_max_test() {
  let s = state.new() |> state.set_store("wood", state.max_store + 1)
  state.get_store(s, "wood") |> should.equal(state.max_store)
}

pub fn set_feature_test() {
  let s = state.new() |> state.set_feature("fire", True)
  state.has_feature(s, "fire") |> should.equal(True)
}

pub fn stores_list_sorted_test() {
  let s =
    state.new()
    |> state.set_store("wood", 2)
    |> state.set_store("fur", 5)
  state.stores_list(s) |> should.equal([#("fur", 5), #("wood", 2)])
}

pub fn stores_list_empty_test() {
  state.stores_list(state.new()) |> should.equal([])
}

pub fn every_perk_announces_its_lesson_test() {
  state.perk_notify("stealthy") |> should.equal("learned how not to be seen")
  state.perk_notify("gastronome")
  |> should.equal("learned to make the most of food")
  state.perk_notify("barbarian")
  |> should.equal("learned to swing weapons with force")
}

pub fn the_perk_table_speaks_for_each_test() {
  // The full Engine.Perks copy, verbatim.
  state.perk_table()
  |> list.map(state.perk_desc)
  |> should.equal([
    "punches do more damage",
    "punches do even more damage.",
    "punch twice as fast, and with even more force",
    "melee weapons deal more damage",
    "go twice as far without eating",
    "go twice as far without drinking",
    "dodge attacks more effectively",
    "land blows more often",
    "see farther",
    "better avoid conflict in the wild",
    "restore more health when eating",
  ])
}

pub fn owned_perks_keep_the_table_order_test() {
  let s =
    state.new()
    |> state.add_perk("gastronome")
    |> state.add_perk("boxer")
  state.owned_perks(s) |> should.equal(["boxer", "gastronome"])
}
