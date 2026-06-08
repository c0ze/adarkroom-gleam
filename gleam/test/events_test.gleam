import adarkroom/craft
import adarkroom/events
import adarkroom/state
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn story_event(title: String, avail: fn(state.State) -> Bool) -> events.Event {
  events.Event(title: title, is_available: avail, scenes: [])
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
      next: events.End,
    )
  events.button_available(btn, state.new()) |> should.equal(True)
  events.button_available(btn, state.new() |> state.set_store("compass", 1))
  |> should.equal(False)
}

// --- clicking a button ------------------------------------------------------

pub fn affordability_reads_stores_test() {
  let s = state.new() |> state.set_store("fur", 30)
  events.affordable([#("fur", 10)], s) |> should.equal(True)
  events.affordable([#("fur", 40)], s) |> should.equal(False)
  events.affordable([#("fur", 10), #("scales", 1)], s) |> should.equal(False)
}

pub fn an_unaffordable_button_is_refused_test() {
  let btn =
    events.SceneButton(
      text: "bribe",
      cost: [#("fur", 100)],
      reward: [],
      notification: None,
      available: None,
      next: events.End,
    )
  events.click_button(btn, state.new(), 0.5) |> should.equal(Error(Nil))
}

pub fn clicking_pays_cost_takes_reward_and_advances_test() {
  let btn =
    events.SceneButton(
      text: "trade",
      cost: [#("fur", 10)],
      reward: [#("scales", 5)],
      notification: Some("a fair trade"),
      available: None,
      next: events.Goto("next"),
    )
  let s0 = state.new() |> state.set_store("fur", 30)
  let assert Ok(#(s, msgs, step)) = events.click_button(btn, s0, 0.5)
  state.get_store(s, "fur") |> should.equal(20)
  state.get_store(s, "scales") |> should.equal(5)
  msgs |> should.equal(["a fair trade"])
  step |> should.equal(events.LoadScene("next"))
}

pub fn a_free_button_can_just_end_test() {
  let btn =
    events.SceneButton(
      text: "leave",
      cost: [],
      reward: [],
      notification: None,
      available: None,
      next: events.End,
    )
  let assert Ok(#(_, msgs, step)) = events.click_button(btn, state.new(), 0.5)
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
  let assert Ok(#(s2, _msgs, step)) = events.click_button(buy, s, 0.5)
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
  events.room_events() |> list.length |> should.equal(5)
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
  let assert Ok(#(s, _, step)) = events.click_button(give50, s0, 0.2)
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
