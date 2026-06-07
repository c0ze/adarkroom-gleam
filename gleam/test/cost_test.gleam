import adarkroom/cost
import adarkroom/state
import gleeunit/should

pub fn pay_deducts_when_affordable_test() {
  let s =
    state.new() |> state.set_store("fur", 200) |> state.set_store("scales", 60)
  let assert Ok(paid) = cost.pay(s, [#("fur", 150), #("scales", 50)])
  state.get_store(paid, "fur") |> should.equal(50)
  state.get_store(paid, "scales") |> should.equal(10)
}

pub fn pay_reports_first_shortfall_without_spending_test() {
  // Enough fur, but no scales: report scales, deduct nothing.
  let s = state.new() |> state.set_store("fur", 200)
  cost.pay(s, [#("fur", 150), #("scales", 50)])
  |> should.equal(Error("scales"))
}

pub fn pay_empty_cost_is_ok_noop_test() {
  let s = state.new() |> state.set_store("fur", 5)
  let assert Ok(paid) = cost.pay(s, [])
  state.get_store(paid, "fur") |> should.equal(5)
}
