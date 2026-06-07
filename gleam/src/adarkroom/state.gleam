//// The core game `State`: a typed container for the nine `StateManager`
//// categories from the original game (`stores`, `features`, `character`,
//// `game`, `income`, `timers`, `playStats`, `previous`, `outfit`).
////
//// Each category is a map at the top level — faithful to the original's
//// dynamic state object. Deeper, fully-typed sub-structures (e.g. a `Fire`
//// enum, typed perks, the world map) are introduced by the milestone that
//// owns them, layered on top of this container.
////
//// `stores` carry the original's invariants: values are non-negative and
//// capped at `max_store`.

import gleam/dict.{type Dict}
import gleam/result

/// The original engine's ceiling for any stored value.
pub const max_store = 99_999_999_999_999

pub type State {
  State(
    /// Resources and items: `wood`, `fur`, `meat`, `iron`, weapons, …
    stores: Dict(String, Int),
    /// Unlocked features: buildings, locations, one-off flags.
    features: Dict(String, Bool),
    /// Player character: perks and personal stats.
    character: Dict(String, Int),
    /// Location/progression state: fire, buildings, population, world map.
    game: Dict(String, Int),
    /// Active income sources.
    income: Dict(String, Int),
    /// Running timers, keyed by name (seconds remaining).
    timers: Dict(String, Float),
    /// Play statistics: play time, loads, etc.
    play_stats: Dict(String, Int),
    /// Carried across prestige: score, trophies, achievements.
    previous: Dict(String, Int),
    /// Items selected to take on the path.
    outfit: Dict(String, Int),
  )
}

/// A fresh, empty state.
pub fn new() -> State {
  State(
    stores: dict.new(),
    features: dict.new(),
    character: dict.new(),
    game: dict.new(),
    income: dict.new(),
    timers: dict.new(),
    play_stats: dict.new(),
    previous: dict.new(),
    outfit: dict.new(),
  )
}

// --- stores -----------------------------------------------------------------

/// Read a store, defaulting to `0` when absent (matches `$SM.get(.., true)`).
pub fn get_store(state: State, key: String) -> Int {
  dict.get(state.stores, key) |> result.unwrap(0)
}

fn clamp_store(value: Int) -> Int {
  case value {
    v if v < 0 -> 0
    v if v > max_store -> max_store
    v -> v
  }
}

/// Set a store, clamped to `[0, max_store]`.
pub fn set_store(state: State, key: String, value: Int) -> State {
  State(..state, stores: dict.insert(state.stores, key, clamp_store(value)))
}

/// Add `delta` to a store (negative `delta` subtracts), clamped to
/// `[0, max_store]`.
pub fn add_store(state: State, key: String, delta: Int) -> State {
  set_store(state, key, get_store(state, key) + delta)
}

// --- features ---------------------------------------------------------------

/// Whether a feature flag is set (defaults to `False`).
pub fn has_feature(state: State, key: String) -> Bool {
  dict.get(state.features, key) |> result.unwrap(False)
}

/// Set or clear a feature flag.
pub fn set_feature(state: State, key: String, value: Bool) -> State {
  State(..state, features: dict.insert(state.features, key, value))
}
