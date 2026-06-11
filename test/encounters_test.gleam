import adarkroom/encounters
import adarkroom/world
import gleam/list
import gleeunit/should

pub fn tier_one_forest_holds_the_snarling_beast_test() {
  encounters.available(5, world.Forest)
  |> list.map(fn(e) { e.title })
  |> should.equal(["A Snarling Beast"])
}

pub fn the_field_has_two_tier_one_encounters_test() {
  // The strange bird and the two-headed creature both roam the fields.
  encounters.available(5, world.Field) |> list.length |> should.equal(2)
}

pub fn tier_one_stops_past_distance_ten_test() {
  let has_beast = fn(d) {
    encounters.available(d, world.Forest)
    |> list.any(fn(e) { e.title == "A Snarling Beast" })
  }
  has_beast(10) |> should.equal(True)
  has_beast(11) |> should.equal(False)
}

pub fn the_snarling_beast_has_its_stats_and_loot_test() {
  let assert Ok(beast) = list.first(encounters.available(3, world.Forest))
  beast.enemy.health |> should.equal(5)
  beast.enemy.damage |> should.equal(1)
  beast.enemy.hit |> should.equal(0.8)
  beast.enemy.attack_delay |> should.equal(1.0)
  beast.enemy.chara |> should.equal("R")
  beast.enemy.loot
  |> list.map(fn(l) { l.name })
  |> should.equal(["fur", "meat", "teeth"])
}

pub fn the_barrens_holds_the_gaunt_man_test() {
  encounters.available(5, world.Barrens)
  |> list.map(fn(e) { e.title })
  |> should.equal(["A Gaunt Man"])
}

pub fn tier_two_deepens_the_danger_test() {
  // Beyond ten tiles the tier-1 foes give way to tougher ones.
  encounters.available(15, world.Forest)
  |> list.map(fn(e) { e.title })
  |> should.equal(["A Man-Eater"])
  // The barrens hold two: the shivering man and the scavenger.
  encounters.available(15, world.Barrens) |> list.length |> should.equal(2)
}

pub fn tier_three_holds_ranged_foes_test() {
  let assert Ok(soldier) = list.first(encounters.available(25, world.Barrens))
  soldier.enemy.name |> should.equal("soldier")
  soldier.enemy.ranged |> should.equal(True)
  soldier.enemy.damage |> should.equal(8)
  soldier.enemy.health |> should.equal(50)
}

pub fn the_pool_spans_all_three_tiers_test() {
  // 4 tier-1 + 4 tier-2 + 3 tier-3.
  encounters.encounters() |> list.length |> should.equal(11)
}
