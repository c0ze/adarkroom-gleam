//// A Whirring Fabricator, ported from `fabricator.js`: wanderer machinery
//// that turns alien alloy into the fleet's tools — some of it only once the
//// matching blueprint has fed the data port.

import adarkroom/state.{type State}
import gleam/list
import gleam/option.{type Option, None, Some}

/// A fabricator recipe (`Fabricator.Craftables`).
pub type Craftable {
  Craftable(
    /// The store key.
    key: String,
    /// The display name — `glowstone` shows as "glow stone".
    name: String,
    /// At most this many owned before the button disables; `None` = unlimited.
    maximum: Option(Int),
    /// Only on the bench once its blueprint is redeemed.
    blueprint_required: Bool,
    /// What one fabrication yields (the hypo comes five to a batch).
    quantity: Int,
    /// Alien alloy per fabrication.
    alloy: Int,
    build_msg: String,
  )
}

/// The bench, in display order. The disruptor's "somtimes" is verbatim.
pub fn craftables() -> List(Craftable) {
  [
    Craftable(
      key: "energy blade",
      name: "energy blade",
      maximum: None,
      blueprint_required: False,
      quantity: 1,
      alloy: 1,
      build_msg: "the blade hums, charged particles sparking and fizzing.",
    ),
    Craftable(
      key: "fluid recycler",
      name: "fluid recycler",
      maximum: Some(1),
      blueprint_required: False,
      quantity: 1,
      alloy: 2,
      build_msg: "water out, water in. waste not, want not.",
    ),
    Craftable(
      key: "cargo drone",
      name: "cargo drone",
      maximum: Some(1),
      blueprint_required: False,
      quantity: 1,
      alloy: 2,
      build_msg: "the workhorse of the wanderer fleet.",
    ),
    Craftable(
      key: "kinetic armour",
      name: "kinetic armour",
      maximum: Some(1),
      blueprint_required: True,
      quantity: 1,
      alloy: 2,
      build_msg: "wanderer soldiers succeed by subverting the enemy's rage.",
    ),
    Craftable(
      key: "disruptor",
      name: "disruptor",
      maximum: None,
      blueprint_required: True,
      quantity: 1,
      alloy: 1,
      build_msg: "somtimes it is best not to fight.",
    ),
    Craftable(
      key: "hypo",
      name: "hypo",
      maximum: None,
      blueprint_required: True,
      quantity: 5,
      alloy: 1,
      build_msg: "a handful of hypos. life in a vial.",
    ),
    Craftable(
      key: "stim",
      name: "stim",
      maximum: None,
      blueprint_required: True,
      quantity: 1,
      alloy: 1,
      build_msg: "sometimes it is best to fight without restraint.",
    ),
    Craftable(
      key: "plasma rifle",
      name: "plasma rifle",
      maximum: None,
      blueprint_required: True,
      quantity: 1,
      alloy: 1,
      build_msg: "the peak of wanderer weapons technology, sleek and deadly.",
    ),
    Craftable(
      key: "glowstone",
      name: "glow stone",
      maximum: None,
      blueprint_required: True,
      quantity: 1,
      alloy: 1,
      build_msg: "a smooth, perfect sphere. its light is inextinguishable.",
    ),
  ]
}

/// Whether a recipe is on the bench (`canFabricate`): free, or its blueprint
/// has been redeemed.
pub fn can_fabricate(s: State, craftable: Craftable) -> Bool {
  !craftable.blueprint_required
  || state.get_character(s, "blueprints." <> craftable.key) != 0
}

/// Whether the recipe's button is disabled: another would exceed its maximum
/// (`$SM.num(key) + 1 > maximum`).
pub fn at_maximum(s: State, craftable: Craftable) -> Bool {
  case craftable.maximum {
    Some(max) -> state.get_store(s, craftable.key) + 1 > max
    None -> False
  }
}

/// The recipes currently on the bench.
pub fn bench(s: State) -> List(Craftable) {
  list.filter(craftables(), can_fabricate(s, _))
}

/// The blueprints redeemed so far, in bench order — the panel's blueprint list.
pub fn redeemed_blueprints(s: State) -> List(String) {
  craftables()
  |> list.filter(fn(c) {
    c.blueprint_required && state.get_character(s, "blueprints." <> c.key) != 0
  })
  |> list.map(fn(c) { c.key })
}

/// Fabricate one batch (`fabricate`): the alloy is paid from the stores, the
/// yield lands there too. The maximum is enforced only by the disabled button,
/// as in the JS — its own re-check is dead code (`Math.min` where it meant
/// `max`), so none is made here either.
pub fn fabricate(s: State, key: String) -> #(State, List(String)) {
  case list.find(craftables(), fn(c) { c.key == key }) {
    Error(_) -> #(s, [])
    Ok(craftable) ->
      case state.get_store(s, "alien alloy") < craftable.alloy {
        True -> #(s, ["not enough alien alloy"])
        False -> #(
          s
            |> state.add_store("alien alloy", -craftable.alloy)
            |> state.add_store(craftable.key, craftable.quantity),
          [craftable.build_msg],
        )
      }
  }
}

/// The hum of real tools, noted once (`onArrival` / `game.fabricator.seen`).
pub fn see_fabricator(s: State) -> #(State, List(String)) {
  case state.get_game(s, "fabricator.seen") {
    0 -> #(state.set_game(s, "fabricator.seen", 1), [
      "the familiar hum of wanderer machinery coming to life. finally, real tools.",
    ])
    _ -> #(s, [])
  }
}
