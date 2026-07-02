//// The Outside: the silent forest beyond the room, where wood is gathered and
//// traps are checked. A faithful port of `Outside`'s gather/trap actions; the
//// village (population) and worker assignment are layered on by later issues.

import adarkroom/craft
import adarkroom/i18n
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

// --- workers ----------------------------------------------------------------

/// Which villager roles each building unlocks (in display order).
const role_unlocks = [
  #("lodge", ["hunter", "trapper"]),
  #("tannery", ["tanner"]),
  #("smokehouse", ["charcutier"]),
  // The mines (cleared as setpieces) and the late village workshops open up
  // their own workers, mirroring the original's `jobMap`.
  #("iron mine", ["iron miner"]),
  #("coal mine", ["coal miner"]),
  #("sulphur mine", ["sulphur miner"]),
  #("steelworks", ["steelworker"]),
  #("armoury", ["armourer"]),
]

/// Every assignable role.
fn all_roles() -> List(String) {
  list.flat_map(role_unlocks, fn(entry) { entry.1 })
}

/// The roles the player can currently assign, given the buildings that stand.
pub fn unlocked_roles(s: State) -> List(String) {
  list.flat_map(role_unlocks, fn(entry) {
    case craft.building_count(s, entry.0) > 0 {
      True -> entry.1
      False -> []
    }
  })
}

/// How many villagers are assigned to a role.
pub fn worker_count(s: State, role: String) -> Int {
  state.get_game(s, "worker." <> role)
}

fn total_workers(s: State) -> Int {
  list.fold(all_roles(), 0, fn(acc, role) { acc + worker_count(s, role) })
}

/// Unassigned villagers — they gather wood.
pub fn num_gatherers(s: State) -> Int {
  population(s) - total_workers(s)
}

/// Assign up to `n` free gatherers to a role.
pub fn increase_worker(s: State, role: String, n: Int) -> State {
  case num_gatherers(s) {
    available if available > 0 ->
      state.set_game(
        s,
        "worker." <> role,
        worker_count(s, role) + int.min(available, n),
      )
    _ -> s
  }
}

/// Return up to `n` of a role's workers to gathering.
pub fn decrease_worker(s: State, role: String, n: Int) -> State {
  case worker_count(s, role) {
    have if have > 0 ->
      state.set_game(s, "worker." <> role, have - int.min(have, n))
    _ -> s
  }
}

// --- income -----------------------------------------------------------------

/// Collect one round of income (the loop runs every 10s). Each active source
/// applies its store deltas, guarded so no store is driven negative. Income can
/// be fractional (a lone hunter yields half a fur), so the sub-unit remainder is
/// carried in `buffer` between collections; the stores themselves stay whole.
/// The thieves, when they're about, skim last — and answer to no guard.
pub fn collect_income(
  s: State,
  buffer: dict.Dict(String, Float),
) -> #(State, dict.Dict(String, Float)) {
  let sources = income_sources(s)
  let names = case thieving(s) {
    True ->
      touched(list.append(sources, [#("thieves", thieves_drain_deltas())]))
    False -> touched(sources)
  }
  // The true value of each touched store: its whole amount plus carried fraction.
  let start =
    list.fold(names, dict.new(), fn(acc, k) {
      dict.insert(
        acc,
        k,
        int.to_float(state.get_store(s, k)) +. get_float(buffer, k),
      )
    })
  let totals =
    list.fold(sources, start, fn(acc, source) { apply_source(acc, source.1) })
  let #(s, totals) = case thieving(s) {
    True -> skim(s, totals)
    False -> #(s, totals)
  }
  // Split each total back into a whole store value and a carried remainder.
  list.fold(names, #(s, buffer), fn(acc, k) {
    let #(st, buf) = acc
    let whole = float.floor(get_float(totals, k))
    #(
      state.set_store(st, k, float.round(whole)),
      dict.insert(buf, k, get_float(totals, k) -. whole),
    )
  })
}

