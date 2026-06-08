//// The event/scene runtime, ported from `events.js`.
////
//// This module is the pure core: the typed scene schema and the logic that
//// drives it — event availability and random selection, entering a scene
//// (rewards + notifications), resolving a button click (cost → reward →
//// next scene), and the next-event timing. The modal UI and the tick-based
//// scheduler are wired on top in the app layer.

import adarkroom/state
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}

/// Where a button leads after its outcome is applied.
pub type NextScene {
  /// Close the event.
  End
  /// Stay on the current scene (a button with no `nextScene`, e.g. a repeatable
  /// trade).
  Stay
  /// Always load this scene.
  Goto(String)
  /// Pick the lowest-threshold scene whose threshold exceeds the roll, matching
  /// the JS `nextScene` probability map (`{ "0.5": a, "1": b }`).
  Branch(List(#(Float, String)))
}

/// A choice the player can make within a scene.
pub type SceneButton {
  SceneButton(
    text: String,
    cost: List(#(String, Int)),
    reward: List(#(String, Int)),
    notification: Option(String),
    /// When present, gates whether the button is offered (`available` in the JS).
    available: Option(fn(state.State) -> Bool),
    next: NextScene,
  )
}

/// Whether a button should be offered: its `available` predicate, defaulting to
/// always-available when there is none.
pub fn button_available(button: SceneButton, s: state.State) -> Bool {
  case button.available {
    option.Some(p) -> p(s)
    option.None -> True
  }
}

/// One screen of an event: prose, an optional notification/reward on entry, and
/// the buttons (kept in order).
pub type Scene {
  Scene(
    text: List(String),
    notification: Option(String),
    reward: List(#(String, Int)),
    buttons: List(#(String, SceneButton)),
    combat: Bool,
  )
}

/// A random event: a title, an availability predicate, and named scenes (one of
/// which must be `"start"`).
pub type Event {
  Event(
    title: String,
    is_available: fn(state.State) -> Bool,
    scenes: List(#(String, Scene)),
  )
}

/// The events from a pool that are currently available (`isAvailable`).
pub fn available_events(pool: List(Event), s: state.State) -> List(Event) {
  list.filter(pool, fn(e) { e.is_available(s) })
}

/// Apply a list of store deltas (`addM('stores', …)`).
fn apply_stores(s: state.State, deltas: List(#(String, Int))) -> state.State {
  list.fold(deltas, s, fn(acc, d) { state.add_store(acc, d.0, d.1) })
}

/// What a button (or scene transition) does to the running event.
pub type Step {
  LoadScene(String)
  EndEvent
  /// Remain on the current scene.
  StayOnScene
}

/// Resolve a `NextScene` into a concrete step, using `roll` for `Branch`. A
/// branch with no threshold above the roll ends the event (the JS error path).
pub fn resolve_next(next: NextScene, roll: Float) -> Step {
  case next {
    End -> EndEvent
    Stay -> StayOnScene
    Goto(name) -> LoadScene(name)
    Branch(branches) ->
      case
        branches
        |> list.filter(fn(b) { roll <. b.0 })
        |> list.sort(fn(a, b) { float.compare(a.0, b.0) })
        |> list.first
      {
        Ok(#(_, name)) -> LoadScene(name)
        Error(_) -> EndEvent
      }
  }
}

/// Enter a scene: grant its reward and surface its notification. Returns the
/// updated state and any messages to log.
pub fn enter_scene(scene: Scene, s: state.State) -> #(state.State, List(String)) {
  let s = apply_stores(s, scene.reward)
  #(s, notification_messages(scene.notification))
}

fn notification_messages(notification: Option(String)) -> List(String) {
  case notification {
    option.Some(n) -> [n]
    option.None -> []
  }
}

/// Whether the stores can cover a button's cost.
pub fn affordable(cost: List(#(String, Int)), s: state.State) -> Bool {
  list.all(cost, fn(c) { state.get_store(s, c.0) >= c.1 })
}

/// Resolve a button click. If the cost can't be met it's refused (`Error`),
/// mirroring the JS no-op. Otherwise the cost is paid, the reward granted, the
/// notification surfaced, and the next step resolved (using `roll` for a
/// `Branch`).
pub fn click_button(
  button: SceneButton,
  s: state.State,
  roll: Float,
) -> Result(#(state.State, List(String), Step), Nil) {
  case affordable(button.cost, s) {
    False -> Error(Nil)
    True -> {
      let s =
        s
        |> apply_stores(list.map(button.cost, fn(c) { #(c.0, -c.1) }))
        |> apply_stores(button.reward)
      let messages = notification_messages(button.notification)
      Ok(#(s, messages, resolve_next(button.next, roll)))
    }
  }
}

const event_time_min = 3

const event_time_max = 6

/// The delay until the next random event, in milliseconds. The JS draws
/// `floor(roll * (max - min)) + min` minutes from `EVENT_TIME_RANGE` ([3, 6]).
/// The upper bound is exclusive, so the draw is really 3–5 minutes (the JS
/// never reaches 6 either); the constants mirror the source range. `scale`
/// (e.g. `0.5` when no event was available) shortens the wait.
pub fn next_event_delay_ms(roll: Float, scale: Float) -> Int {
  let span = int.to_float(event_time_max - event_time_min)
  let minutes = float.truncate(roll *. span) + event_time_min
  float.round(int.to_float(minutes) *. scale *. 60_000.0)
}

/// Pick an item by a uniform `[0, 1)` roll, the way the JS does:
/// `items[floor(roll * length)]`. A full `1.0` roll is clamped to the last
/// item; an empty list is an error.
pub fn pick(items: List(a), roll: Float) -> Result(a, Nil) {
  case list.length(items) {
    0 -> Error(Nil)
    n -> {
      let idx = int.min(float.truncate(roll *. int.to_float(n)), n - 1)
      items |> list.drop(idx) |> list.first
    }
  }
}

// --- event content (the pools) ----------------------------------------------
// The JS splits its pool by where an event can fire (`Events.Global` / `Room` /
// `Outside`), each checking `activeModule` in `isAvailable`. We keep that split
// so availability stays a pure function of `State`. The full pools arrive in a
// follow-up; for now the Nomad seeds the Room pool.

/// Events available while in the Room.
pub fn room_events() -> List(Event) {
  [nomad()]
}

/// Events available while Outside.
pub fn outside_events() -> List(Event) {
  []
}

/// Events available in any settled location (Room or Outside).
pub fn global_events() -> List(Event) {
  []
}

/// The Nomad — a wandering merchant who buys fur for scales, teeth, bait, and
/// (once) a compass.
fn nomad() -> Event {
  let start =
    Scene(
      text: [
        "a nomad shuffles into view, laden with makeshift bags bound with rough twine.",
        "won't say from where he came, but it's clear that he's not staying.",
      ],
      notification: option.Some("a nomad arrives, looking to trade"),
      reward: [],
      combat: False,
      buttons: [
        #(
          "buyScales",
          SceneButton(
            text: "buy scales",
            cost: [#("fur", 100)],
            reward: [#("scales", 1)],
            notification: option.None,
            available: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyTeeth",
          SceneButton(
            text: "buy teeth",
            cost: [#("fur", 200)],
            reward: [#("teeth", 1)],
            notification: option.None,
            available: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyBait",
          SceneButton(
            text: "buy bait",
            cost: [#("fur", 5)],
            reward: [#("bait", 1)],
            notification: option.Some("traps are more effective with bait."),
            available: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyCompass",
          SceneButton(
            text: "buy compass",
            cost: [#("fur", 300), #("scales", 15), #("teeth", 5)],
            reward: [#("compass", 1)],
            notification: option.Some(
              "the old compass is dented and dusty, but it looks to work.",
            ),
            available: option.Some(fn(s) { state.get_store(s, "compass") < 1 }),
            next: Stay,
          ),
        ),
        #(
          "goodbye",
          SceneButton(
            text: "say goodbye",
            cost: [],
            reward: [],
            notification: option.None,
            available: option.None,
            next: End,
          ),
        ),
      ],
    )
  Event(
    title: "The Nomad",
    is_available: fn(s) { state.get_store(s, "fur") > 0 },
    scenes: [#("start", start)],
  )
}
