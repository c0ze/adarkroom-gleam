import adarkroom/model.{Navigate, Tick}
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
