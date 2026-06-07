//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` is kept pure here.

import adarkroom/notifications.{type Notifications}
import adarkroom/room
import adarkroom/state.{type State}
import gleam/list

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
  /// Timer: cool the fire by one level.
  CoolFire
  /// Timer: move the temperature toward the fire.
  AdjustTemp
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

/// Pure state transition.
pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Tick -> Model(..model, ticks: model.ticks + 1)
    Navigate(to: location) ->
      Model(
        ..model,
        location: location,
        // Arriving at a location flushes its queued notifications.
        notifications: notifications.flush(
          model.notifications,
          location_key(location),
        ),
      )
    LightFire -> {
      let lit = apply_room(model, room.light_fire(model.state))
      // A successful first light (Dead -> Burning) reveals the forest; a failed
      // attempt (not enough wood) leaves it unchanged.
      case room.fire(model.state), room.fire(lit.state) {
        room.Dead, room.Burning ->
          apply_room(lit, room.unlock_forest(lit.state))
        _, _ -> lit
      }
    }
    StokeFire -> apply_room(model, room.stoke_fire(model.state))
    CoolFire -> apply_room(model, room.cool_fire(model.state))
    AdjustTemp -> apply_room(model, room.adjust_temp(model.state))
  }
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
