import adarkroom/rng
import adarkroom/state
import adarkroom/world
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
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

// --- expedition: movement & fog ---------------------------------------------

pub fn begin_starts_at_the_village_with_full_vitals_test() {
  let s = state.new() |> state.set_store("waterskin", 1)
  let exp = world.begin(world.generate_map(rng.seed(1)), s)
  exp.pos |> should.equal(#(30, 30))
  exp.vitals.water |> should.equal(20)
  exp.vitals.health |> should.equal(10)
}

pub fn begin_reveals_only_the_starting_diamond_test() {
  let exp = world.begin(world.generate_map(rng.seed(1)), state.new())
  set.contains(exp.seen, #(30, 30)) |> should.equal(True)
  // Manhattan distance 2 is lit; distance 3 is not.
  set.contains(exp.seen, #(28, 30)) |> should.equal(True)
  set.contains(exp.seen, #(27, 30)) |> should.equal(False)
}

pub fn moving_steps_drains_water_and_widens_sight_test() {
  let s = state.new() |> state.set_outfit("cured meat", 5)
  let exp = world.begin(world.generate_map(rng.seed(1)), s)
  let step = world.move(s, exp, world.East)
  step.expedition.pos |> should.equal(#(31, 30))
  step.expedition.vitals.water |> should.equal(9)
  step.alive |> should.equal(True)
  // Newly-reached ground is now lit.
  set.contains(step.expedition.seen, #(33, 30)) |> should.equal(True)
}

pub fn moving_is_blocked_at_the_edge_of_the_world_test() {
  let s = state.new() |> state.set_outfit("cured meat", 5)
  let exp =
    world.Expedition(..world.begin(world.generate_map(rng.seed(1)), s), pos: #(
      30,
      0,
    ))
  let step = world.move(s, exp, world.North)
  step.expedition.pos |> should.equal(#(30, 0))
}

pub fn the_scout_perk_widens_sight_test() {
  let s = state.new() |> state.add_perk("scout")
  let exp = world.begin(world.generate_map(rng.seed(1)), s)
  // Sight radius doubles to 4.
  set.contains(exp.seen, #(26, 30)) |> should.equal(True)
  set.contains(exp.seen, #(25, 30)) |> should.equal(False)
}

// --- map render -------------------------------------------------------------

pub fn tile_char_maps_tiles_to_their_codes_test() {
  world.tile_char(world.Village) |> should.equal("A")
  world.tile_char(world.Forest) |> should.equal(";")
  world.tile_char(world.Ship) |> should.equal("W")
  world.tile_char(world.IronMine) |> should.equal("I")
}

pub fn render_is_sixty_one_rows_test() {
  let exp = world.begin(world.generate_map(rng.seed(1)), state.new())
  list.length(world.render(exp)) |> should.equal(61)
}

pub fn render_marks_the_wanderer_at_the_centre_test() {
  let exp = world.begin(world.generate_map(rng.seed(1)), state.new())
  let assert Ok(row) = list.drop(world.render(exp), 30) |> list.first
  string.slice(row, 30, 1) |> should.equal("@")
}

pub fn render_shows_the_forest_beside_the_village_test() {
  let exp = world.begin(world.generate_map(rng.seed(1)), state.new())
  let assert Ok(row) = list.drop(world.render(exp), 30) |> list.first
  // The village's orthogonal neighbour is forest, and it is within sight.
  string.slice(row, 29, 1) |> should.equal(";")
}

pub fn render_hides_unseen_ground_test() {
  let exp = world.begin(world.generate_map(rng.seed(1)), state.new())
  let assert Ok(row) = list.first(world.render(exp))
  // A far corner has not been seen.
  string.slice(row, 0, 1) |> should.equal(" ")
}

pub fn distance_is_manhattan_from_the_village_test() {
  // The village sits at the centre (radius, radius).
  world.distance(#(world.radius, world.radius)) |> should.equal(0)
  world.distance(#(world.radius + 3, world.radius)) |> should.equal(3)
  world.distance(#(world.radius - 2, world.radius + 4)) |> should.equal(6)
}

// --- setpiece landmarks -----------------------------------------------------

pub fn landmark_tiles_map_to_their_setpiece_test() {
  world.setpiece_scene(world.Outpost) |> should.equal(Ok("outpost"))
  world.setpiece_scene(world.Swamp) |> should.equal(Ok("swamp"))
  world.setpiece_scene(world.City) |> should.equal(Ok("city"))
  // Terrain, roads, the village and the executioner have no setpiece key here.
  world.setpiece_scene(world.Forest) |> should.be_error
  world.setpiece_scene(world.Village) |> should.be_error
  world.setpiece_scene(world.Executioner) |> should.be_error
}

/// An expedition standing on `tile` at the centre.
fn standing_on(tile: world.Tile) -> world.Expedition {
  let pos = #(world.radius, world.radius)
  world.Expedition(
    pos: pos,
    map: dict.from_list([#(pos, tile)]),
    seen: set.new(),
    vitals: world.Vitals(10, 10, 0, 0, False, False),
    visited: set.new(),
    used_outposts: set.new(),
  )
}

pub fn a_fresh_landmark_triggers_its_setpiece_test() {
  world.should_trigger_setpiece(
    standing_on(world.Battlefield),
    world.Battlefield,
  )
  |> should.be_true
  // Open ground never does.
  world.should_trigger_setpiece(standing_on(world.Forest), world.Forest)
  |> should.be_false
}

pub fn a_visited_landmark_does_not_trigger_again_test() {
  let exp = world.mark_visited(standing_on(world.Battlefield))
  world.should_trigger_setpiece(exp, world.Battlefield) |> should.be_false
}

pub fn an_unused_outpost_triggers_but_a_used_one_does_not_test() {
  let exp = standing_on(world.Outpost)
  world.should_trigger_setpiece(exp, world.Outpost) |> should.be_true
  let used = world.use_outpost(exp, state.new())
  world.should_trigger_setpiece(used, world.Outpost) |> should.be_false
}

pub fn using_an_outpost_refills_water_to_the_brim_test() {
  let s = state.new() |> state.set_store("water tank", 1)
  let exp =
    world.Expedition(
      ..standing_on(world.Outpost),
      vitals: world.Vitals(3, 10, 0, 0, False, False),
    )
  let refilled = world.use_outpost(exp, s)
  refilled.vitals.water |> should.equal(world.max_water(s))
}