/// The active income sources, each as `(name, store-deltas)`, pre-scaled by the
/// number of contributors.
fn income_sources(s: State) -> List(#(String, List(#(String, Float)))) {
  let builder = case room.builder_helping(s) {
    True -> [#("builder", [#("wood", 2.0)])]
    False -> []
  }
  let gatherers = case num_gatherers(s) {
    g if g > 0 -> [#("gatherer", scale([#("wood", 1.0)], g))]
    _ -> []
  }
  let workers =
    list.filter_map(all_roles(), fn(role) {
      case worker_count(s, role) {
        n if n > 0 -> Ok(#(role, scale(role_income(role), n)))
        _ -> Error(Nil)
      }
    })
  list.flatten([builder, gatherers, workers])
}

/// `_INCOME` per collection, every 10 seconds.
pub const income_delay_s = 10

/// One worker's ledger for the hover tooltip (`makeWorkerRow`): what a
/// single member of the profession consumes and produces per collection.
pub fn worker_ledger(role: String) -> List(#(String, Float)) {
  case role {
    "gatherer" -> [#("wood", 1.0)]
    _ -> role_income(role)
  }
}

/// Every active income source with its scaled deltas — the stores rows'
/// hover breakdown (`updateIncomeView` reading the income state). The
/// thieves appear while they're skimming.
pub fn active_income(s: State) -> List(#(String, List(#(String, Float)))) {
  let sources = income_sources(s)
  case thieving(s) {
    True -> list.append(sources, [#("thieves", thieves_drain_deltas())])
    False -> sources
  }
}

/// What one worker of a role yields (and consumes) per collection.
fn role_income(role: String) -> List(#(String, Float)) {
  case role {
    "hunter" -> [#("fur", 0.5), #("meat", 0.5)]
    "trapper" -> [#("meat", -1.0), #("bait", 1.0)]
    "tanner" -> [#("fur", -5.0), #("leather", 1.0)]
    "charcutier" -> [#("meat", -5.0), #("wood", -5.0), #("cured meat", 1.0)]
    "iron miner" -> [#("cured meat", -1.0), #("iron", 1.0)]
    "coal miner" -> [#("cured meat", -1.0), #("coal", 1.0)]
    "sulphur miner" -> [#("cured meat", -1.0), #("sulphur", 1.0)]
    "steelworker" -> [#("iron", -1.0), #("coal", -1.0), #("steel", 1.0)]
    "armourer" -> [#("steel", -1.0), #("sulphur", -1.0), #("bullets", 1.0)]
    _ -> []
  }
}

fn scale(deltas: List(#(String, Float)), n: Int) -> List(#(String, Float)) {
  list.map(deltas, fn(d) { #(d.0, d.1 *. int.to_float(n)) })
}

/// Apply a source's deltas to the running totals, but only if every affected
/// store stays non-negative (the original's per-source collection guard).
fn apply_source(
  totals: dict.Dict(String, Float),
  deltas: List(#(String, Float)),
) -> dict.Dict(String, Float) {
  case list.all(deltas, fn(d) { get_float(totals, d.0) +. d.1 >=. 0.0 }) {
    True ->
      list.fold(deltas, totals, fn(acc, d) {
        dict.insert(acc, d.0, get_float(acc, d.0) +. d.1)
      })
    False -> totals
  }
}

/// Every store name touched by the active sources (deduped).
fn touched(sources: List(#(String, List(#(String, Float))))) -> List(String) {
  list.fold(sources, [], fn(acc, source) {
    list.fold(source.1, acc, fn(names, d) {
      case list.contains(names, d.0) {
        True -> names
        False -> [d.0, ..names]
      }
    })
  })
}

fn get_float(m: dict.Dict(String, Float), k: String) -> Float {
  result.unwrap(dict.get(m, k), 0.0)
}

// --- thieves ----------------------------------------------------------------

/// What the thieves demand of each store per collection (`startThieves`).
const thieves_drain = [#("wood", 10), #("fur", 5), #("meat", 5)]

/// Whether the thieves are currently skimming: `game.thieves` is 1 between
/// their arrival and the day a thief is caught (then it's 2 for good).
fn thieving(s: State) -> Bool {
  state.get_game(s, "thieves") == 1
}

/// The drain as income-source deltas, for the touched-store bookkeeping.
fn thieves_drain_deltas() -> List(#(String, Float)) {
  list.map(thieves_drain, fn(d) { #(d.0, 0.0 -. int.to_float(d.1)) })
}

/// Once any store swells past 5000 in the world era, thieves move in and start
/// skimming (`startThieves`; the original checks on every stores redraw). They
/// only ever come once.
pub fn maybe_start_thieves(s: State) -> State {
  let tempted =
    state.get_game(s, "thieves") == 0
    && state.has_feature(s, "location.world")
    && list.any(state.stores_list(s), fn(store) { store.1 > 5000 })
  case tempted {
    True -> state.set_game(s, "thieves", 1)
    False -> s
  }
}

/// The thieves' cut of one collection: each store loses what they demand or all
/// it holds (`addStolen` plus the guard-free `collectIncome` branch — stores
/// clamp at zero rather than blocking the take). Whole units only: the sub-unit
/// fraction carried between collections stays behind. The take is tallied under
/// `game.stolen.*` so justice can one day return it.
fn skim(
  s: State,
  totals: dict.Dict(String, Float),
) -> #(State, dict.Dict(String, Float)) {
  list.fold(thieves_drain, #(s, totals), fn(acc, d) {
    let #(st, tot) = acc
    let have = get_float(tot, d.0)
    let taken = int.min(float.truncate(have), d.1)
    let tally = "stolen." <> d.0
    #(
      state.set_game(st, tally, state.get_game(st, tally) + taken),
      dict.insert(tot, d.0, have -. int.to_float(taken)),
    )
  })
}

/// Return everything the thieves took (`addM('stores', game.stolen)`). Only the
/// drained stores are checked — nothing else ever lands in the tally.
pub fn return_stolen(s: State) -> State {
  list.fold(thieves_drain, s, fn(st, d) {
    state.add_store(st, d.0, state.get_game(st, "stolen." <> d.0))
  })
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

// --- disasters --------------------------------------------------------------

/// Cut the population by `n` (never below zero), then lay off any workers the
/// survivors can no longer cover, oldest role first (`Outside.killVillagers`).
pub fn kill_villagers(s: State, n: Int) -> State {
  let s = state.set_game(s, "population", int.max(0, population(s) - n))
  case num_gatherers(s) {
    short if short < 0 -> lay_off(s, all_roles(), -short)
    _ -> s
  }
}

/// Drop `gap` workers, taking whole roles from the front before splitting one.
fn lay_off(s: State, roles: List(String), gap: Int) -> State {
  case roles {
    _ if gap <= 0 -> s
    [] -> s
    [role, ..rest] -> {
      let have = worker_count(s, role)
      case have < gap {
        True ->
          lay_off(state.set_game(s, "worker." <> role, 0), rest, gap - have)
        False -> state.set_game(s, "worker." <> role, have - gap)
      }
    }
  }
}

/// Tear apart `n` traps (`A Ruined Trap`).
pub fn destroy_traps(s: State, n: Int) -> State {
  state.set_game(
    s,
    craft.building_key("trap"),
    int.max(0, craft.building_count(s, "trap") - n),
  )
}

/// Raze `n` huts, killing whoever lived in each (`Outside.destroyHuts`, without
/// `allowEmpty`). One roll per hut picks which full/half-full hut burns; an empty
/// target spares its residents.
pub fn destroy_huts(s: State, n: Int, rolls: List(Float)) -> State {
  case n <= 0, rolls {
    True, _ -> s
    _, [] -> s
    _, [roll, ..rest] -> destroy_huts(raze_one_hut(s, roll), n - 1, rest)
  }
}

fn raze_one_hut(s: State, roll: Float) -> State {
  let pop = population(s)
  let full = pop / hut_room
  // The default targets only occupied huts: ceil(pop / room).
  let huts = { pop + hut_room - 1 } / hut_room
  case huts <= 0 {
    True -> s
    False -> {
      let target = float.truncate(roll *. int.to_float(huts)) + 1
      let inhabitants = case target <= full, target == full + 1 {
        True, _ -> hut_room
        _, True -> pop % hut_room
        _, _ -> 0
      }
      let s =
        state.set_game(
          s,
          craft.building_key("hut"),
          int.max(0, craft.building_count(s, "hut") - 1),
        )
      kill_villagers(s, inhabitants)
    }
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
      // The original translates the pieces (`_('the traps contain ')`, each
      // drop's message, `_(' and ')`) and joins them by hand.
      #(after, [
        i18n.t("the traps contain ") <> join_drops(list.map(messages, i18n.t)),
      ])
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
        init -> string.join(init, ", ") <> i18n.t(" and ") <> last
      }
  }
}
