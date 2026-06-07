//// The Outside: the silent forest beyond the room, where wood is gathered and
//// traps are checked. A faithful port of `Outside`'s gather/trap actions; the
//// village (population) and worker assignment are layered on by later issues.

import adarkroom/craft
import adarkroom/room
import adarkroom/state.{type State}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

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

// --- income -----------------------------------------------------------------

/// Collect one round of income (the loop runs every 10s). Each active source
/// applies its store deltas, but only if no store would be driven negative. For
/// now the only source is the builder, who gathers wood once she is helping;
/// assigned villagers are added later.
pub fn collect_income(s: State) -> State {
  list.fold(income_sources(s), s, fn(acc, source) {
    apply_income(acc, source.1)
  })
}

/// The active income sources, each as `(name, store-deltas)`.
fn income_sources(s: State) -> List(#(String, List(#(String, Int)))) {
  case room.builder_helping(s) {
    True -> [#("builder", [#("wood", 2)])]
    False -> []
  }
}

/// Apply a source's deltas, but only if every affected store stays non-negative
/// (faithful to the original's collection guard).
fn apply_income(s: State, deltas: List(#(String, Int))) -> State {
  case list.all(deltas, fn(d) { state.get_store(s, d.0) + d.1 >= 0 }) {
    True -> list.fold(deltas, s, fn(acc, d) { state.add_store(acc, d.0, d.1) })
    False -> s
  }
}

// --- village & population ---------------------------------------------------

/// How many villagers a single hut houses.
pub const hut_room = 4

/// The most villagers the huts can hold.
pub fn max_population(s: State) -> Int {
  craft.building_count(s, "hut") * hut_room
}

/// The current population.
pub fn population(s: State) -> Int {
  state.get_game(s, "population")
}

/// Newcomers arrive to fill empty huts. Given a roll in `[0.0, 1.0)`, the number
/// is between half the free space and all of it (at least one), and the note
/// reflects how many came. A no-op when the huts are full.
pub fn increase_population(s: State, roll: Float) -> #(State, List(String)) {
  let space = max_population(s) - population(s)
  case space > 0 {
    False -> #(s, [])
    True -> {
      let half = int.to_float(space) /. 2.0
      let num = int.max(float.truncate(roll *. half +. half), 1)
      #(state.set_game(s, "population", population(s) + num), [
        arrival_message(num),
      ])
    }
  }
}

fn arrival_message(num: Int) -> String {
  case num {
    1 -> "a stranger arrives in the night"
    n if n < 5 -> "a weathered family takes up in one of the huts."
    n if n < 10 -> "a small group arrives, all dust and bones."
    n if n < 30 -> "a convoy lurches in, equal parts worry and hope."
    _ -> "the town's booming. word does get around."
  }
}

/// The Outside's title, which grows from a silent forest into a village as huts
/// go up.
pub fn title(s: State) -> String {
  case craft.building_count(s, "hut") {
    0 -> "A Silent Forest"
    1 -> "A Lonely Hut"
    n if n <= 4 -> "A Tiny Village"
    n if n <= 8 -> "A Modest Village"
    n if n <= 14 -> "A Large Village"
    _ -> "A Raucous Village"
  }
}

// --- check traps ------------------------------------------------------------

/// How many drops a trap-check rolls: one per trap, plus one per bait (capped at
/// the number of traps).
pub fn num_drops(s: State) -> Int {
  let traps = craft.building_count(s, "trap")
  traps + int.min(state.get_store(s, "bait"), traps)
}

/// Check the traps, given one random roll in `[0.0, 1.0)` per drop (see
/// `num_drops`). Each roll yields a resource from the weighted drop table; the
/// gains are added to stores, the bait used is consumed, and the haul is
/// reported (each kind named once, in the order first found).
pub fn check_traps(s: State, rolls: List(Float)) -> #(State, List(String)) {
  let traps = craft.building_count(s, "trap")
  let bait_used = int.min(state.get_store(s, "bait"), traps)

  let #(counts, seen_rev) =
    list.fold(rolls, #(dict.new(), []), fn(acc, roll) {
      let #(counts, seen) = acc
      let #(name, message) = classify(roll)
      let counts =
        dict.insert(counts, name, result.unwrap(dict.get(counts, name), 0) + 1)
      let seen = case list.contains(seen, message) {
        True -> seen
        False -> [message, ..seen]
      }
      #(counts, seen)
    })

  case list.reverse(seen_rev) {
    [] -> #(s, [])
    messages -> {
      let gained = dict.fold(counts, s, state.add_store)
      let after = state.add_store(gained, "bait", -bait_used)
      #(after, ["the traps contain " <> join_drops(messages)])
    }
  }
}

/// The weighted trap-drop table: a roll in `[0.0, 1.0)` maps to a resource and
/// its message (cumulative thresholds, as in the original `TrapDrops`).
fn classify(roll: Float) -> #(String, String) {
  case roll {
    r if r <. 0.5 -> #("fur", "scraps of fur")
    r if r <. 0.75 -> #("meat", "bits of meat")
    r if r <. 0.85 -> #("scales", "strange scales")
    r if r <. 0.93 -> #("teeth", "scattered teeth")
    r if r <. 0.995 -> #("cloth", "tattered cloth")
    _ -> #("charm", "a crudely made charm")
  }
}

/// Join drop messages as "a", "a and b", or "a, b and c".
fn join_drops(messages: List(String)) -> String {
  case list.reverse(messages) {
    [] -> ""
    [last, ..rest_rev] ->
      case list.reverse(rest_rev) {
        [] -> last
        init -> string.join(init, ", ") <> " and " <> last
      }
  }
}
