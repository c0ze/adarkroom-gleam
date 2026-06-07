import adarkroom/model.{Navigate, Tick}
import adarkroom/notifications
import adarkroom/room
import adarkroom/state
import gleeunit/should

pub fn init_starts_in_room_test() {
  let m = model.init()
  m.location |> should.equal(model.Room)
  m.ticks |> should.equal(0)
}

pub fn tick_increments_test() {
  let m =
    model.init()
    |> model.update(Tick)
    |> model.update(Tick)
  m.ticks |> should.equal(2)
}

pub fn navigate_changes_location_test() {
  let m = model.init() |> model.update(Navigate(to: model.Outside))
  m.location |> should.equal(model.Outside)
}

pub fn navigate_preserves_ticks_test() {
  let m =
    model.init()
    |> model.update(Tick)
    |> model.update(Navigate(to: model.World))
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
  let arrived = model.update(m, Navigate(to: model.Outside))
  notifications.messages(arrived.notifications)
  |> should.equal(["a stranger arrives."])
}

pub fn light_fire_msg_lights_and_notifies_test() {
  let m = model.update(model.init(), model.LightFire)
  room.fire(m.state) |> should.equal(room.Burning)
  // Lighting also reveals the forest, so the log carries those messages too
  // (newest first).
  notifications.messages(m.notifications)
  |> should.equal([
    "the wood is running out.",
    "the wind howls outside.",
    "the fire is burning.",
  ])
}

pub fn light_fire_reveals_forest_test() {
  let m = model.update(model.init(), model.LightFire)
  state.get_store(m.state, "wood") |> should.equal(4)
  state.has_feature(m.state, "location.outside") |> should.equal(True)
  model.unlocked_locations(m) |> should.equal([model.Room, model.Outside])
}
