import adarkroom/craft
import adarkroom/model.{Navigate, Tick}
import adarkroom/notifications
import adarkroom/room
import adarkroom/state
import gleam/set
import gleeunit/should

/// Apply an update and discard the effect.
fn run(m: model.Model, msg: model.Msg) -> model.Model {
  model.update(m, msg).0
}

pub fn init_starts_in_room_test() {
  let m = model.init()
  m.location |> should.equal(model.Room)
  m.ticks |> should.equal(0)
}

pub fn tick_increments_test() {
  let m = run(run(model.init(), Tick), Tick)
  m.ticks |> should.equal(2)
}

pub fn tick_reveals_buildings_when_builder_helps_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("builder", 4)
        |> state.set_store("wood", 5),
    )
  let after = run(m, Tick)
  set.contains(after.revealed, "trap") |> should.equal(True)
  notifications.messages(after.notifications)
  |> should.equal([
    "builder says she can make traps to catch any creatures might still be alive out there.",
  ])
}

pub fn tick_reveals_nothing_without_helper_test() {
  let after = run(model.init(), Tick)
  set.size(after.revealed) |> should.equal(0)
}

pub fn navigate_changes_location_test() {
  let m = run(model.init(), Navigate(to: model.Outside))
  m.location |> should.equal(model.Outside)
}

pub fn navigate_preserves_ticks_test() {
  let m = run(run(model.init(), Tick), Navigate(to: model.World))
  m.ticks |> should.equal(1)
  m.location |> should.equal(model.World)
}

pub fn unlocked_only_room_by_default_test() {
  model.unlocked_locations(model.init()) |> should.equal([model.Room])
}

pub fn unlocked_includes_outside_when_feature_set_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: state.set_feature(base.state, "location.outside", True),
    )
  model.unlocked_locations(m) |> should.equal([model.Room, model.Outside])
}

pub fn navigate_flushes_target_queue_test() {
  let base = model.init()
  let queued =
    notifications.notify(
      base.notifications,
      current: "room",
      target: "outside",
      text: "a stranger arrives",
    )
  let m = model.Model(..base, notifications: queued)
  let arrived = run(m, Navigate(to: model.Outside))
  notifications.messages(arrived.notifications)
  |> should.equal(["a stranger arrives."])
}

pub fn light_fire_burns_and_notifies_test() {
  let m = run(model.init(), model.LightFire)
  room.fire(m.state) |> should.equal(room.Burning)
  // Fire burns, then the room glows and the builder is summoned; the forest
  // is not revealed until the builder stumbles in.
  notifications.messages(m.notifications)
  |> should.equal([
    "the light from the fire spills from the windows, out into the dark.",
    "the fire is burning.",
  ])
}

pub fn light_fire_summons_builder_without_revealing_forest_test() {
  let m = run(model.init(), model.LightFire)
  room.builder_level(m.state) |> should.equal(0)
  state.has_feature(m.state, "location.outside") |> should.equal(False)
}

pub fn builder_progress_stumbles_in_and_reveals_forest_test() {
  let m =
    model.init()
    |> run(model.LightFire)
    |> run(model.BuilderProgress)
  room.builder_level(m.state) |> should.equal(1)
  state.get_store(m.state, "wood") |> should.equal(4)
  state.has_feature(m.state, "location.outside") |> should.equal(True)
  model.unlocked_locations(m) |> should.equal([model.Room, model.Outside])
  // Newest first: the forest reveal follows the stumble-in, after lighting.
  notifications.messages(m.notifications)
  |> should.equal([
    "the wood is running out.",
    "the wind howls outside.",
    "a ragged stranger stumbles through the door and collapses in the corner.",
    "the light from the fire spills from the windows, out into the dark.",
    "the fire is burning.",
  ])
}

pub fn arriving_at_room_makes_sleeping_builder_help_test() {
  // Builder is "up" (level 3, sleeping) and the player is away; returning to the
  // Room is when she offers to help (faithful to the original's onArrival).
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Outside,
      state: state.set_game(base.state, "builder", 3),
    )
  let arrived = run(m, Navigate(to: model.Room))
  room.builder_helping(arrived.state) |> should.equal(True)
  notifications.messages(arrived.notifications)
  |> should.equal([
    "the stranger is standing by the fire. she says she can help. says she builds things.",
  ])
}

pub fn arriving_at_room_noop_when_builder_not_sleeping_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Outside,
      state: state.set_game(base.state, "builder", 2),
    )
  let arrived = run(m, Navigate(to: model.Room))
  room.builder_level(arrived.state) |> should.equal(2)
  notifications.messages(arrived.notifications) |> should.equal([])
}

pub fn arriving_elsewhere_does_not_make_builder_help_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: state.set_feature(
        state.set_game(base.state, "builder", 3),
        "location.outside",
        True,
      ),
    )
  let arrived = run(m, Navigate(to: model.Outside))
  room.builder_level(arrived.state) |> should.equal(3)
}

pub fn failed_light_does_not_summon_builder_test() {
  let base = model.init()
  let m = model.Model(..base, state: state.set_store(base.state, "wood", 3))
  let after = run(m, model.LightFire)
  room.fire(after.state) |> should.equal(room.Dead)
  room.builder_level(after.state) |> should.equal(-1)
  state.has_feature(after.state, "location.outside") |> should.equal(False)
}

pub fn build_message_raises_building_and_notifies_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("temperature", 2)
        |> state.set_store("wood", 50),
    )
  let after = run(m, model.Build("trap"))
  craft.building_count(after.state, "trap") |> should.equal(1)
  state.get_store(after.state, "wood") |> should.equal(40)
  notifications.messages(after.notifications)
  |> should.equal(["more traps to catch more creatures."])
}

pub fn buy_message_adds_good_and_spends_fur_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("building.trading post", 1)
        |> state.set_store("fur", 200),
    )
  let after = run(m, model.Buy("scales"))
  state.get_store(after.state, "scales") |> should.equal(1)
  state.get_store(after.state, "fur") |> should.equal(50)
}

pub fn light_fire_resets_cool_deadline_test() {
  let base = model.init()
  let m = model.Model(..base, state: state.set_game(base.state, "coolAt", 9999))
  let after = run(m, model.LightFire)
  // fire_action re-arms cooling: the deadline is reset (next CoolCheck re-arms).
  state.get_game(after.state, "coolAt") |> should.equal(0)
}
