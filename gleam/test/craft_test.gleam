import adarkroom/craft
import adarkroom/state
import gleeunit/should

/// A room warm enough for the builder to work (Mild or better).
fn warm() -> state.State {
  state.new() |> state.set_game("temperature", 2)
}

pub fn get_known_returns_craftable_test() {
  let assert Ok(c) = craft.get("trap")
  c.name |> should.equal("trap")
  c.kind |> should.equal(craft.Building)
}

pub fn get_unknown_is_error_test() {
  craft.get("dragon") |> should.equal(Error(Nil))
}

pub fn trap_cost_scales_with_count_test() {
  let assert Ok(c) = craft.get("trap")
  c.cost(state.new()) |> should.equal([#("wood", 10)])
  c.cost(state.new() |> state.set_game("building.trap", 2))
  |> should.equal([#("wood", 30)])
}

pub fn hut_cost_scales_with_count_test() {
  let assert Ok(c) = craft.get("hut")
  c.cost(state.new()) |> should.equal([#("wood", 100)])
  c.cost(state.new() |> state.set_game("building.hut", 1))
  |> should.equal([#("wood", 150)])
}

pub fn lodge_cost_is_multi_component_test() {
  let assert Ok(c) = craft.get("lodge")
  c.cost(state.new())
  |> should.equal([#("wood", 200), #("fur", 10), #("meat", 5)])
}

pub fn building_count_reads_game_test() {
  let s = state.new() |> state.set_game("building.hut", 3)
  craft.building_count(s, "hut") |> should.equal(3)
}

pub fn needs_workshop_classifies_test() {
  craft.needs_workshop(craft.Weapon) |> should.equal(True)
  craft.needs_workshop(craft.Tool) |> should.equal(True)
  craft.needs_workshop(craft.Upgrade) |> should.equal(True)
  craft.needs_workshop(craft.Building) |> should.equal(False)
}

pub fn build_deducts_cost_and_raises_building_test() {
  let s = warm() |> state.set_store("wood", 50)
  let #(s2, msgs) = craft.build(s, "trap")
  state.get_store(s2, "wood") |> should.equal(40)
  craft.building_count(s2, "trap") |> should.equal(1)
  msgs |> should.equal(["more traps to catch more creatures"])
}

pub fn build_blocked_when_too_cold_test() {
  let s =
    state.new()
    |> state.set_game("temperature", 1)
    |> state.set_store("wood", 50)
  let #(s2, msgs) = craft.build(s, "trap")
  craft.building_count(s2, "trap") |> should.equal(0)
  state.get_store(s2, "wood") |> should.equal(50)
  msgs |> should.equal(["builder just shivers"])
}

pub fn build_blocked_when_not_enough_wood_test() {
  let s = warm() |> state.set_store("wood", 5)
  let #(s2, msgs) = craft.build(s, "trap")
  craft.building_count(s2, "trap") |> should.equal(0)
  state.get_store(s2, "wood") |> should.equal(5)
  msgs |> should.equal(["not enough wood"])
}

pub fn build_multi_component_deducts_all_test() {
  let s =
    warm()
    |> state.set_store("wood", 300)
    |> state.set_store("fur", 20)
    |> state.set_store("meat", 10)
  let #(s2, msgs) = craft.build(s, "lodge")
  state.get_store(s2, "wood") |> should.equal(100)
  state.get_store(s2, "fur") |> should.equal(10)
  state.get_store(s2, "meat") |> should.equal(5)
  craft.building_count(s2, "lodge") |> should.equal(1)
  msgs
  |> should.equal(["the hunting lodge stands in the forest, a ways out of town"])
}

pub fn build_multi_component_aborts_on_first_missing_without_deducting_test() {
  // Enough wood, but no fur: report the missing fur, deduct nothing.
  let s = warm() |> state.set_store("wood", 300) |> state.set_store("meat", 10)
  let #(s2, msgs) = craft.build(s, "lodge")
  state.get_store(s2, "wood") |> should.equal(300)
  craft.building_count(s2, "lodge") |> should.equal(0)
  msgs |> should.equal(["not enough fur"])
}

pub fn build_at_maximum_is_silent_noop_test() {
  // cart's maximum is 1; once built, a second build does nothing.
  let s =
    warm() |> state.set_store("wood", 100) |> state.set_game("building.cart", 1)
  let #(s2, msgs) = craft.build(s, "cart")
  craft.building_count(s2, "cart") |> should.equal(1)
  state.get_store(s2, "wood") |> should.equal(100)
  msgs |> should.equal([])
}

pub fn trap_maxes_at_ten_test() {
  let s =
    warm()
    |> state.set_store("wood", 99_999_999)
    |> state.set_game("building.trap", 10)
  let #(s2, msgs) = craft.build(s, "trap")
  craft.building_count(s2, "trap") |> should.equal(10)
  msgs |> should.equal([])
}

pub fn build_weapon_increments_stores_and_has_no_maximum_test() {
  // bone spear: weapon, no maximum, costs wood 100 + teeth 5, counts in stores.
  let s = warm() |> state.set_store("wood", 250) |> state.set_store("teeth", 12)
  let #(s2, _) = craft.build(s, "bone spear")
  state.get_store(s2, "bone spear") |> should.equal(1)
  state.get_store(s2, "wood") |> should.equal(150)
  state.get_store(s2, "teeth") |> should.equal(7)
  craft.building_count(s2, "bone spear") |> should.equal(0)
  // No maximum — can be crafted again.
  let #(s3, _) = craft.build(s2, "bone spear")
  state.get_store(s3, "bone spear") |> should.equal(2)
}

pub fn unknown_build_is_noop_test() {
  let s = warm() |> state.set_store("wood", 99_999)
  let #(s2, msgs) = craft.build(s, "dragon")
  msgs |> should.equal([])
  state.get_store(s2, "wood") |> should.equal(99_999)
}
