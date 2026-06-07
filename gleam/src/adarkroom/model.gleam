//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location and a loop tick counter), and the messages that drive updates.
//// `update` is kept pure here; the Lustre runtime wraps it with effects.

import adarkroom/state.{type State}

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
  Model(state: State, location: Location, ticks: Int)
}

/// The initial model for a new game.
pub fn init() -> Model {
  Model(state: state.new(), location: Room, ticks: 0)
}

/// Pure state transition.
pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Tick -> Model(..model, ticks: model.ticks + 1)
    Navigate(to: location) -> Model(..model, location: location)
  }
}
