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
  beast.enemy.attack_delay |> should.equal(1)
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
