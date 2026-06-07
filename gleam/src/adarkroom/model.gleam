//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` is kept pure here.

import adarkroom/notifications.{type Notifications}
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
  }
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
