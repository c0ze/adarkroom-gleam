import adarkroom/combat
import adarkroom/events
import adarkroom/executioner
import adarkroom/state
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

// --- the antechamber and the engineering wing -----------------------------------

fn wing(key: String, name: String) -> events.Scene {
  let assert Ok(ev) = executioner.event(key)
  let assert Ok(s) = list.key_find(ev.scenes, name)
  s
}

pub fn the_elevators_run_until_their_wing_is_done_test() {
  let assert Ok(lift) =
    list.key_find(wing("executioner-antechamber", "start").buttons, "medical")
  events.button_available(lift, state.new()) |> should.be_true
  state.new()
  |> state.set_game("world.medical", 1)
  |> events.button_available(lift, _)
  |> should.be_false
}

pub fn the_command_deck_needs_all_three_wings_test() {
  let assert Ok(lift) =
    list.key_find(wing("executioner-antechamber", "start").buttons, "command")
  let two =
    state.new()
    |> state.set_game("world.engineering", 1)
    |> state.set_game("world.medical", 1)
  events.button_available(lift, two) |> should.be_false
  two
  |> state.set_game("world.martial", 1)
  |> events.button_available(lift, _)
  |> should.be_true
}

pub fn the_fire_takes_water_or_blood_test() {
  let s = wing("executioner-engineering", "1-3")
  let assert Ok(douse) = list.key_find(s.buttons, "water")
  douse.cost |> should.equal([#("water", 5)])
  let assert Ok(rush) = list.key_find(s.buttons, "run")
  rush.cost |> should.equal([#("hp", 10)])
  // No way around: the fire offers no leave.
  list.key_find(s.buttons, "leave") |> should.equal(Error(Nil))
}

pub fn the_machine_heals_for_an_alloy_test() {
  let assert Ok(use_machine) =
    list.key_find(wing("executioner-engineering", "4").buttons, "use")
  use_machine.cost |> should.equal([#("alien alloy", 1)])
  use_machine.effect |> should.equal(Some(events.HealToMax))
}

pub fn the_prototype_shields_every_five_seconds_test() {
  let s = wing("executioner-engineering", "7")
  let assert Some(extra) = s.setpiece
  extra.specials
  |> should.equal([combat.SetStatusEvery(5.0, combat.Shield)])
  let assert Some(foe) = extra.enemy
  foe.health |> should.equal(150)
}

pub fn the_wing_ends_at_the_elevators_test() {
  let s = wing("executioner-engineering", "8")
  let assert Some(on_load) = s.on_load
  let #(after, _) = on_load(state.new())
  state.get_game(after, "world.engineering") |> should.equal(1)
}

// --- the martial wing -----------------------------------------------------------

pub fn the_sealed_door_takes_a_grenade_test() {
  let assert Ok(explode) =
    list.key_find(wing("executioner-martial", "1").buttons, "explode")
  explode.cost |> should.equal([#("grenade", 1)])
  explode.next |> should.equal(events.Branch([#(1.0, "2-1")]))
}

pub fn the_planning_room_offers_surface_maps_test() {
  let assert Ok(scavenge) =
    list.key_find(wing("executioner-martial", "7-1").buttons, "scavenge")
  scavenge.effect |> should.equal(Some(events.ApplyMap(3)))
  // And the noise draws a guard.
  let guard = wing("executioner-martial", "8-1a")
  guard.notification
  |> should.equal(Some("drew some attention with all that noise."))
}

pub fn the_quadruped_keeps_its_one_sided_loot_table_test() {
  // The JS table has two 'alien alloy' keys; the later wins the object
  // literal, leaving only alloy 2-4 at 0.2 — preserved verbatim.
  let s = wing("executioner-martial", "3-2a")
  let assert Some(extra) = s.setpiece
  let assert Some(foe) = extra.enemy
  foe.name |> should.equal("mechanical quadruped")
  foe.loot |> should.equal([combat.LootEntry("alien alloy", 2, 4, 0.2)])
}

pub fn the_sparring_automaton_energises_test() {
  let s = wing("executioner-martial", "12")
  let assert Some(extra) = s.setpiece
  extra.specials
  |> should.equal([combat.SetStatusEvery(13.0, combat.Energised)])
  let assert Some(foe) = extra.enemy
  foe.health |> should.equal(250)
  // No retreat from the duel: the win offers only the way on.
  list.key_find(s.buttons, "leave") |> should.equal(Error(Nil))
}

pub fn the_martial_wing_ends_at_the_flag_test() {
  let s = wing("executioner-martial", "13")
  let assert Some(on_load) = s.on_load
  let #(after, _) = on_load(state.new())
  state.get_game(after, "world.martial") |> should.equal(1)
}
