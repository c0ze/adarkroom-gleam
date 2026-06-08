import adarkroom/path
import adarkroom/state
import gleeunit/should

pub fn weight_defaults_to_one_test() {
  path.weight("fur") |> should.equal(1.0)
  path.weight("bullets") |> should.equal(0.1)
  path.weight("bolas") |> should.equal(0.5)
  path.weight("steel sword") |> should.equal(5.0)
}

pub fn capacity_grows_with_carry_upgrades_test() {
  path.capacity(state.new()) |> should.equal(10)
  path.capacity(state.new() |> state.set_store("rucksack", 1))
  |> should.equal(20)
  path.capacity(state.new() |> state.set_store("wagon", 1)) |> should.equal(40)
  path.capacity(state.new() |> state.set_store("convoy", 1)) |> should.equal(70)
  // The largest upgrade wins.
  path.capacity(
    state.new()
    |> state.set_store("rucksack", 1)
    |> state.set_store("convoy", 1),
  )
  |> should.equal(70)
}

pub fn free_space_subtracts_packed_weight_test() {
  let s = state.new() |> state.set_outfit("cured meat", 3)
  path.free_space(s) |> should.equal(7.0)
}

pub fn increase_supply_packs_up_to_what_is_asked_test() {
  let s = state.new() |> state.set_store("cured meat", 5)
  path.increase_supply(s, "cured meat", 3)
  |> state.get_outfit("cured meat")
  |> should.equal(3)
}

pub fn increase_supply_capped_by_store_test() {
  let s = state.new() |> state.set_store("cured meat", 2)
  path.increase_supply(s, "cured meat", 10)
  |> state.get_outfit("cured meat")
  |> should.equal(2)
}

pub fn increase_supply_capped_by_weight_test() {
  // Bone spears weigh 2 — at most 5 fit in a 10-space bag.
  let s = state.new() |> state.set_store("bone spear", 100)
  path.increase_supply(s, "bone spear", 100)
  |> state.get_outfit("bone spear")
  |> should.equal(5)
}

pub fn increase_supply_handles_fractional_weight_test() {
  // Bullets weigh 0.1 — 100 fit in a 10-space bag.
  let s = state.new() |> state.set_store("bullets", 1000)
  path.increase_supply(s, "bullets", 1000)
  |> state.get_outfit("bullets")
  |> should.equal(100)
}

pub fn increase_supply_noop_when_full_test() {
  let s =
    state.new()
    |> state.set_store("fur", 50)
    |> state.set_outfit("fur", 10)
  // The bag already holds 10 units (capacity 10) — nothing more fits.
  path.increase_supply(s, "fur", 1)
  |> state.get_outfit("fur")
  |> should.equal(10)
}

pub fn decrease_supply_unpacks_down_to_zero_test() {
  let s = state.new() |> state.set_outfit("cured meat", 3)
  path.decrease_supply(s, "cured meat", 1)
  |> state.get_outfit("cured meat")
  |> should.equal(2)
  path.decrease_supply(s, "cured meat", 10)
  |> state.get_outfit("cured meat")
  |> should.equal(0)
}

import gleam/list

pub fn carryable_lists_owned_tools_and_weapons_test() {
  let s =
    state.new()
    |> state.set_store("cured meat", 5)
    |> state.set_store("bone spear", 1)
    |> state.set_store("fur", 99)
  let names = path.carryable(s) |> list.map(fn(c) { c.0 })
  list.contains(names, "cured meat") |> should.equal(True)
  list.contains(names, "bone spear") |> should.equal(True)
  // Ordinary resources are not carried as supplies.
  list.contains(names, "fur") |> should.equal(False)
}

pub fn carryable_is_empty_with_nothing_owned_test() {
  path.carryable(state.new()) |> should.equal([])
}

pub fn armour_reflects_the_best_owned_test() {
  path.armour(state.new()) |> should.equal("none")
  path.armour(state.new() |> state.set_store("l armour", 1))
  |> should.equal("leather")
  path.armour(
    state.new()
    |> state.set_store("l armour", 1)
    |> state.set_store("s armour", 1),
  )
  |> should.equal("steel")
}
