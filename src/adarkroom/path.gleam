//// The Dusty Path: outfitting before an expedition. A faithful port of `Path`'s
//// bag-capacity and supply logic. The compass (bought at the trading post)
//// reveals the path; here the player packs supplies — bounded by the bag's
//// capacity (raised by carry upgrades) and the weight of each item — before
//// embarking into the world.

import adarkroom/state.{type State}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

const default_bag_space = 10

/// A carryable item's kind — weapons can fight, tools are used or consumed.
pub type Kind {
  Tool
  Weapon
}

/// Everything that can be packed for the path, with its kind: the loose goods
/// `updateOutfitting` lists, plus every tool and weapon the workshop and the
/// fabricator make (its `$.extend` of `Room.Craftables` and
/// `Fabricator.Craftables`).
fn carryable_items() -> List(#(String, Kind)) {
  [
    #("cured meat", Tool),
    #("bullets", Tool),
    #("grenade", Weapon),
    #("bolas", Weapon),
    #("energy cell", Tool),
    #("bayonet", Weapon),
    #("charm", Tool),
    #("alien alloy", Tool),
    #("medicine", Tool),
    #("torch", Tool),
    #("bone spear", Weapon),
    #("iron sword", Weapon),
    #("steel sword", Weapon),
    #("rifle", Weapon),
    #("laser rifle", Weapon),
    #("energy blade", Weapon),
    #("disruptor", Weapon),
    #("plasma rifle", Weapon),
    #("hypo", Tool),
    #("stim", Tool),
    #("glowstone", Tool),
  ]
}

/// The carryable items the player actually has, sorted by name for display.
pub fn carryable(s: State) -> List(#(String, Kind)) {
  carryable_items()
  |> list.filter(fn(entry) { state.get_store(s, entry.0) > 0 })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// The best armour the player owns (display only on the path).
pub fn armour(s: State) -> String {
  let has = fn(item) { state.get_store(s, item) > 0 }
  case
    has("kinetic armour"),
    has("s armour"),
    has("i armour"),
    has("l armour")
  {
    True, _, _, _ -> "kinetic"
    _, True, _, _ -> "steel"
    _, _, True, _ -> "iron"
    _, _, _, True -> "leather"
    _, _, _, _ -> "none"
  }
}

/// What one of an item weighs. Most things weigh 1; weapons and ammo differ.
pub fn weight(item: String) -> Float {
  case item {
    "bone spear" -> 2.0
    "iron sword" -> 3.0
    "steel sword" -> 5.0
    "rifle" -> 5.0
    "laser rifle" -> 5.0
    "plasma rifle" -> 5.0
    "bolas" -> 0.5
    "bullets" -> 0.1
    "energy cell" -> 0.2
    _ -> 1.0
  }
}

/// The bag's carrying capacity, raised by the best carry upgrade owned.
pub fn capacity(s: State) -> Int {
  let has = fn(item) { state.get_store(s, item) > 0 }
  case has("cargo drone"), has("convoy"), has("wagon"), has("rucksack") {
    True, _, _, _ -> default_bag_space + 100
    _, True, _, _ -> default_bag_space + 60
    _, _, True, _ -> default_bag_space + 30
    _, _, _, True -> default_bag_space + 10
    _, _, _, _ -> default_bag_space
  }
}

/// The total weight currently packed.
pub fn used_space(s: State) -> Float {
  list.fold(state.outfit_list(s), 0.0, fn(acc, entry) {
    acc +. int.to_float(entry.1) *. weight(entry.0)
  })
}

/// The remaining space in the bag.
pub fn free_space(s: State) -> Float {
  int.to_float(capacity(s)) -. used_space(s)
}

/// Pack up to `n` more of an item, bounded by free space and how many are in
/// the stores.
pub fn increase_supply(s: State, item: String, n: Int) -> State {
  let cur = state.get_outfit(s, item)
  let have = state.get_store(s, item)
  let w = weight(item)
  case free_space(s) >=. w && cur < have {
    True -> {
      let by_weight = float.truncate(free_space(s) /. w)
      let by_store = have - cur
      state.set_outfit(s, item, cur + int.min(n, int.min(by_weight, by_store)))
    }
    False -> s
  }
}

/// Trim every packed amount to what the stores still hold — supplies packed
/// and then spent at home can't ride out (`updateOutfitting`'s
/// `if (have < num) num = have`).
pub fn settle(s: State) -> State {
  list.fold(state.outfit_list(s), s, fn(acc, entry) {
    let have = state.get_store(acc, entry.0)
    case entry.1 > have {
      True -> state.set_outfit(acc, entry.0, have)
      False -> acc
    }
  })
}

/// Unpack up to `n` of an item (never below zero).
pub fn decrease_supply(s: State, item: String, n: Int) -> State {
  state.set_outfit(s, item, int.max(0, state.get_outfit(s, item) - n))
}
