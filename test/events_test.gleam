import adarkroom/craft
import adarkroom/events
import adarkroom/outside
import adarkroom/state
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn story_event(title: String, avail: fn(state.State) -> Bool) -> events.Event {
  events.Event(title: title, is_available: avail, scenes: [], audio: None)
}

// --- random selection (triggerEvent / pick) ---------------------------------

pub fn pick_indexes_by_floored_roll_test() {
  events.pick(["a", "b", "c"], 0.0) |> should.equal(Ok("a"))
  // floor(0.5 * 3) = 1
  events.pick(["a", "b", "c"], 0.5) |> should.equal(Ok("b"))
  // floor(0.99 * 3) = 2
  events.pick(["a", "b", "c"], 0.99) |> should.equal(Ok("c"))
}

pub fn pick_from_empty_is_an_error_test() {
  events.pick([], 0.5) |> should.equal(Error(Nil))
}

pub fn pick_clamps_a_full_roll_to_the_last_item_test() {
  // floor(1.0 * 3) = 3 would overrun; clamp to the last index.
  events.pick(["a", "b", "c"], 1.0) |> should.equal(Ok("c"))
}

// --- event availability -----------------------------------------------------

pub fn available_events_keeps_only_those_whose_predicate_holds_test() {
  let pool = [
    story_event("always", fn(_) { True }),
    story_event("never", fn(_) { False }),
    story_event("rich", fn(s) { state.get_store(s, "wood") >= 10 }),
  ]
  events.available_events(pool, state.new())
  |> list.map(fn(e) { e.title })
  |> should.equal(["always"])

  events.available_events(pool, state.new() |> state.set_store("wood", 10))
  |> list.map(fn(e) { e.title })
  |> should.equal(["always", "rich"])
}

// --- entering a scene (loadScene reward + notification) ---------------------

