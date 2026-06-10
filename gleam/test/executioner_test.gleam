import adarkroom/combat
import adarkroom/events
import adarkroom/executioner
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleeunit/should

fn intro() -> events.Event {
  let assert Ok(ev) = executioner.event("executioner-intro")
  ev
}

fn scene(name: String) -> events.Scene {
  let assert Ok(s) = list.key_find(intro().scenes, name)
  s
}

pub fn the_registry_knows_the_intro_test() {
  intro().title |> should.equal("A Ravaged Battleship")
  executioner.event("no-such-event") |> result.is_error |> should.be_true
}

pub fn entering_the_ship_costs_a_torch_test() {
  let assert Ok(enter) = list.key_find(scene("start").buttons, "enter")
  enter.cost |> should.equal([#("torch", 1)])
  scene("start").notification
  |> should.equal(Some("the remains of a huge ship are embedded in the earth."))
}

pub fn the_corridor_forks_three_ways_test() {
  let assert Ok(fork) = list.key_find(scene("1").buttons, "continue")
  fork.next
  |> should.equal(events.Branch([#(0.4, "2-1"), #(0.8, "2-2"), #(1.0, "2-3")]))
}

pub fn the_horror_guards_the_webs_test() {
  let s = scene("3-1")
  s.combat |> should.be_true
  let assert Some(extra) = s.setpiece
  let assert Some(foe) = extra.enemy
  foe.name |> should.equal("chitinous horror")
  foe.chara |> should.equal("H")
  foe.health |> should.equal(60)
  foe.damage |> should.equal(1)
  foe.attack_delay |> should.equal(0.25)
}

pub fn the_barricade_hoards_energy_weapons_test() {
  let assert Some(extra) = scene("2-3").setpiece
  extra.loot
  |> should.equal([
    combat.LootEntry("laser rifle", 1, 3, 1.0),
    combat.LootEntry("energy cell", 1, 5, 0.8),
    combat.LootEntry("plasma rifle", 1, 1, 0.2),
  ])
}

pub fn the_turret_shoots_back_test() {
  let assert Some(extra) = scene("6").setpiece
  let assert Some(foe) = extra.enemy
  foe.name |> should.equal("automated turret")
  foe.ranged |> should.be_true
  foe.attack_delay |> should.equal(2.5)
}

pub fn taking_the_device_unseals_the_ship_test() {
  let s = scene("7")
  let assert Some(extra) = s.setpiece
  extra.world_effect |> should.equal(events.FoundExecutioner)
  let assert Ok(btn) = list.key_find(s.buttons, "leave")
  btn.text |> should.equal("take device and leave")
  btn.next |> should.equal(events.End)
}
