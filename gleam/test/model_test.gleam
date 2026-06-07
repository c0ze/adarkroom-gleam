import adarkroom/model.{Navigate, Tick}
import adarkroom/notifications
import adarkroom/room
import adarkroom/state
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
}

pub fn failed_light_does_not_summon_builder_test() {
  let base = model.init()
  let m = model.Model(..base, state: state.set_store(base.state, "wood", 3))
  let after = run(m, model.LightFire)
  room.fire(after.state) |> should.equal(room.Dead)
  room.builder_level(after.state) |> should.equal(-1)
  state.has_feature(after.state, "location.outside") |> should.equal(False)
}
