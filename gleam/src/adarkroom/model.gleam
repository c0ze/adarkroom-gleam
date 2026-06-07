//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` returns the new model together with any
//// effects (e.g. one-shot timers for the builder's timed progression).

import adarkroom/notifications.{type Notifications}
import adarkroom/room
import adarkroom/state.{type State}
import adarkroom/timer
import gleam/list
import lustre/effect.{type Effect}

/// The screens the player can be on.
pub type Location {
  Room
  Outside
  World
  Path
  Ship
  Space
  Fabricator
}

pub type Msg {
  /// The periodic game-loop tick.
  Tick
  /// Switch to another location.
  Navigate(to: Location)
  /// Light the fire.
  LightFire
  /// Stoke the fire.
  StokeFire
  /// Timer: a time-stamped check that cools the fire once its deadline passes.
  CoolCheck(at: Int)
  /// Timer: move the temperature toward the fire.
  AdjustTemp
  /// Timer: advance the builder's arrival/progression.
  BuilderProgress
}

pub type Model {
  Model(
    state: State,
    location: Location,
    ticks: Int,
    notifications: Notifications,
  )
}

/// The initial model for a new game.
pub fn init() -> Model {
  Model(
    state: state.new(),
    location: Room,
    ticks: 0,
    notifications: notifications.new(),
  )
}

/// State transition, paired with any effects to run.
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Tick -> #(Model(..model, ticks: model.ticks + 1), effect.none())

    Navigate(to: location) -> #(
      Model(
        ..model,
        location:,
        // Arriving at a location flushes its queued notifications.
        notifications: notifications.flush(
          model.notifications,
          location_key(location),
        ),
      ),
      effect.none(),
    )

    LightFire -> fire_action(model, room.light_fire(model.state))
    StokeFire -> fire_action(model, room.stoke_fire(model.state))

    CoolCheck(at: now) -> #(
      apply_room(model, room.tick_cool(model.state, now)),
      effect.none(),
    )
    AdjustTemp -> #(
      apply_room(model, room.adjust_temp(model.state)),
      effect.none(),
    )

    BuilderProgress -> {
      let progressed = apply_room(model, room.progress_builder(model.state))
      let next = case room.builder_up(progressed.state) {
        True -> effect.none()
        False -> delayed(room.builder_state_delay_ms, BuilderProgress)
      }
      #(progressed, next)
    }
  }
}

/// Apply a fire change, let the builder react (it is summoned once the room
/// first glows), and schedule the builder's progression if it just arrived.
fn fire_action(
  model: Model,
  transition: #(State, List(String)),
) -> #(Model, Effect(Msg)) {
  let after_fire = apply_room(model, transition)
  let after_builder =
    apply_room(after_fire, room.on_fire_change(after_fire.state))
  let just_arrived =
    room.builder_level(model.state) < 0
    && room.builder_level(after_builder.state) == 0
  let eff = case just_arrived {
    True -> delayed(room.builder_state_delay_ms, BuilderProgress)
    False -> effect.none()
  }
  #(after_builder, eff)
}

/// An effect that dispatches `msg` once after `ms` milliseconds.
fn delayed(ms: Int, msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = timer.set_timeout(fn() { dispatch(msg) }, ms)
    Nil
  })
}

/// Apply a room transition: adopt the new state and emit its messages to the
/// Room's notification stream.
fn apply_room(model: Model, result: #(State, List(String))) -> Model {
  let #(new_state, messages) = result
  let notes =
    list.fold(messages, model.notifications, fn(acc, text) {
      notifications.notify(
        acc,
        current: location_key(model.location),
        target: "room",
        text: text,
      )
    })
  Model(..model, state: new_state, notifications: notes)
}

/// Locations the player has unlocked. The Room is always available; the others
/// appear once their `location.*` feature flag is set.
pub fn unlocked_locations(model: Model) -> List(Location) {
  let optional = [
    #(Outside, "location.outside"),
    #(World, "location.world"),
    #(Path, "location.path"),
    #(Ship, "location.ship"),
    #(Space, "location.space"),
    #(Fabricator, "location.fabricator"),
  ]
  let extra =
    list.filter_map(optional, fn(pair) {
      let #(loc, feature) = pair
      case state.has_feature(model.state, feature) {
        True -> Ok(loc)
        False -> Error(Nil)
      }
    })
  [Room, ..extra]
}

/// A stable key for a location (notification queues, DOM ids).
pub fn location_key(location: Location) -> String {
  case location {
    Room -> "room"
    Outside -> "outside"
    World -> "world"
    Path -> "path"
    Ship -> "ship"
    Space -> "space"
    Fabricator -> "fabricator"
  }
}

/// The display title for a location (placeholder; dynamic titles come later).
pub fn location_title(location: Location) -> String {
  case location {
    Room -> "A Dark Room"
    Outside -> "A Silent Forest"
    World -> "The World"
    Path -> "A Dusty Path"
    Ship -> "An Old Starship"
    Space -> "The Stars"
    Fabricator -> "A Whirring Fabricator"
  }
}
