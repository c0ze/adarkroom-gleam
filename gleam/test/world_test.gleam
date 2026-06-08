import adarkroom/rng
import adarkroom/world
import gleam/dict
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

import gleam/int

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
