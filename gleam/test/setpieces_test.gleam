import adarkroom/combat
import adarkroom/events
import adarkroom/setpieces
import adarkroom/state
import gleam/list
import gleam/option.{Some}
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
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect)) =
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
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect)) =
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
  let assert Some(events.SetpieceExtra(loot: loot, world_effect: effect)) =
    start.setpiece
  effect |> should.equal(events.MarkVisited)
  loot |> should.equal([combat.LootEntry("alien alloy", 1, 3, 1.0)])
}

pub fn setpieces_have_no_combat_yet_test() {
  // #25a is non-combat; the inline-enemy scenes arrive with the cave.
  ["outpost", "swamp", "battlefield", "borehole"]
  |> list.each(fn(name) {
    let assert Ok(event) = setpieces.setpiece(name)
    list.each(event.scenes, fn(pair) { { pair.1 }.combat |> should.be_false })
  })
}
