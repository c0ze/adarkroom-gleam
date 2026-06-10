import adarkroom/combat
import adarkroom/events
import adarkroom/setpieces
import adarkroom/state
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

/// The current scene of a setpiece, by name.
fn scene(name: String, scene_name: String) -> events.Scene {
  let assert Ok(event) = setpieces.setpiece(name)
  let assert Ok(scene) = list.key_find(event.scenes, scene_name)
  scene
}

pub fn the_registry_has_the_ported_setpieces_test() {
  ["outpost", "swamp", "battlefield", "borehole"]
  |> list.each(fn(name) { setpieces.setpiece(name) |> should.be_ok })
}

pub fn every_setpiece_is_ported_test() {
  // All 13 landmarks resolve; the executioner rides its own registry, and
  // unknown keys still error.
  setpieces.setpiece("cache") |> should.be_ok
  setpieces.setpiece("executioner") |> should.be_error
  setpieces.setpiece("nonsense") |> should.be_error
}

pub fn the_destroyed_village_claims_the_cache_test() {
  let assert Ok(ev) = setpieces.setpiece("cache")
  ev.title |> should.equal("A Destroyed Village")
  let assert Ok(start) = list.key_find(ev.scenes, "start")
  start.notification
  |> should.equal(Some(
    "the metallic tang of wanderer afterburner hangs in the air.",
  ))
  // No way out of the shack but with the supplies.
  let assert Ok(underground) = list.key_find(ev.scenes, "underground")
  underground.buttons |> list.map(fn(b) { b.0 }) |> should.equal(["take"])
  let assert Ok(exit) = list.key_find(ev.scenes, "exit")
  let assert Some(extra) = exit.setpiece
  extra.world_effect |> should.equal(events.CollectCache)
}

pub fn the_city_is_a_fifteen_ended_dungeon_test() {
  let assert Ok(event) = setpieces.setpiece("city")
  // start, a1-a4, b1-b8, c1-c13, d1-d11, end1-15.
  list.length(event.scenes) |> should.equal(52)
}

pub fn the_city_swarm_attacks_fast_test() {
  // The elderly-squatter swarm (`c11`) is a plural enemy with a 0.5s delay —
  // the fractional attack delay the city forced `attack_delay` to a Float for.
  let c11 = scene("city", "c11")
  let assert Some(events.SetpieceExtra(enemy: Some(foe), ..)) = c11.setpiece
  foe.name |> should.equal("squatters")
  foe.attack_delay |> should.equal(0.5)
}

pub fn the_city_end_records_the_clear_test() {
  // The end scene's `onLoad` sets `game.cityCleared`, gating the later event.
  let assert Some(on_load) = scene("city", "end1").on_load
  let #(after, _) = on_load(state.new())
  state.get_game(after, "cityCleared") |> should.equal(1)
}

pub fn the_city_back_rooms_clear_and_flag_it_test() {
  // Every `end*` clears the dungeon and records the city cleared.
  let assert Ok(event) = setpieces.setpiece("city")
  let ends = list.filter(event.scenes, fn(p) { string.starts_with(p.0, "end") })
  list.length(ends) |> should.equal(15)
  list.each(ends, fn(p) {
    let scene = p.1
    let assert Some(events.SetpieceExtra(world_effect: effect, ..)) =
      scene.setpiece
    effect |> should.equal(events.ClearDungeon)
    scene.on_load |> should.not_equal(None)
  })
}

pub fn the_outpost_refills_water_and_drops_cured_meat_test() {
  let start = scene("outpost", "start")
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect, ..)) =
    start.setpiece
  effect |> should.equal(events.UseOutpost)
  loot
  |> should.equal([combat.LootEntry("cured meat", 5, 10, 1.0)])
  // A way out.
  list.key_find(start.buttons, "leave") |> should.be_ok
}

pub fn the_swamp_grants_gastronome_and_marks_visited_test() {
  let talk = scene("swamp", "talk")
  // markVisited rides on the setpiece extra; the perk is an ordinary onLoad.
  let assert Some(events.SetpieceExtra(world_effect: effect, ..)) =
    talk.setpiece
  effect |> should.equal(events.MarkVisited)
  let assert Some(on_load) = talk.on_load
  let #(after, _messages) = on_load(state.new())
  state.has_perk(after, "gastronome") |> should.be_true
}

pub fn the_swamp_cabin_costs_a_charm_to_talk_test() {
  let cabin = scene("swamp", "cabin")
  let assert Ok(talk) = list.key_find(cabin.buttons, "talk")
  talk.cost |> should.equal([#("charm", 1)])
}

pub fn the_battlefield_marks_visited_and_offers_war_loot_test() {
  let start = scene("battlefield", "start")
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect, ..)) =
    start.setpiece
  effect |> should.equal(events.MarkVisited)
  // The six dormant-tech drops.
  list.length(loot) |> should.equal(6)
  list.map(loot, fn(l) { l.name })
  |> list.contains("alien alloy")
  |> should.be_true
}

