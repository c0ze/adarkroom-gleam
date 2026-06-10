//// The score and the prestige carryover, ported from `scoring.js` and
//// `prestige.js`. The score weighs a fixed roster of 24 stores, plus the
//// endgame's own currencies; prestige squirrels a randomly-reduced copy of
//// those stores — and the accumulated score — past the end of the game, in
//// its own storage slot that a restart leaves untouched.

import adarkroom/ship
import adarkroom/state.{type State}
import adarkroom/storage
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The kinds of store prestige reduces differently (`randGen`).
pub type StoreKind {
  /// A good: divided by `floor(roll × 10)`.
  Good
  /// A weapon: divided by `floor(floor(roll × 10) / 2)`.
  Weapon
  /// Ammunition: divided by `ceil(roll × 10 × ceil(roll' × 10))` — two rolls.
  Ammo
}

/// The scored stores, in the factor table's order (`Prestige.storesMap`).
pub fn stores_map() -> List(#(String, StoreKind, Float)) {
  [
    #("wood", Good, 1.0),
    #("fur", Good, 1.5),
    #("meat", Good, 1.0),
    #("iron", Good, 2.0),
    #("coal", Good, 2.0),
    #("sulphur", Good, 3.0),
    #("steel", Good, 3.0),
    #("cured meat", Good, 2.0),
    #("scales", Good, 2.0),
    #("teeth", Good, 2.0),
    #("leather", Good, 2.0),
    #("bait", Good, 1.5),
    #("torch", Good, 1.0),
    #("cloth", Good, 1.0),
    #("bone spear", Weapon, 10.0),
    #("iron sword", Weapon, 30.0),
    #("steel sword", Weapon, 50.0),
    #("bayonet", Weapon, 100.0),
    #("rifle", Weapon, 150.0),
    #("laser rifle", Weapon, 150.0),
    #("bullets", Ammo, 3.0),
    #("energy cell", Ammo, 3.0),
    #("grenade", Ammo, 5.0),
    #("bolas", Ammo, 4.0),
  ]
}

/// This game's score (`Score.calculateScore`): the weighted stores — float
/// accumulation, floored once at the end — plus ten per alien alloy, five
/// hundred per fleet beacon, and fifty per point of hull.
pub fn calculate_score(s: State) -> Int {
  let weighted =
    list.fold(stores_map(), 0.0, fn(acc, entry) {
      let #(store, _, factor) = entry
      acc +. int.to_float(state.get_store(s, store)) *. factor
    })
  float.truncate(weighted)
  + state.get_store(s, "alien alloy")
  * 10
  + state.get_store(s, "fleet beacon")
  * 500
  + ship.hull(s)
  * 50
}

/// Prestige's reduced copy of the scored stores (`getStores(true)`): each
/// divided by its kind's random divisor — a zero divisor coerced to one.
/// Goods and weapons take one roll each, ammunition two; `rolls` is consumed
/// in map order.
pub fn reduced_stores(s: State, rolls: List(Float)) -> List(Int) {
  do_reduce(stores_map(), s, rolls, [])
}

fn do_reduce(
  entries: List(#(String, StoreKind, Float)),
  s: State,
  rolls: List(Float),
  acc: List(Int),
) -> List(Int) {
  case entries {
    [] -> list.reverse(acc)
    [#(store, kind, _), ..rest] -> {
      let #(divisor, remaining) = divisor(kind, rolls)
      do_reduce(rest, s, remaining, [state.get_store(s, store) / divisor, ..acc])
    }
  }
}

/// `randGen`: the kind's divisor from the next roll(s), never zero.
fn divisor(kind: StoreKind, rolls: List(Float)) -> #(Int, List(Float)) {
  case kind, rolls {
    Good, [r, ..rest] -> #(at_least_one(float.truncate(r *. 10.0)), rest)
    Weapon, [r, ..rest] -> #(at_least_one(float.truncate(r *. 10.0) / 2), rest)
    Ammo, [r1, r2, ..rest] -> #(
      at_least_one(
        float.round(float.ceiling(r1 *. 10.0 *. float.ceiling(r2 *. 10.0))),
      ),
      rest,
    )
    _, _ -> #(1, [])
  }
}

fn at_least_one(n: Int) -> Int {
  case n {
    0 -> 1
    _ -> n
  }
}

/// How many rolls one prestige save consumes: one per good and weapon, two
/// per ammunition store.
pub fn rolls_needed() -> Int {
  list.fold(stores_map(), 0, fn(acc, entry) {
    case entry.1 {
      Ammo -> acc + 2
      _ -> acc + 1
    }
  })
}

// --- the prestige slot --------------------------------------------------------

/// What carries between games: the reduced stores and the accumulated score.
pub type Prestige {
  Prestige(stores: List(Int), score: Int)
}

const prestige_key = "prestige"

/// The previous games' carryover, if any.
pub fn load() -> Option(Prestige) {
  case storage.get(prestige_key) {
    Some(raw) -> {
      case string.split(raw, "|") {
        [score_part, stores_part] -> {
          let score = result.unwrap(int.parse(score_part), 0)
          let stores =
            stores_part
            |> string.split(",")
            |> list.map(fn(v) { result.unwrap(int.parse(v), 0) })
          Some(Prestige(stores: stores, score: score))
        }
        _ -> None
      }
    }
    None -> None
  }
}

/// Save the carryover (`Prestige.save`): the reduced stores and the running
/// total — the previous total plus this game's score. The slot survives a
/// restart; only a new ending rewrites it.
pub fn save(s: State, rolls: List(Float)) -> Nil {
  let previous = case load() {
    Some(p) -> p.score
    None -> 0
  }
  let total = previous + calculate_score(s)
  let stores =
    reduced_stores(s, rolls)
    |> list.map(int.to_string)
    |> string.join(",")
  storage.set(prestige_key, int.to_string(total) <> "|" <> stores)
}

/// The accumulated score across every life so far.
pub fn total_score() -> Int {
  case load() {
    Some(p) -> p.score
    None -> 0
  }
}
