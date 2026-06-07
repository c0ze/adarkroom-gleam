import adarkroom/state
import gleeunit/should

pub fn new_state_is_empty_test() {
  let s = state.new()
  state.get_store(s, "wood") |> should.equal(0)
  state.has_feature(s, "fire") |> should.equal(False)
}

pub fn set_and_get_store_test() {
  let s = state.new() |> state.set_store("wood", 5)
  state.get_store(s, "wood") |> should.equal(5)
}

pub fn add_store_test() {
  let s =
    state.new()
    |> state.set_store("wood", 5)
    |> state.add_store("wood", 3)
  state.get_store(s, "wood") |> should.equal(8)
}

pub fn stores_clamp_negative_test() {
  let s =
    state.new()
    |> state.set_store("wood", 5)
    |> state.add_store("wood", -10)
  state.get_store(s, "wood") |> should.equal(0)
}

pub fn stores_clamp_max_test() {
  let s =
    state.new()
    |> state.set_store("wood", state.max_store)
    |> state.add_store("wood", 100)
  state.get_store(s, "wood") |> should.equal(state.max_store)
}

// Direct set_store boundary tests, so the invariant holds independently of
// add_store.
pub fn set_store_clamp_negative_test() {
  let s = state.new() |> state.set_store("wood", -1)
  state.get_store(s, "wood") |> should.equal(0)
}

pub fn set_store_clamp_max_test() {
  let s = state.new() |> state.set_store("wood", state.max_store + 1)
  state.get_store(s, "wood") |> should.equal(state.max_store)
}

pub fn set_feature_test() {
  let s = state.new() |> state.set_feature("fire", True)
  state.has_feature(s, "fire") |> should.equal(True)
}

pub fn stores_list_sorted_test() {
  let s =
    state.new()
    |> state.set_store("wood", 2)
    |> state.set_store("fur", 5)
  state.stores_list(s) |> should.equal([#("fur", 5), #("wood", 2)])
}

pub fn stores_list_empty_test() {
  state.stores_list(state.new()) |> should.equal([])
}
