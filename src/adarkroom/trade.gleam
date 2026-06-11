//// The trading post's commerce: the nomads' `TradeGoods`, bought with furs and
//// the spoils of the wilds. A faithful port of the original `Room.TradeGoods`
//// data and its `buy` / `buyUnlocked` logic.
////
//// Every good is counted in `stores`; costs are paid from `stores`. A good's
//// button appears once the trading post stands and the good has been seen (the
//// compass is always on offer). The scripted nomad *event* lives with the
//// events system; this is the always-available shop.

import adarkroom/cost
import adarkroom/craft
import adarkroom/state.{type State}
import gleam/list
import gleam/option.{type Option, None, Some}

/// A purchasable good: its name, its cost in stores, and an optional cap (only
/// the compass is limited, to one).
pub type Good {
  Good(name: String, cost: List(#(String, Int)), maximum: Option(Int))
}

/// Look up a trade good by name.
pub fn get(name: String) -> Result(Good, Nil) {
  list.key_find(goods(), name)
}

/// Whether a good has reached its maximum.
pub fn at_maximum(g: Good, n: Int) -> Bool {
  case g.maximum {
    Some(m) -> n >= m
    None -> False
  }
}

/// Whether a good's buy button should appear: the trading post must stand, and
/// the good must be the compass or one that has already been seen.
pub fn buy_unlocked(s: State, name: String) -> Bool {
  craft.building_count(s, "trading post") > 0
  && { name == "compass" || state.has_store(s, name) }
}

/// The goods on offer, in table order — ready for the buy button section.
pub fn visible(s: State) -> List(#(String, Good)) {
  list.filter(goods(), fn(entry) { buy_unlocked(s, entry.0) })
}

/// Buy one of `name`. Faithful to the original: reaching the maximum is a silent
/// no-op; otherwise every cost component must be affordable (the first shortfall
/// is reported and nothing is spent) before the cost is paid and one is gained.
/// Trades carry no message of their own.
pub fn buy(s: State, name: String) -> #(State, List(String)) {
  case get(name) {
    Error(Nil) -> #(s, [])
    Ok(g) ->
      case at_maximum(g, state.get_store(s, name)) {
        True -> #(s, [])
        False ->
          case cost.pay(s, g.cost) {
            Error(missing) -> #(s, ["not enough " <> missing])
            Ok(paid) -> #(state.add_store(paid, name, 1), [])
          }
      }
  }
}

/// The full trade goods table, ported from `Room.TradeGoods`.
fn goods() -> List(#(String, Good)) {
  [
    #("scales", Good("scales", [#("fur", 150)], None)),
    #("teeth", Good("teeth", [#("fur", 300)], None)),
    #("iron", Good("iron", [#("fur", 150), #("scales", 50)], None)),
    #("coal", Good("coal", [#("fur", 200), #("teeth", 50)], None)),
    #(
      "steel",
      Good("steel", [#("fur", 300), #("scales", 50), #("teeth", 50)], None),
    ),
    #("medicine", Good("medicine", [#("scales", 50), #("teeth", 30)], None)),
    #("bullets", Good("bullets", [#("scales", 10)], None)),
    #(
      "energy cell",
      Good("energy cell", [#("scales", 10), #("teeth", 10)], None),
    ),
    #("bolas", Good("bolas", [#("teeth", 10)], None)),
    #("grenade", Good("grenade", [#("scales", 100), #("teeth", 50)], None)),
    #("bayonet", Good("bayonet", [#("scales", 500), #("teeth", 250)], None)),
    #(
      "alien alloy",
      Good(
        "alien alloy",
        [#("fur", 1500), #("scales", 750), #("teeth", 300)],
        None,
      ),
    ),
    #(
      "compass",
      Good("compass", [#("fur", 400), #("scales", 20), #("teeth", 10)], Some(1)),
    ),
  ]
}
