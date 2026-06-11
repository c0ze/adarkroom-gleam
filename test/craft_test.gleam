import adarkroom/craft
import adarkroom/state
import gleam/list
import gleam/set
import gleeunit/should

/// A room warm enough for the builder to work (Mild or better).
fn warm() -> state.State {
  state.new() |> state.set_game("temperature", 2)
}

/// A state where the builder is helping (the crafting gate).
fn helping() -> state.State {
  state.new() |> state.set_game("builder", 4)
}

const trap_available = "builder says she can make traps to catch any creatures might still be alive out there"

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

// --- reveal gating ----------------------------------------------------------

pub fn reveal_nothing_before_builder_helps_test() {
  // Plenty of wood, but the builder is only "up" (level 3), not helping.
  let s =
    state.new() |> state.set_game("builder", 3) |> state.set_store("wood", 9999)
  let #(seen, msgs) = craft.reveal(s, set.new())
  set.size(seen) |> should.equal(0)
  msgs |> should.equal([])
}

pub fn reveal_building_when_helping_and_resourced_test() {
  // trap costs 10 wood; revealed once you hold at least half (5).
  let s = helping() |> state.set_store("wood", 5)
  let #(seen, msgs) = craft.reveal(s, set.new())
  set.contains(seen, "trap") |> should.equal(True)
  // cart needs 15 (half of 30) — still hidden at 5 wood.
  set.contains(seen, "cart") |> should.equal(False)
  list.contains(msgs, trap_available) |> should.equal(True)
}

pub fn reveal_is_idempotent_and_quiet_once_seen_test() {
  let s = helping() |> state.set_store("wood", 5)
  let #(seen1, _) = craft.reveal(s, set.new())
  let #(seen2, msgs2) = craft.reveal(s, seen1)
  set.contains(seen2, "trap") |> should.equal(True)
  list.contains(msgs2, trap_available) |> should.equal(False)
}

pub fn reveal_requires_all_components_seen_test() {
  // lodge: wood 200, fur 10, meat 5 — needs half the wood AND some fur AND meat.
  let wood_only = helping() |> state.set_store("wood", 100)
  let #(seen, _) = craft.reveal(wood_only, set.new())
  set.contains(seen, "lodge") |> should.equal(False)
  let resourced =
    helping()
    |> state.set_store("wood", 100)
    |> state.set_store("fur", 1)
    |> state.set_store("meat", 1)
  let #(seen2, _) = craft.reveal(resourced, set.new())
  set.contains(seen2, "lodge") |> should.equal(True)
}

pub fn reveal_workshop_crafts_gated_on_workshop_test() {
  // bone spear (weapon) needs the workshop; trap (building) does not.
  let s =
    helping() |> state.set_store("wood", 9999) |> state.set_store("teeth", 9)
  let #(seen, _) = craft.reveal(s, set.new())
  set.contains(seen, "trap") |> should.equal(True)
  set.contains(seen, "bone spear") |> should.equal(False)
  let with_shop = s |> state.set_game("building.workshop", 1)
  let #(seen2, _) = craft.reveal(with_shop, set.new())
  set.contains(seen2, "bone spear") |> should.equal(True)
}

pub fn reveal_already_built_ignores_resources_and_is_quiet_test() {
  // A trap already stands, but no wood remains: still shown, no availability note.
  let s = helping() |> state.set_game("building.trap", 1)
  let #(seen, msgs) = craft.reveal(s, set.new())
  set.contains(seen, "trap") |> should.equal(True)
  list.contains(msgs, trap_available) |> should.equal(False)
}

pub fn visible_splits_buildings_from_crafts_test() {
  let revealed = set.from_list(["trap", "cart", "bone spear", "waterskin"])
  let #(builds, crafts) = craft.visible(revealed)
  // Each section keeps table order: waterskin (upgrade) precedes bone spear.
  list.map(builds, fn(p) { p.0 }) |> should.equal(["trap", "cart"])
  list.map(crafts, fn(p) { p.0 }) |> should.equal(["waterskin", "bone spear"])
}
