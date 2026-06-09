import adarkroom/combat
import adarkroom/events
import adarkroom/setpieces
import adarkroom/state
import gleam/list
import gleam/option.{None, Some}
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

pub fn unported_setpieces_are_absent_test() {
  // The combat dungeons land in later work.
  setpieces.setpiece("cave") |> should.be_error
  setpieces.setpiece("city") |> should.be_error
  setpieces.setpiece("nonsense") |> should.be_error
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