pub fn entering_a_scene_grants_its_reward_and_notification_test() {
  let scene =
    events.Scene(
      text: ["you stumble on a cache"],
      notification: Some("a cache of wood"),
      reward: [#("wood", 50)],
      buttons: [],
      combat: False,
      blink: False,
      on_load_rng: None,
      setpiece: None,
      on_load: None,
    )
  let #(s, msgs) = events.enter_scene(scene, state.new())
  state.get_store(s, "wood") |> should.equal(50)
  msgs |> should.equal(["a cache of wood"])
}

pub fn entering_a_scene_runs_its_on_load_effect_test() {
  // The store-room Noises scene computes its reward from current wood.
  let scene =
    events.Scene(
      text: ["the ground is littered with small scales"],
      notification: None,
      reward: [],
      buttons: [],
      combat: False,
      blink: False,
      on_load_rng: None,
      setpiece: None,
      on_load: Some(fn(s) {
        let taken = state.get_store(s, "wood") / 10
        let s =
          s
          |> state.add_store("wood", -taken)
          |> state.add_store("scales", taken / 5)
        #(s, ["some wood is missing"])
      }),
    )
  let s0 = state.new() |> state.set_store("wood", 100)
  let #(s, msgs) = events.enter_scene(scene, s0)
  // 10% of 100 = 10 wood taken; 10 / 5 = 2 scales.
  state.get_store(s, "wood") |> should.equal(90)
  state.get_store(s, "scales") |> should.equal(2)
  msgs |> should.equal(["some wood is missing"])
}

pub fn entering_a_plain_scene_changes_nothing_test() {
  let scene =
    events.Scene(
      text: ["nothing here"],
      notification: None,
      reward: [],
      buttons: [],
      combat: False,
      blink: False,
      on_load_rng: None,
      setpiece: None,
      on_load: None,
    )
  let #(s, msgs) = events.enter_scene(scene, state.new())
  state.get_store(s, "wood") |> should.equal(0)
  msgs |> should.equal([])
}

// --- next-scene resolution --------------------------------------------------

pub fn end_closes_the_event_test() {
  events.resolve_next(events.End, 0.5) |> should.equal(events.EndEvent)
}

pub fn goto_always_loads_the_named_scene_test() {
  events.resolve_next(events.Goto("camp"), 0.5)
  |> should.equal(events.LoadScene("camp"))
}

pub fn branch_takes_the_lowest_threshold_above_the_roll_test() {
  let next = events.Branch([#(0.5, "a"), #(1.0, "b")])
  // 0.3 < 0.5, so the 0.5 bucket wins.
  events.resolve_next(next, 0.3) |> should.equal(events.LoadScene("a"))
  // 0.7 only clears the 1.0 threshold.
  events.resolve_next(next, 0.7) |> should.equal(events.LoadScene("b"))
}

pub fn branch_with_nothing_above_the_roll_ends_test() {
  events.resolve_next(events.Branch([#(0.5, "a")]), 0.9)
  |> should.equal(events.EndEvent)
}

pub fn stay_remains_on_the_current_scene_test() {
  // A button with no `nextScene` (e.g. a repeatable trade) keeps the scene.
  events.resolve_next(events.Stay, 0.5) |> should.equal(events.StayOnScene)
}

// --- button availability gate -----------------------------------------------

pub fn an_ungated_button_is_always_available_test() {
  let btn =
    events.SceneButton(
      text: "leave",
      cost: [],
      reward: [],
      notification: None,
      available: None,
      link: None,
      effect: None,
      on_click: None,
      next: events.End,
    )
  events.button_available(btn, state.new()) |> should.equal(True)
}

pub fn a_gated_button_follows_its_predicate_test() {
  let btn =
    events.SceneButton(
      text: "buy compass",
      cost: [],
      reward: [],
      notification: None,
      available: Some(fn(s) { state.get_store(s, "compass") < 1 }),
      on_click: None,
      link: None,
      effect: None,
      next: events.End,
    )
  events.button_available(btn, state.new()) |> should.equal(True)
  events.button_available(btn, state.new() |> state.set_store("compass", 1))
  |> should.equal(False)
}

// --- clicking a button ------------------------------------------------------

pub fn affordability_reads_stores_test() {
  let s = state.new() |> state.set_store("fur", 30)
  events.affordable([#("fur", 10)], s, events.HomeStores) |> should.equal(True)
  events.affordable([#("fur", 40)], s, events.HomeStores) |> should.equal(False)
  events.affordable([#("fur", 10), #("scales", 1)], s, events.HomeStores)
  |> should.equal(False)
}

pub fn an_unaffordable_button_is_refused_test() {
  let btn =
    events.SceneButton(
      text: "bribe",
      cost: [#("fur", 100)],
      reward: [],
      notification: None,
      available: None,
      link: None,
      effect: None,
      on_click: None,
      next: events.End,
    )
  events.click_button(btn, state.new(), 0.5, events.HomeStores)
  |> should.equal(Error(Nil))
}

pub fn clicking_pays_cost_takes_reward_and_advances_test() {
  let btn =
    events.SceneButton(
      text: "trade",
      cost: [#("fur", 10)],
      reward: [#("scales", 5)],
      notification: Some("a fair trade"),
      available: None,
      link: None,
      effect: None,
      on_click: None,
      next: events.Goto("next"),
    )
  let s0 = state.new() |> state.set_store("fur", 30)
  let assert Ok(#(s, _, msgs, step)) =
    events.click_button(btn, s0, 0.5, events.HomeStores)
  state.get_store(s, "fur") |> should.equal(20)
  state.get_store(s, "scales") |> should.equal(5)
  msgs |> should.equal(["a fair trade"])
  step |> should.equal(events.LoadScene("next"))
}

pub fn clicking_a_button_runs_its_on_click_effect_test() {
  // The Scout's "learn" button grants a perk via onChoose.
  let btn =
    events.SceneButton(
      text: "learn scouting",
      cost: [],
      reward: [],
      notification: None,
      available: None,
      link: None,
      effect: None,
      on_click: Some(fn(s) {
        #(state.add_perk(s, "scout"), ["lessons learned"])
      }),
      next: events.End,
    )
  let assert Ok(#(s, _, msgs, _)) =
    events.click_button(btn, state.new(), 0.5, events.HomeStores)
  state.has_perk(s, "scout") |> should.equal(True)
  msgs |> should.equal(["lessons learned"])
}

pub fn a_free_button_can_just_end_test() {
  let btn =
    events.SceneButton(
      text: "leave",
      cost: [],
      reward: [],
      notification: None,
      available: None,
      link: None,
      effect: None,
      on_click: None,
      next: events.End,
    )
  let assert Ok(#(_, _, msgs, step)) =
    events.click_button(btn, state.new(), 0.5, events.HomeStores)
  msgs |> should.equal([])
  step |> should.equal(events.EndEvent)
}

// --- the Nomad (first ported event) -----------------------------------------

fn nomad() -> events.Event {
  let assert Ok(e) =
    list.find(events.room_events(), fn(e) { e.title == "The Nomad" })
  e
}

pub fn the_nomad_only_trades_when_you_have_fur_test() {
  nomad().is_available(state.new()) |> should.equal(False)
  nomad().is_available(state.new() |> state.set_store("fur", 1))
  |> should.equal(True)
}

pub fn buying_scales_from_the_nomad_costs_fur_and_stays_test() {
  let assert Ok(start) = list.key_find(nomad().scenes, "start")
  let assert Ok(buy) = list.key_find(start.buttons, "buyScales")
  let s = state.new() |> state.set_store("fur", 150)
  let assert Ok(#(s2, _, _msgs, step)) =
    events.click_button(buy, s, 0.5, events.HomeStores)
  state.get_store(s2, "fur") |> should.equal(50)
  state.get_store(s2, "scales") |> should.equal(1)
  // No nextScene on a trade button — you stay and can keep buying.
  step |> should.equal(events.StayOnScene)
}

pub fn the_nomads_compass_is_gated_to_one_test() {
  let assert Ok(start) = list.key_find(nomad().scenes, "start")
  let assert Ok(compass) = list.key_find(start.buttons, "buyCompass")
  events.button_available(compass, state.new()) |> should.equal(True)
  events.button_available(compass, state.new() |> state.set_store("compass", 1))
  |> should.equal(False)
}

// --- the Noises events ------------------------------------------------------

fn room_event_by_notification(note: String) -> events.Event {
  let assert Ok(ev) =
    list.find(events.room_events(), fn(e) {
      case list.key_find(e.scenes, "start") {
        Ok(scene) -> scene.notification == Some(note)
        Error(_) -> False
      }
    })
  ev
}

pub fn the_room_pool_has_grown_test() {
  events.room_events() |> list.length |> should.equal(10)
}

// --- the perk teachers + the Sick Man ---------------------------------------

pub fn the_scout_only_visits_the_well_travelled_test() {
  let scout = room_event_by_notification("a scout stops for the night")
  scout.is_available(state.new()) |> should.equal(False)
  scout.is_available(state.new() |> state.set_feature("location.world", True))
  |> should.equal(True)
}

pub fn learning_scouting_grants_the_perk_then_hides_the_button_test() {
  let scout = room_event_by_notification("a scout stops for the night")
  let assert Ok(start) = list.key_find(scout.scenes, "start")
  let assert Ok(learn) = list.key_find(start.buttons, "learn")
  let s0 =
    state.new()
    |> state.set_store("fur", 1000)
    |> state.set_store("scales", 50)
    |> state.set_store("teeth", 20)
  let assert Ok(#(s, _, _, step)) =
    events.click_button(learn, s0, 0.5, events.HomeStores)
  state.has_perk(s, "scout") |> should.equal(True)
  state.get_store(s, "fur") |> should.equal(0)
  step |> should.equal(events.EndEvent)
  // Already learned — no longer offered.
  events.button_available(learn, s) |> should.equal(False)
}

pub fn the_master_teaches_a_combat_perk_test() {
  let master = room_event_by_notification("an old wanderer arrives")
  let assert Ok(agree) = list.key_find(master.scenes, "agree")
  let assert Ok(force) = list.key_find(agree.buttons, "force")
  let assert Ok(#(s, _, _, _)) =
    events.click_button(force, state.new(), 0.5, events.HomeStores)
  state.has_perk(s, "barbarian") |> should.equal(True)
}

pub fn the_sick_man_appears_only_with_medicine_test() {
  let sick = room_event_by_notification("a sick man hobbles up")
  sick.is_available(state.new()) |> should.equal(False)
  sick.is_available(state.new() |> state.set_store("medicine", 1))
  |> should.equal(True)
}

pub fn helping_the_sick_man_spends_medicine_and_may_reward_test() {
  let sick = room_event_by_notification("a sick man hobbles up")
  let assert Ok(start) = list.key_find(sick.scenes, "start")
  let assert Ok(help) = list.key_find(start.buttons, "help")
  let s0 = state.new() |> state.set_store("medicine", 2)
  // 0.05 < 0.1 → the rare alien-alloy reward.
  let assert Ok(#(s, _, _, step)) =
    events.click_button(help, s0, 0.05, events.HomeStores)
  state.get_store(s, "medicine") |> should.equal(1)
  step |> should.equal(events.LoadScene("alloy"))
  let assert Ok(alloy) = list.key_find(sick.scenes, "alloy")
  let #(s2, _) = events.enter_scene(alloy, s)
  state.get_store(s2, "alien alloy") |> should.equal(1)
}

pub fn investigating_wall_noises_branches_on_the_roll_test() {
  let ev =
    room_event_by_notification("strange noises can be heard through the walls")
  let assert Ok(start) = list.key_find(ev.scenes, "start")
  let assert Ok(investigate) = list.key_find(start.buttons, "investigate")
  // 0.2 < 0.3 → the good find; 0.5 clears only the 1.0 bucket → nothing.
  events.resolve_next(investigate.next, 0.2)
  |> should.equal(events.LoadScene("stuff"))
  events.resolve_next(investigate.next, 0.5)
  |> should.equal(events.LoadScene("nothing"))
}

pub fn the_store_room_scenes_scavenge_each_material_test() {
  let ev = room_event_by_notification("something's in the store room")
  // Each scene routes the same wood→material math to a different material.
  list.each(
    [#("scales", "scales"), #("teeth", "teeth"), #("cloth", "cloth")],
    fn(pair) {
      let #(scene_name, material) = pair
      let assert Ok(scene) = list.key_find(ev.scenes, scene_name)
      let s0 = state.new() |> state.set_store("wood", 200)
      let #(s, _) = events.enter_scene(scene, s0)
      // 200 / 10 = 20 wood taken; 20 / 5 = 4 of the material.
      state.get_store(s, "wood") |> should.equal(180)
      state.get_store(s, material) |> should.equal(4)
    },
  )
}

// --- the Beggar -------------------------------------------------------------

pub fn the_beggar_appears_only_with_fur_to_spare_test() {
  let beggar = room_event_by_notification("a beggar arrives")
  beggar.is_available(state.new()) |> should.equal(False)
  beggar.is_available(state.new() |> state.set_store("fur", 1))
  |> should.equal(True)
}

pub fn giving_the_beggar_fur_branches_to_a_reward_scene_test() {
  let beggar = room_event_by_notification("a beggar arrives")
  let assert Ok(start) = list.key_find(beggar.scenes, "start")
  let assert Ok(give50) = list.key_find(start.buttons, "50furs")
  // 50 furs costs 50 fur and routes to scales (<0.5) / teeth (<0.8) / cloth.
  let s0 = state.new() |> state.set_store("fur", 80)
  let assert Ok(#(s, _, _, step)) =
    events.click_button(give50, s0, 0.2, events.HomeStores)
  state.get_store(s, "fur") |> should.equal(30)
  step |> should.equal(events.LoadScene("scales"))
  // The reward scene hands over 20 scales.
  let assert Ok(scales) = list.key_find(beggar.scenes, "scales")
  let #(s2, _) = events.enter_scene(scales, s)
  state.get_store(s2, "scales") |> should.equal(20)
}

// --- the Shady Builder ------------------------------------------------------

pub fn the_shady_builder_appears_with_five_to_twenty_huts_test() {
  let builder = room_event_by_notification("a shady builder passes through")
  let huts = fn(n) { state.set_game(state.new(), craft.building_key("hut"), n) }
  builder.is_available(huts(4)) |> should.equal(False)
  builder.is_available(huts(5)) |> should.equal(True)
  builder.is_available(huts(19)) |> should.equal(True)
  builder.is_available(huts(20)) |> should.equal(False)
}

pub fn the_shady_builders_build_scene_raises_a_hut_test() {
  let builder = room_event_by_notification("a shady builder passes through")
  let assert Ok(build) = list.key_find(builder.scenes, "build")
  let s0 = state.new() |> state.set_game(craft.building_key("hut"), 6)
  let #(s, _) = events.enter_scene(build, s0)
  craft.building_count(s, "hut") |> should.equal(7)
}

// --- next-event timing (scheduleNextEvent) ----------------------------------

pub fn next_event_delay_spans_three_to_five_minutes_test() {
  // floor(roll * 3) + 3 minutes, in ms.
  events.next_event_delay_ms(0.0, 1.0) |> should.equal(180_000)
  events.next_event_delay_ms(0.99, 1.0) |> should.equal(300_000)
}

pub fn next_event_delay_can_be_scaled_down_test() {
  // The "no events available" reschedule halves the wait.
  events.next_event_delay_ms(0.0, 0.5) |> should.equal(90_000)
}

// --- outside disasters ------------------------------------------------------

fn disaster_titles(s: state.State) -> List(String) {
  list.map(events.available_events(events.outside_events(), s), fn(e) {
    e.title
  })
}

pub fn outside_disasters_gate_on_the_village_test() {
  // A bare forest courts no disaster.
  disaster_titles(state.new()) |> should.equal([])
  // Traps standing → the ruined trap (only).
  disaster_titles(state.new() |> state.set_game("building.trap", 2))
  |> should.equal(["A Ruined Trap"])
  // A big, medicined village faces the plague, not the small-village sickness.
  let big =
    state.new()
    |> state.set_game("population", 60)
    |> state.set_store("medicine", 1)
  disaster_titles(big) |> list.contains("Plague") |> should.be_true
  disaster_titles(big) |> list.contains("Sickness") |> should.be_false
}

pub fn the_military_raid_waits_for_the_cleared_city_test() {
  let s = state.new() |> state.set_game("population", 10)
  disaster_titles(s) |> list.contains("A Military Raid") |> should.be_false
  disaster_titles(state.set_game(s, "cityCleared", 1))
  |> list.contains("A Military Raid")
  |> should.be_true
}

pub fn the_beast_attack_toll_scales_with_the_roll_test() {
  let assert Ok(event) =
    list.find(events.outside_events(), fn(e) { e.title == "A Beast Attack" })
  let assert Ok(start) = list.key_find(event.scenes, "start")
  let assert Some(toll) = start.on_load_rng
  let s = state.new() |> state.set_game("population", 20)
  // roll 0.0 → floor(0 × 10) + 1 = 1 dead.
  outside.population(toll(s, 0.0).0) |> should.equal(19)
  // roll 0.9 → floor(0.9 × 10) + 1 = 10 dead.
  outside.population(toll(s, 0.9).0) |> should.equal(10)
}

// --- the Thief (global) -------------------------------------------------------

fn the_thief() -> events.Event {
  let assert Ok(ev) =
    list.find(events.global_events(), fn(e) { e.title == "The Thief" })
  ev
}

pub fn the_thief_calls_only_while_thieves_skim_test() {
  the_thief().is_available(state.new()) |> should.be_false
  state.new()
  |> state.set_game("thieves", 1)
  |> the_thief().is_available
  |> should.be_true
  // Dealt with — hanged or spared — he never returns.
  state.new()
  |> state.set_game("thieves", 2)
  |> the_thief().is_available
  |> should.be_false
}

pub fn hanging_the_thief_returns_the_stolen_supplies_test() {
  let assert Ok(hang) = list.key_find(the_thief().scenes, "hang")
  let s =
    state.new()
    |> state.set_store("wood", 5)
    |> state.set_game("thieves", 1)
    |> state.set_game("stolen.wood", 100)
    |> state.set_game("stolen.fur", 40)
  let #(after, _) = events.enter_scene(hang, s)
  state.get_game(after, "thieves") |> should.equal(2)
  state.get_store(after, "wood") |> should.equal(105)
  state.get_store(after, "fur") |> should.equal(40)
}

pub fn sparing_the_thief_teaches_stealth_test() {
  let assert Ok(spare) = list.key_find(the_thief().scenes, "spare")
  let s = state.new() |> state.set_game("thieves", 1)
  let #(after, msgs) = events.enter_scene(spare, s)
  state.get_game(after, "thieves") |> should.equal(2)
  state.has_perk(after, "stealthy") |> should.be_true
  msgs |> should.equal(["learned how not to be seen"])
}

// --- the Mysterious Wanderers (saveDelay) -------------------------------------

/// The wanderer variant whose start scene leads to the given gamble scene.
fn wanderer_with(scene: String) -> events.Event {
  let assert Ok(ev) =
    list.find(events.room_events(), fn(e) {
      e.title == "The Mysterious Wanderer"
      && list.key_find(e.scenes, scene) != Error(Nil)
    })
  ev
}

pub fn the_wanderers_call_while_there_is_cargo_test() {
  let broke = state.new()
  wanderer_with("wood100").is_available(broke) |> should.be_false
  wanderer_with("fur100").is_available(broke) |> should.be_false
  let stocked = state.new() |> state.set_store("wood", 1)
  wanderer_with("wood100").is_available(stocked) |> should.be_true
  wanderer_with("fur100").is_available(stocked) |> should.be_false
}

pub fn a_lucky_gamble_starts_the_return_countdown_test() {
  let assert Ok(scene) =
    list.key_find(wanderer_with("wood100").scenes, "wood100")
  let assert Some(gamble) = scene.on_load_rng
  // Math.random() < 0.5 — a 0.4 roll wins, the cart comes back in 60s.
  let #(s, msgs) = gamble(state.new(), 0.4)
  state.get_game(s, "delay.wanderer.wood100") |> should.equal(60)
  msgs |> should.equal([])
}

pub fn an_unlucky_gamble_starts_nothing_test() {
  let assert Ok(scene) =
    list.key_find(wanderer_with("wood100").scenes, "wood100")
  let assert Some(gamble) = scene.on_load_rng
  let #(s, _) = gamble(state.new(), 0.5)
  state.get_game(s, "delay.wanderer.wood100") |> should.equal(0)
}

pub fn the_big_gamble_has_longer_odds_test() {
  // The 500 scenes win only under 0.3.
  let assert Ok(scene) = list.key_find(wanderer_with("fur500").scenes, "fur500")
  let assert Some(gamble) = scene.on_load_rng
  state.get_game(gamble(state.new(), 0.29).0, "delay.wanderer.fur500")
  |> should.equal(60)
  state.get_game(gamble(state.new(), 0.3).0, "delay.wanderer.fur500")
  |> should.equal(0)
}

pub fn tick_delays_counts_down_one_second_test() {
  let s = state.new() |> state.set_game("delay.wanderer.wood100", 2)
  let #(after, msgs) = events.tick_delays(s)
  state.get_game(after, "delay.wanderer.wood100") |> should.equal(1)
  msgs |> should.equal([])
  state.get_store(after, "wood") |> should.equal(0)
}

pub fn tick_delays_fires_the_return_at_zero_test() {
  let s = state.new() |> state.set_game("delay.wanderer.wood100", 1)
  let #(after, msgs) = events.tick_delays(s)
  state.get_game(after, "delay.wanderer.wood100") |> should.equal(0)
  state.get_store(after, "wood") |> should.equal(300)
  msgs
  |> should.equal([
    "the mysterious wanderer returns, cart piled high with wood.",
  ])
  // Spent — nothing more comes.
  let #(again, quiet) = events.tick_delays(after)
  state.get_store(again, "wood") |> should.equal(300)
  quiet |> should.equal([])
}

pub fn tick_delays_pays_each_gamble_its_due_test() {
  let s = state.new() |> state.set_game("delay.wanderer.fur500", 1)
  let #(after, msgs) = events.tick_delays(s)
  state.get_store(after, "fur") |> should.equal(1500)
  msgs
  |> should.equal([
    "the mysterious wanderer returns, cart piled high with furs.",
  ])
}

pub fn tick_delays_idles_with_nothing_pending_test() {
  let #(after, msgs) = events.tick_delays(state.new())
  msgs |> should.equal([])
  after |> should.equal(state.new())
}

// --- marketing ------------------------------------------------------------------

fn penrose() -> events.Event {
  let assert Ok(ev) =
    list.find(events.marketing_events(), fn(e) { e.title == "Penrose" })
  ev
}

pub fn penrose_thrums_until_given_in_test() {
  penrose().is_available(state.new()) |> should.be_true
  state.new()
  |> state.set_game("marketing.penrose", 1)
  |> penrose().is_available
  |> should.be_false
}

pub fn giving_in_to_penrose_sets_the_flag_and_links_out_test() {
  let assert Ok(start) = list.key_find(penrose().scenes, "start")
  let assert Ok(give_in) = list.key_find(start.buttons, "give in")
  give_in.link
  |> should.equal(Some(
    "https://penrose.doublespeakgames.com/?utm_source=adarkroom&utm_medium=crosspromote&utm_campaign=event",
  ))
  let assert Ok(#(s, _, _, _)) =
    events.click_button(give_in, state.new(), 0.5, events.HomeStores)
  state.get_game(s, "marketing.penrose") |> should.equal(1)
}

pub fn goto_event_switches_events_test() {
  // The JS `nextEvent` — the executioner's elevators hop between events.
  events.resolve_next(events.GotoEvent("executioner-medical"), 0.5)
  |> should.equal(events.SwitchEvent("executioner-medical"))
}

// --- the purse (in-world costs) -----------------------------------------------

fn priced(cost: List(#(String, Int))) -> events.SceneButton {
  events.SceneButton(
    text: "pay",
    cost: cost,
    reward: [],
    notification: None,
    available: None,
    link: None,
    effect: None,
    on_click: None,
    next: events.End,
  )
}

pub fn world_costs_come_from_the_carried_outfit_test() {
  // Out in the world a torch cost is paid from the pack, not the home stores.
  let s =
    state.new()
    |> state.set_store("torch", 5)
    |> state.set_outfit("torch", 2)
  let assert Ok(#(after, purse, _, _)) =
    events.click_button(
      priced([#("torch", 1)]),
      s,
      0.5,
      events.Carried(water: 10, hp: 10),
    )
  state.get_outfit(after, "torch") |> should.equal(1)
  state.get_store(after, "torch") |> should.equal(5)
  purse |> should.equal(events.Carried(water: 10, hp: 10))
}

pub fn torches_at_home_cannot_pay_in_the_wilds_test() {
  let s = state.new() |> state.set_store("torch", 5)
  events.affordable([#("torch", 1)], s, events.Carried(water: 10, hp: 10))
  |> should.be_false
  events.affordable([#("torch", 1)], s, events.HomeStores)
  |> should.be_true
}

pub fn water_and_hp_costs_drain_the_vitals_test() {
  let assert Ok(#(_, doused, _, _)) =
    events.click_button(
      priced([#("water", 5)]),
      state.new(),
      0.5,
      events.Carried(water: 8, hp: 10),
    )
  doused |> should.equal(events.Carried(water: 3, hp: 10))
  let assert Ok(#(_, burnt, _, _)) =
    events.click_button(
      priced([#("hp", 10)]),
      state.new(),
      0.5,
      events.Carried(water: 8, hp: 10),
    )
  burnt |> should.equal(events.Carried(water: 8, hp: 0))
}

pub fn an_exact_vitals_cost_is_allowed_test() {
  // The JS gate is `num < cost`: 10 hp covers a 10-hp rush, down to zero.
  events.affordable(
    [#("hp", 10)],
    state.new(),
    events.Carried(water: 0, hp: 10),
  )
  |> should.be_true
  events.affordable([#("hp", 10)], state.new(), events.Carried(water: 0, hp: 9))
  |> should.be_false
}

pub fn learning_from_the_master_announces_the_lesson_test() {
  // addPerk always notifies (Engine.Perks[name].notify).
  let master =
    list.find(events.room_events(), fn(e) { e.title == "The Master" })
  let assert Ok(master) = master
  let assert Ok(agree) = list.key_find(master.scenes, "agree")
  let assert Ok(evasion) = list.key_find(agree.buttons, "evasion")
  let assert Ok(#(s, _, msgs, _)) =
    events.click_button(evasion, state.new(), 0.5, events.HomeStores)
  state.has_perk(s, "evasive") |> should.be_true
  msgs |> should.equal(["learned to be where they're not"])
}

// --- event music ----------------------------------------------------------------

pub fn every_pool_event_carries_its_track_test() {
  let assert Ok(nomad) =
    list.find(events.room_events(), fn(e) { e.title == "The Nomad" })
  nomad.audio |> should.equal(Some("audio/event-nomad.flac"))
  // Penrose reuses the store-room noises track — verbatim quirk.
  let assert Ok(penrose) =
    list.find(events.marketing_events(), fn(e) { e.title == "Penrose" })
  penrose.audio |> should.equal(Some("audio/event-noises-inside.flac"))
  // The raid plays the soldier-attack theme.
  let assert Ok(raid) =
    list.find(events.outside_events(), fn(e) { e.title == "A Military Raid" })
  raid.audio |> should.equal(Some("audio/event-soldier-attack.flac"))
}

// --- the glowstone's torch waiver -------------------------------------------------

pub fn a_glowstone_waives_a_torch_cost_test() {
  let btn =
    events.SceneButton(
      text: "go inside",
      cost: [#("torch", 1)],
      reward: [],
      notification: option.None,
      available: option.None,
      on_click: option.None,
      link: option.None,
      effect: option.None,
      next: events.End,
    )
  // No torch, no glowstone: refused.
  let bare = state.new()
  events.click_button(btn, bare, 0.5, events.Carried(water: 1, hp: 1))
  |> should.equal(Error(Nil))
  // A glowstone in the bag stands in for the torch — and isn't spent.
  let lit = state.set_outfit(bare, "glowstone", 1)
  let assert Ok(#(s, _, _, _)) =
    events.click_button(btn, lit, 0.5, events.Carried(water: 1, hp: 1))
  state.get_outfit(s, "glowstone") |> should.equal(1)
  state.get_outfit(s, "torch") |> should.equal(0)
}
