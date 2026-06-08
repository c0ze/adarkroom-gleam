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
    )
  let #(s, msgs) = events.enter_scene(scene, state.new())
  state.get_store(s, "wood") |> should.equal(50)
  msgs |> should.equal(["a cache of wood"])
}

pub fn entering_a_plain_scene_changes_nothing_test() {
  let scene =
    events.Scene(
      text: ["nothing here"],
      notification: None,
      reward: [],
      buttons: [],
      combat: False,
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
      next: events.End,
    )
  let assert Ok(#(_, msgs, step)) = events.click_button(btn, state.new(), 0.5)
  msgs |> should.equal([])
  step |> should.equal(events.EndEvent)
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
