import adarkroom/rng
import adarkroom/state
import adarkroom/world
import gleam/dict
import gleam/int
import gleam/list
import gleeunit/should

pub fn terrain_places_the_village_at_the_centre_test() {
  let map = world.generate_terrain(rng.seed(1)).0
  world.tile_at(map, 30, 30) |> should.equal(Ok(world.Village))
}

pub fn terrain_fills_the_whole_grid_test() {
  let map = world.generate_terrain(rng.seed(1)).0
  // A 61 x 61 grid.
  dict.size(map) |> should.equal(3721)
}

pub fn terrain_is_only_terrain_or_village_test() {
  let map = world.generate_terrain(rng.seed(7)).0
  dict.values(map)
  |> list.all(fn(t) { world.is_terrain(t) || t == world.Village })
  |> should.equal(True)
}

pub fn the_village_sits_in_a_forest_test() {
  let map = world.generate_terrain(rng.seed(3)).0
  // The four orthogonal neighbours of the village are always forest.
  world.tile_at(map, 29, 30) |> should.equal(Ok(world.Forest))
  world.tile_at(map, 31, 30) |> should.equal(Ok(world.Forest))
  world.tile_at(map, 30, 29) |> should.equal(Ok(world.Forest))
  world.tile_at(map, 30, 31) |> should.equal(Ok(world.Forest))
}

pub fn terrain_is_deterministic_for_a_seed_test() {
  world.generate_terrain(rng.seed(42)).0
  |> should.equal(world.generate_terrain(rng.seed(42)).0)
}

pub fn different_seeds_give_different_terrain_test() {
  let a = world.generate_terrain(rng.seed(1)).0
  let b = world.generate_terrain(rng.seed(99)).0
  { a == b } |> should.equal(False)
}

fn count(map: world.Map, tile: world.Tile) -> Int {
  dict.values(map) |> list.filter(fn(t) { t == tile }) |> list.length
}

pub fn map_places_each_landmark_the_right_number_of_times_test() {
  let map = world.generate_map(rng.seed(5))
  count(map, world.IronMine) |> should.equal(1)
  count(map, world.CoalMine) |> should.equal(1)
  count(map, world.SulphurMine) |> should.equal(1)
  count(map, world.Ship) |> should.equal(1)
  count(map, world.Executioner) |> should.equal(1)
  count(map, world.House) |> should.equal(10)
  count(map, world.Cave) |> should.equal(5)
  count(map, world.Town) |> should.equal(10)
  count(map, world.City) |> should.equal(20)
  count(map, world.Borehole) |> should.equal(10)
  count(map, world.Battlefield) |> should.equal(5)
  count(map, world.Swamp) |> should.equal(1)
}

pub fn map_keeps_the_village_at_the_centre_test() {
  world.tile_at(world.generate_map(rng.seed(5)), 30, 30)
  |> should.equal(Ok(world.Village))
}

pub fn map_generation_is_deterministic_test() {
  world.generate_map(rng.seed(8))
  |> should.equal(world.generate_map(rng.seed(8)))
}

pub fn the_crashed_ship_lands_at_radius_28_test() {
  let map = world.generate_map(rng.seed(5))
  let assert [pos, ..] = world.positions_of(map, world.Ship)
  int.absolute_value(pos.0 - 30) + int.absolute_value(pos.1 - 30)
  |> should.equal(28)
}

// --- survival ---------------------------------------------------------------

fn fresh() -> world.Vitals {
  world.Vitals(
    water: 10,
    health: 10,
    food_move: 0,
    water_move: 0,
    starvation: False,
    thirst: False,
  )
}

pub fn max_water_grows_with_upgrades_test() {
  world.max_water(state.new()) |> should.equal(10)
  world.max_water(state.new() |> state.set_store("waterskin", 1))
  |> should.equal(20)
  world.max_water(state.new() |> state.set_store("water tank", 1))
  |> should.equal(60)
}

pub fn max_health_grows_with_armour_test() {
  world.max_health(state.new()) |> should.equal(10)
  world.max_health(state.new() |> state.set_store("l armour", 1))
  |> should.equal(15)
  world.max_health(state.new() |> state.set_store("s armour", 1))
  |> should.equal(45)
}

pub fn meat_heal_doubles_with_gastronome_test() {
  world.meat_heal(state.new()) |> should.equal(8)
  world.meat_heal(state.new() |> state.add_perk("gastronome"))
  |> should.equal(16)
}

pub fn every_move_drinks_one_water_test() {
  let s = state.new() |> state.set_outfit("cured meat", 5)
  let r = world.use_supplies(s, fresh())
  r.vitals.water |> should.equal(9)
  r.alive |> should.equal(True)
}

pub fn food_is_eaten_every_two_moves_and_heals_test() {
  let s = state.new() |> state.set_outfit("cured meat", 5)
  let v = world.Vitals(..fresh(), food_move: 1, health: 5)
  let r = world.use_supplies(s, v)
  state.get_outfit(r.state, "cured meat") |> should.equal(4)
  // 5 + 8 heal, capped at max health 10.
  r.vitals.health |> should.equal(10)
  r.vitals.food_move |> should.equal(0)
}

pub fn dehydration_kills_on_the_second_dry_move_test() {
  let s = state.new() |> state.set_outfit("cured meat", 5)
  let r1 = world.use_supplies(s, world.Vitals(..fresh(), water: 0))
  r1.alive |> should.equal(True)
  r1.vitals.thirst |> should.equal(True)
  let r2 = world.use_supplies(r1.state, r1.vitals)
  r2.alive |> should.equal(False)
}

pub fn enough_starvation_grants_slow_metabolism_test() {
  let s = state.new() |> state.set_character("starved", 9)
  // food due (food_move 1 -> 2), no meat, already starving -> 10th starvation.
  let v = world.Vitals(..fresh(), food_move: 1, starvation: True)
  let r = world.use_supplies(s, v)
  r.alive |> should.equal(False)
  state.has_perk(r.state, "slow metabolism") |> should.equal(True)
}
