//// The Outside: the silent forest beyond the room, where wood is gathered and
//// traps are checked. A faithful port of `Outside`'s gather/trap actions; the
//// village (population) and worker assignment are layered on by later issues.

import adarkroom/craft
import adarkroom/state.{type State}

/// Cooldown after gathering wood by hand.
pub const gather_cooldown_ms = 60_000

/// Cooldown after checking the traps.
pub const traps_cooldown_ms = 90_000

const seen_forest_key = "outside.seenForest"

/// How much wood a gather yields — more once a cart has been built.
pub fn gather_amount(s: State) -> Int {
  case craft.building_count(s, "cart") > 0 {
    True -> 50
    False -> 10
  }
}

/// Gather wood from the forest floor.
pub fn gather_wood(s: State) -> #(State, List(String)) {
  #(state.add_store(s, "wood", gather_amount(s)), [
    "dry brush and dead branches litter the forest floor",
  ])
}

/// The first time the player steps outside, note the bleak forest. Quiet
/// thereafter.
pub fn see_forest(s: State) -> #(State, List(String)) {
  case state.has_feature(s, seen_forest_key) {
    True -> #(s, [])
    False -> #(state.set_feature(s, seen_forest_key, True), [
      "the sky is grey and the wind blows relentlessly",
    ])
  }
}
