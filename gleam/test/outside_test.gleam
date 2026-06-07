import adarkroom/outside
import adarkroom/state
import gleeunit/should

pub fn gather_wood_gives_ten_by_hand_test() {
  let #(s, msgs) = outside.gather_wood(state.new())
  state.get_store(s, "wood") |> should.equal(10)
  msgs
  |> should.equal(["dry brush and dead branches litter the forest floor"])
}

pub fn gather_wood_gives_fifty_with_a_cart_test() {
  let s = state.new() |> state.set_game("building.cart", 1)
  let #(s2, _) = outside.gather_wood(s)
  state.get_store(s2, "wood") |> should.equal(50)
}

pub fn gather_wood_accumulates_test() {
  let #(s, _) = outside.gather_wood(state.new())
  let #(s2, _) = outside.gather_wood(s)
  state.get_store(s2, "wood") |> should.equal(20)
}

pub fn first_arrival_notes_the_forest_once_test() {
  let #(s, msgs) = outside.see_forest(state.new())
  msgs
  |> should.equal(["the sky is grey and the wind blows relentlessly"])
  // A second arrival is quiet.
  let #(_, msgs2) = outside.see_forest(s)
  msgs2 |> should.equal([])
}
