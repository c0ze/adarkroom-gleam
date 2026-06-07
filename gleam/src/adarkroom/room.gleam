//// The Room: fire and temperature.
////
//// The fire is lit/stoked with wood and decays over time; the room temperature
//// drifts toward the fire's level. As in the original, the very first light or
//// stoke is free — wood has not yet been introduced — until a wood store is
//// established (which is distinct from a wood count of zero).

import adarkroom/state.{type State}

pub type Fire {
  Dead
  Smoldering
  Flickering
  Burning
  Roaring
}

pub type Temperature {
  Freezing
  Cold
  Mild
  Warm
  Hot
}

const fire_key = "fire"

const temp_key = "temperature"

const light_cost = 5

pub fn fire_to_int(f: Fire) -> Int {
  case f {
    Dead -> 0
    Smoldering -> 1
    Flickering -> 2
    Burning -> 3
    Roaring -> 4
  }
}

pub fn fire_from_int(value: Int) -> Fire {
  case value {
    _ if value <= 0 -> Dead
    1 -> Smoldering
    2 -> Flickering
    3 -> Burning
    _ -> Roaring
  }
}

pub fn fire_text(f: Fire) -> String {
  case f {
    Dead -> "dead"
    Smoldering -> "smoldering"
    Flickering -> "flickering"
    Burning -> "burning"
    Roaring -> "roaring"
  }
}

pub fn temp_to_int(t: Temperature) -> Int {
  case t {
    Freezing -> 0
    Cold -> 1
    Mild -> 2
    Warm -> 3
    Hot -> 4
  }
}

pub fn temp_from_int(value: Int) -> Temperature {
  case value {
    _ if value <= 0 -> Freezing
    1 -> Cold
    2 -> Mild
    3 -> Warm
    _ -> Hot
  }
}

pub fn temp_text(t: Temperature) -> String {
  case t {
    Freezing -> "freezing"
    Cold -> "cold"
    Mild -> "mild"
    Warm -> "warm"
    Hot -> "hot"
  }
}

/// The current fire level.
pub fn fire(s: State) -> Fire {
  fire_from_int(state.get_game(s, fire_key))
}

/// The current room temperature.
pub fn temperature(s: State) -> Temperature {
  temp_from_int(state.get_game(s, temp_key))
}

fn set_fire(s: State, f: Fire) -> State {
  state.set_game(s, fire_key, fire_to_int(f))
}

fn fire_message(f: Fire) -> String {
  "the fire is " <> fire_text(f)
}

/// Light the fire (to Burning). Costs `light_cost` wood once wood exists; the
/// very first light (before any wood store) is free.
pub fn light_fire(s: State) -> #(State, List(String)) {
  case state.has_store(s, "wood") {
    False -> #(reset_cool(set_fire(s, Burning)), [fire_message(Burning)])
    True ->
      case state.get_store(s, "wood") >= light_cost {
        True -> #(
          reset_cool(set_fire(state.add_store(s, "wood", -light_cost), Burning)),
          [fire_message(Burning)],
        )
        False -> #(s, ["not enough wood to get the fire going"])
      }
  }
}

/// Revealed on the first light: a little wood appears and the Outside unlocks.
/// A no-op once already unlocked.
pub fn unlock_forest(s: State) -> #(State, List(String)) {
  case state.has_feature(s, "location.outside") {
    True -> #(s, [])
    False -> {
      let unlocked =
        s
        |> state.set_store("wood", 4)
        |> state.set_feature("location.outside", True)
      #(unlocked, ["the wind howls outside", "the wood is running out"])
    }
  }
}

// --- the builder ------------------------------------------------------------

const builder_key = "builder"

/// Delay between builder progression steps.
pub const builder_state_delay_ms = 30_000

/// The builder's progression: `-1` not arrived, `0` summoned, `1` stumbled in,
/// `2` mumbling, `3` up (able to build).
pub fn builder_level(s: State) -> Int {
  state.get_game_or(s, builder_key, -1)
}

/// Whether the builder has been summoned by the fire.
pub fn builder_arrived(s: State) -> Bool {
  builder_level(s) >= 0
}

/// Whether the builder is up and able to build.
pub fn builder_up(s: State) -> Bool {
  builder_level(s) >= 3
}

fn set_builder(s: State, level: Int) -> State {
  state.set_game(s, builder_key, level)
}

