import adarkroom/room
import adarkroom/state
import gleeunit/should

pub fn fire_from_int_clamps_test() {
  room.fire_from_int(-1) |> should.equal(room.Dead)
  room.fire_from_int(0) |> should.equal(room.Dead)
  room.fire_from_int(3) |> should.equal(room.Burning)
  room.fire_from_int(9) |> should.equal(room.Roaring)
}

pub fn new_room_is_dead_and_freezing_test() {
  let s = state.new()
  room.fire(s) |> should.equal(room.Dead)
  room.temperature(s) |> should.equal(room.Freezing)
}

pub fn first_light_is_free_test() {
  let #(lit, msgs) = room.light_fire(state.new())
  room.fire(lit) |> should.equal(room.Burning)
  msgs |> should.equal(["the fire is burning"])
}

pub fn light_costs_five_wood_when_wood_exists_test() {
  let #(lit, _) = room.light_fire(state.new() |> state.set_store("wood", 7))
  room.fire(lit) |> should.equal(room.Burning)
  state.get_store(lit, "wood") |> should.equal(2)
}

pub fn light_blocked_without_enough_wood_test() {
  let #(s, msgs) = room.light_fire(state.new() |> state.set_store("wood", 3))
  room.fire(s) |> should.equal(room.Dead)
  msgs |> should.equal(["not enough wood to get the fire going"])
}

pub fn stoke_raises_and_costs_one_wood_test() {
  let s =
    state.new()
    |> state.set_store("wood", 10)
    |> state.set_game("fire", 2)
  let #(s2, msgs) = room.stoke_fire(s)
  room.fire(s2) |> should.equal(room.Burning)
  state.get_store(s2, "wood") |> should.equal(9)
  msgs |> should.equal(["the fire is burning"])
}

pub fn stoke_blocked_when_wood_runs_out_test() {
  let s =
    state.new()
    |> state.set_store("wood", 0)
    |> state.set_game("fire", 3)
  let #(s2, msgs) = room.stoke_fire(s)
  msgs |> should.equal(["the wood has run out"])
  room.fire(s2) |> should.equal(room.Burning)
}

pub fn stoke_caps_at_roaring_test() {
  let s =
    state.new()
    |> state.set_store("wood", 100)
    |> state.set_game("fire", 4)
  let #(s2, _) = room.stoke_fire(s)
  room.fire(s2) |> should.equal(room.Roaring)
}

pub fn cool_fire_decays_test() {
  let #(s, _) = room.cool_fire(state.new() |> state.set_game("fire", 3))
  room.fire(s) |> should.equal(room.Flickering)
}

pub fn cool_dead_fire_is_noop_test() {
  let #(s, msgs) = room.cool_fire(state.new())
  room.fire(s) |> should.equal(room.Dead)
  msgs |> should.equal([])
}

pub fn adjust_temp_warms_toward_fire_test() {
  let #(s, _) = room.adjust_temp(state.new() |> state.set_game("fire", 3))
  room.temperature(s) |> should.equal(room.Cold)
}

pub fn adjust_temp_cools_toward_dead_fire_test() {
  let #(s, _) =
    room.adjust_temp(state.new() |> state.set_game("temperature", 4))
  room.temperature(s) |> should.equal(room.Warm)
}

pub fn adjust_temp_stable_when_matched_test() {
  let s =
    state.new()
    |> state.set_game("fire", 2)
    |> state.set_game("temperature", 2)
  let #(s2, msgs) = room.adjust_temp(s)
  room.temperature(s2) |> should.equal(room.Mild)
  msgs |> should.equal([])
}
