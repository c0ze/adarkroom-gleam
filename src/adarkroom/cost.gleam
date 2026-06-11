//// Paying a cost out of `stores` — shared by building/crafting and trading.

import adarkroom/state.{type State}
import gleam/list

/// Pay `items` from `stores` if every component is affordable; otherwise report
/// the first component that falls short (as `Error(name)`) and spend nothing.
pub fn pay(s: State, items: List(#(String, Int))) -> Result(State, String) {
  case list.find(items, fn(pair) { state.get_store(s, pair.0) < pair.1 }) {
    Ok(#(missing, _)) -> Error(missing)
    Error(Nil) ->
      Ok(
        list.fold(items, s, fn(acc, pair) {
          state.add_store(acc, pair.0, -pair.1)
        }),
      )
  }
}