/// React to a fire change: once the room glows (Flickering or brighter) the
/// builder is summoned. A no-op if the fire is dim or the builder has arrived.
pub fn on_fire_change(s: State) -> #(State, List(String)) {
  let glowing = fire_to_int(fire(s)) >= fire_to_int(Flickering)
  case glowing && builder_arrived(s) == False {
    True -> #(set_builder(s, 0), [
      "the light from the fire spills from the windows, out into the dark",
    ])
    False -> #(s, [])
  }
}

/// Advance the builder one step (driven by a timer). The first step (stumbling
/// in) also reveals the forest; later steps wait until the room is Warm.
pub fn progress_builder(s: State) -> #(State, List(String)) {
  let warm = temp_to_int(temperature(s)) >= temp_to_int(Warm)
  case builder_level(s), warm {
    0, _ -> {
      let #(revealed, forest) = unlock_forest(set_builder(s, 1))
      #(revealed, [
        "a ragged stranger stumbles through the door and collapses in the corner",
        ..forest
      ])
    }
    1, True -> #(set_builder(s, 2), [
      "the stranger shivers, and mumbles quietly. her words are unintelligible.",
    ])
    2, True -> #(set_builder(s, 3), [
      "the stranger in the corner stops shivering. her breathing calms.",
    ])
    _, _ -> #(s, [])
  }
}

/// Stoke the fire one level. Costs 1 wood once wood exists; free before.
pub fn stoke_fire(s: State) -> #(State, List(String)) {
  let stoked = fire_from_int(state.get_game(s, fire_key) + 1)
  case state.has_store(s, "wood") {
    False -> #(reset_cool(set_fire(s, stoked)), [fire_message(stoked)])
    True ->
      case state.get_store(s, "wood") {
        0 -> #(s, ["the wood has run out"])
        _ -> #(reset_cool(set_fire(state.add_store(s, "wood", -1), stoked)), [
          fire_message(stoked),
        ])
      }
  }
}

/// Cool the fire by one level (driven by a timer). A no-op once Dead.
pub fn cool_fire(s: State) -> #(State, List(String)) {
  case fire(s) {
    Dead -> #(s, [])
    current -> {
      let cooled = fire_from_int(fire_to_int(current) - 1)
      #(set_fire(s, cooled), [fire_message(cooled)])
    }
  }
}

// --- fire-cooling deadline ---------------------------------------------------

const cool_at_key = "coolAt"

/// How long a fire holds before cooling one level.
pub const fire_cool_delay_ms = 300_000

/// Reset the cooling deadline; the next `tick_cool` re-arms it. Called on every
/// fire change so a freshly lit/stoked fire gets the full delay.
pub fn reset_cool(s: State) -> State {
  state.set_game(s, cool_at_key, 0)
}

/// Time-driven cooling: re-arm the deadline after a reset, then cool one level
/// each time `now` (ms since epoch) passes it. A no-op while the fire is Dead.
pub fn tick_cool(s: State, now: Int) -> #(State, List(String)) {
  case fire(s) {
    Dead -> #(s, [])
    _ -> {
      let cool_at = state.get_game(s, cool_at_key)
      case cool_at == 0, now >= cool_at {
        True, _ -> #(
          state.set_game(s, cool_at_key, now + fire_cool_delay_ms),
          [],
        )
        _, True -> {
          let #(cooled, msgs) = cool_fire(s)
          #(state.set_game(cooled, cool_at_key, now + fire_cool_delay_ms), msgs)
        }
        _, _ -> #(s, [])
      }
    }
  }
}

/// Move the temperature one step toward the fire's level (driven by a timer).
pub fn adjust_temp(s: State) -> #(State, List(String)) {
  let t = state.get_game(s, temp_key)
  let f = state.get_game(s, fire_key)
  case t < f, t > f {
    True, _ -> {
      let warmer = temp_from_int(t + 1)
      #(state.set_game(s, temp_key, temp_to_int(warmer)), [
        "the room is " <> temp_text(warmer),
      ])
    }
    _, True -> {
      let cooler = temp_from_int(t - 1)
      #(state.set_game(s, temp_key, temp_to_int(cooler)), [
        "the room is " <> temp_text(cooler),
      ])
    }
    _, _ -> #(s, [])
  }
}
