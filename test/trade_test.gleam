import adarkroom/state
import adarkroom/trade
import gleam/list
import gleeunit/should

/// A room with a trading post built.
fn with_post() -> state.State {
  state.new() |> state.set_game("building.trading post", 1)
}

pub fn get_known_good_test() {
  let assert Ok(g) = trade.get("scales")
  g.name |> should.equal("scales")
  g.cost |> should.equal([#("fur", 150)])
}

pub fn get_unknown_good_is_error_test() {
  trade.get("unicorn") |> should.equal(Error(Nil))
}

pub fn buy_deducts_cost_and_adds_one_test() {
  let s = with_post() |> state.set_store("fur", 200)
  let #(s2, msgs) = trade.buy(s, "scales")
  state.get_store(s2, "fur") |> should.equal(50)
  state.get_store(s2, "scales") |> should.equal(1)
  // Goods are bought silently — the original has no message for a trade.
  msgs |> should.equal([])
}

pub fn buy_reports_shortfall_without_spending_test() {
  let s = with_post() |> state.set_store("fur", 100)
  let #(s2, msgs) = trade.buy(s, "scales")
  state.get_store(s2, "fur") |> should.equal(100)
  state.get_store(s2, "scales") |> should.equal(0)
  msgs |> should.equal(["not enough fur"])
}

pub fn buy_multi_component_deducts_all_test() {
  // steel: fur 300, scales 50, teeth 50.
  let s =
    with_post()
    |> state.set_store("fur", 300)
    |> state.set_store("scales", 60)
    |> state.set_store("teeth", 60)
  let #(s2, _) = trade.buy(s, "steel")
  state.get_store(s2, "fur") |> should.equal(0)
  state.get_store(s2, "scales") |> should.equal(10)
  state.get_store(s2, "teeth") |> should.equal(10)
  state.get_store(s2, "steel") |> should.equal(1)
}

pub fn compass_maxes_at_one_test() {
  let s =
    with_post()
    |> state.set_store("fur", 9999)
    |> state.set_store("scales", 999)
    |> state.set_store("teeth", 999)
    |> state.set_store("compass", 1)
  let #(s2, msgs) = trade.buy(s, "compass")
  state.get_store(s2, "compass") |> should.equal(1)
  state.get_store(s2, "fur") |> should.equal(9999)
  msgs |> should.equal([])
}

pub fn buy_unlocked_requires_trading_post_test() {
  trade.buy_unlocked(state.new(), "compass") |> should.equal(False)
  trade.buy_unlocked(state.new() |> state.set_store("scales", 1), "scales")
  |> should.equal(False)
}

pub fn buy_unlocked_compass_always_at_post_test() {
  trade.buy_unlocked(with_post(), "compass") |> should.equal(True)
}

pub fn buy_unlocked_good_requires_having_been_seen_test() {
  // The trading post is up, but scales have never been seen — still hidden.
  trade.buy_unlocked(with_post(), "scales") |> should.equal(False)
  // A store entry (even zero) means it has been seen — now it shows.
  trade.buy_unlocked(with_post() |> state.set_store("scales", 0), "scales")
  |> should.equal(True)
}

pub fn visible_lists_unlocked_goods_in_table_order_test() {
  let s = with_post() |> state.set_store("teeth", 5)
  let names = trade.visible(s) |> list.map(fn(p) { p.0 })
  list.contains(names, "compass") |> should.equal(True)
  list.contains(names, "teeth") |> should.equal(True)
  list.contains(names, "scales") |> should.equal(False)
}

pub fn unknown_buy_is_noop_test() {
  let s = with_post() |> state.set_store("fur", 999)
  let #(s2, msgs) = trade.buy(s, "unicorn")
  msgs |> should.equal([])
  state.get_store(s2, "fur") |> should.equal(999)
}
