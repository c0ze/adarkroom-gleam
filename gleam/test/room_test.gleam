import adarkroom/room
import adarkroom/state
import gleeunit/should

pub fn fire_from_int_clamps_test() {
  room.fire_from_int(-1) |> should.equal(room.Dead)
  room.fire_from_int(0) |> should.equal(room.Dead)
  room.fire_from_int(3) |> should.equal(room.Burning)
  room.fire_from_int(9) |> should.equal(room.Roaring)
}

pub fn temp_from_int_clamps_test() {
  room.temp_from_int(-1) |> should.equal(room.Freezing)
  room.temp_from_int(0) |> should.equal(room.Freezing)
  room.temp_from_int(2) |> should.equal(room.Mild)
  room.temp_from_int(9) |> should.equal(room.Hot)
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

pub fn unlock_forest_gives_wood_and_reveals_outside_test() {
  let #(s, msgs) = room.unlock_forest(state.new())
  state.get_store(s, "wood") |> should.equal(4)
  state.has_feature(s, "location.outside") |> should.equal(True)
  msgs |> should.equal(["the wind howls outside", "the wood is running out"])
}

pub fn unlock_forest_is_noop_once_unlocked_test() {
  let s = state.new() |> state.set_feature("location.outside", True)
  let #(s2, msgs) = room.unlock_forest(s)
  msgs |> should.equal([])
  state.get_store(s2, "wood") |> should.equal(0)
}

pub fn on_fire_change_summons_builder_when_glowing_test() {
  let s = state.new() |> state.set_game("fire", 3)
  let #(s2, msgs) = room.on_fire_change(s)
  room.builder_level(s2) |> should.equal(0)
  msgs
  |> should.equal([
    "the light from the fire spills from the windows, out into the dark",
  ])
}

pub fn on_fire_change_noop_when_dim_test() {
  let #(s2, msgs) =
    room.on_fire_change(state.new() |> state.set_game("fire", 1))
  room.builder_level(s2) |> should.equal(-1)
  msgs |> should.equal([])
}

pub fn on_fire_change_noop_when_builder_already_arrived_test() {
  let s =
    state.new() |> state.set_game("fire", 3) |> state.set_game("builder", 0)
  let #(_, msgs) = room.on_fire_change(s)
  msgs |> should.equal([])
}

pub fn progress_builder_stumbles_and_reveals_forest_test() {
  let #(s2, msgs) =
    room.progress_builder(state.new() |> state.set_game("builder", 0))
  room.builder_level(s2) |> should.equal(1)
  state.get_store(s2, "wood") |> should.equal(4)
  state.has_feature(s2, "location.outside") |> should.equal(True)
  msgs
  |> should.equal([
    "a ragged stranger stumbles through the door and collapses in the corner",
    "the wind howls outside",
    "the wood is running out",
  ])
}

pub fn progress_builder_waits_for_warmth_test() {
  let #(s2, msgs) =
    room.progress_builder(state.new() |> state.set_game("builder", 1))
  room.builder_level(s2) |> should.equal(1)
  msgs |> should.equal([])
}

pub fn progress_builder_advances_when_warm_test() {
  let s =
    state.new()
    |> state.set_game("builder", 1)
    |> state.set_game("temperature", 3)
  let #(s2, _) = room.progress_builder(s)
  room.builder_level(s2) |> should.equal(2)
}

pub fn builder_up_test() {
  room.builder_up(state.new() |> state.set_game("builder", 3))
  |> should.equal(True)
  room.builder_up(state.new() |> state.set_game("builder", 2))
  |> should.equal(False)
}

pub fn become_helper_advances_sleeping_builder_test() {
  let #(s2, msgs) =
    room.become_helper(state.new() |> state.set_game("builder", 3))
  room.builder_level(s2) |> should.equal(4)
  msgs
  |> should.equal([
    "the stranger is standing by the fire. she says she can help. says she builds things.",
  ])
}

pub fn become_helper_noop_before_sleeping_test() {
  let #(s2, msgs) =
    room.become_helper(state.new() |> state.set_game("builder", 2))
  room.builder_level(s2) |> should.equal(2)
  msgs |> should.equal([])
}

pub fn become_helper_noop_when_already_helping_test() {
  let #(s2, msgs) =
    room.become_helper(state.new() |> state.set_game("builder", 4))
  room.builder_level(s2) |> should.equal(4)
  msgs |> should.equal([])
}

pub fn builder_helping_test() {
  room.builder_helping(state.new() |> state.set_game("builder", 4))
  |> should.equal(True)
  room.builder_helping(state.new() |> state.set_game("builder", 3))
  |> should.equal(False)
}

pub fn reset_cool_zeroes_deadline_test() {
  let s = room.reset_cool(state.new() |> state.set_game("coolAt", 12_345))
  state.get_game(s, "coolAt") |> should.equal(0)
}

pub fn tick_cool_arms_deadline_when_unset_test() {
  let #(s2, msgs) =
    room.tick_cool(state.new() |> state.set_game("fire", 3), 1000)
  state.get_game(s2, "coolAt") |> should.equal(1000 + room.fire_cool_delay_ms)
  room.fire(s2) |> should.equal(room.Burning)
  msgs |> should.equal([])
}

pub fn tick_cool_waits_before_deadline_test() {
  let s =
    state.new() |> state.set_game("fire", 3) |> state.set_game("coolAt", 5000)
  let #(s2, msgs) = room.tick_cool(s, 1000)
  room.fire(s2) |> should.equal(room.Burning)
  msgs |> should.equal([])
}

pub fn tick_cool_cools_once_deadline_passes_test() {
  let s =
    state.new() |> state.set_game("fire", 3) |> state.set_game("coolAt", 500)
  let #(s2, _) = room.tick_cool(s, 1000)
  room.fire(s2) |> should.equal(room.Flickering)
  state.get_game(s2, "coolAt") |> should.equal(1000 + room.fire_cool_delay_ms)
}

pub fn tick_cool_noop_when_dead_test() {
  let #(s2, msgs) = room.tick_cool(state.new(), 999_999)
  room.fire(s2) |> should.equal(room.Dead)
  msgs |> should.equal([])
}

pub fn light_fire_resets_cool_test() {
  let #(s2, _) = room.light_fire(state.new() |> state.set_game("coolAt", 9999))
  state.get_game(s2, "coolAt") |> should.equal(0)
}

pub fn failed_light_keeps_cool_test() {
  let s =
    state.new() |> state.set_store("wood", 3) |> state.set_game("coolAt", 9999)
  let #(s2, _) = room.light_fire(s)
  state.get_game(s2, "coolAt") |> should.equal(9999)
}

pub fn failed_stoke_keeps_cool_test() {
  let s =
    state.new()
    |> state.set_store("wood", 0)
    |> state.set_game("fire", 3)
    |> state.set_game("coolAt", 9999)
  let #(s2, _) = room.stoke_fire(s)
  state.get_game(s2, "coolAt") |> should.equal(9999)
}