pub fn the_borehole_yields_alien_alloy_test() {
  let start = scene("borehole", "start")
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect, ..)) =
    start.setpiece
  effect |> should.equal(events.MarkVisited)
  loot |> should.equal([combat.LootEntry("alien alloy", 1, 3, 1.0)])
}

pub fn the_ship_is_found_and_roaded_home_test() {
  let start = scene("ship", "start")
  start.combat |> should.be_false
  let assert Some(events.SetpieceExtra(world_effect: effect, ..)) =
    start.setpiece
  effect |> should.equal(events.FoundShip)
  list.key_find(start.buttons, "leave") |> should.be_ok
}

pub fn the_town_is_a_six_ended_dungeon_test() {
  let assert Ok(event) = setpieces.setpiece("town")
  // start, a1-a3, b1-b5, c1-c6, d1-d2, end1-6.
  list.length(event.scenes) |> should.equal(23)
}

pub fn the_town_street_ambush_is_a_thug_test() {
  let a2 = scene("town", "a2")
  a2.combat |> should.be_true
  let assert Some(events.SetpieceExtra(enemy: Some(foe), ..)) = a2.setpiece
  foe.name |> should.equal("thug")
  foe.health |> should.equal(30)
}

pub fn the_town_back_rooms_clear_the_dungeon_test() {
  ["end1", "end2", "end3", "end4", "end5", "end6"]
  |> list.each(fn(name) {
    let assert Some(events.SetpieceExtra(world_effect: effect, ..)) =
      scene("town", name).setpiece
    effect |> should.equal(events.ClearDungeon)
  })
}

pub fn the_cave_descent_costs_a_torch_and_branches_test() {
  let start = scene("cave", "start")
  let assert Ok(enter) = list.key_find(start.buttons, "enter")
  enter.cost |> should.equal([#("torch", 1)])
}

pub fn the_cave_first_chamber_is_a_beast_fight_test() {
  let a1 = scene("cave", "a1")
  a1.combat |> should.be_true
  let assert Some(events.SetpieceExtra(enemy: Some(foe), ..)) = a1.setpiece
  foe.name |> should.equal("beast")
  foe.health |> should.equal(5)
}

pub fn the_cave_back_rooms_clear_the_dungeon_test() {
  ["end1", "end2", "end3"]
  |> list.each(fn(name) {
    let assert Some(events.SetpieceExtra(world_effect: effect, ..)) =
      scene("cave", name).setpiece
    effect |> should.equal(events.ClearDungeon)
  })
}

pub fn each_mine_clears_into_its_building_test() {
  [
    #("sulphurmine", "sulphur mine"),
    #("coalmine", "coal mine"),
    #("ironmine", "iron mine"),
  ]
  |> list.each(fn(pair) {
    let cleared = scene(pair.0, "cleared")
    let assert Some(events.SetpieceExtra(
      world_effect: events.ClearMine(building),
      ..,
    )) = cleared.setpiece
    building |> should.equal(pair.1)
  })
}

pub fn the_sulphur_mine_soldiers_are_ranged_test() {
  let a1 = scene("sulphurmine", "a1")
  a1.combat |> should.be_true
  let assert Some(events.SetpieceExtra(enemy: Some(foe), ..)) = a1.setpiece
  foe.name |> should.equal("soldier")
  foe.ranged |> should.be_true
  foe.health |> should.equal(50)
}

pub fn the_iron_mine_costs_a_torch_to_enter_test() {
  let start = scene("ironmine", "start")
  let assert Ok(enter) = list.key_find(start.buttons, "enter")
  enter.cost |> should.equal([#("torch", 1)])
}

pub fn the_house_squatter_is_a_combat_scene_test() {
  let occupied = scene("house", "occupied")
  occupied.combat |> should.be_true
  let assert Some(events.SetpieceExtra(enemy: Some(foe), ..)) =
    occupied.setpiece
  foe.name |> should.equal("squatter")
  foe.health |> should.equal(10)
  foe.ranged |> should.be_false
  // The loot rides on the enemy (it lands on the win), not the scene.
  list.length(foe.loot) |> should.equal(3)
}

pub fn the_house_well_refills_water_on_a_story_scene_test() {
  let supplies = scene("house", "supplies")
  supplies.combat |> should.be_false
  let assert Some(events.SetpieceExtra(world_effect: effect, enemy: None, ..)) =
    supplies.setpiece
  effect |> should.equal(events.RefillSupplies)
}

pub fn the_non_combat_setpieces_carry_no_enemy_test() {
  ["outpost", "swamp", "battlefield", "borehole"]
  |> list.each(fn(name) {
    let assert Ok(event) = setpieces.setpiece(name)
    list.each(event.scenes, fn(pair) {
      let scene = pair.1
      scene.combat |> should.be_false
      case scene.setpiece {
        Some(extra) -> extra.enemy |> should.equal(None)
        None -> Nil
      }
    })
  })
}
