import adarkroom/events
import adarkroom/ship
import adarkroom/state
import gleam/list
import gleam/option.{Some}
import gleeunit/should

pub fn reinforcing_the_hull_costs_an_alloy_test() {
  let s = state.new() |> state.set_store("alien alloy", 2)
  let #(after, msgs) = ship.reinforce_hull(s)
  ship.hull(after) |> should.equal(1)
  state.get_store(after, "alien alloy") |> should.equal(1)
  msgs |> should.equal([])
}

pub fn an_empty_store_reinforces_nothing_test() {
  let #(after, msgs) = ship.reinforce_hull(state.new())
  ship.hull(after) |> should.equal(0)
  msgs |> should.equal(["not enough alien alloy"])
}

pub fn upgrading_the_engine_costs_an_alloy_test() {
  let s =
    state.new()
    |> state.set_store("alien alloy", 1)
    |> state.set_game("spaceShip.thrusters", 1)
  let #(after, _) = ship.upgrade_engine(s)
  ship.thrusters(after) |> should.equal(2)
  state.get_store(after, "alien alloy") |> should.equal(0)
}

pub fn the_fleet_hovers_above_once_test() {
  let #(s, msgs) = ship.see_ship(state.new())
  msgs
  |> should.equal([
    "somewhere above the debris cloud, the wanderer fleet hovers. been on this rock too long.",
  ])
  let #(_, again) = ship.see_ship(s)
  again |> should.equal([])
}

pub fn the_warning_offers_flight_or_lingering_test() {
  let assert Ok(start) = list.key_find(ship.ready_to_leave().scenes, "start")
  let assert Ok(fly) = list.key_find(start.buttons, "fly")
  fly.effect |> should.equal(Some(events.LiftOff))
  let assert Ok(wait) = list.key_find(start.buttons, "wait")
  wait.effect |> should.equal(Some(events.ClearCooldown("liftoff")))
  // Flying remembers the warning was seen.
  let assert Some(on_click) = fly.on_click
  let #(after, _) = on_click(state.new())
  ship.seen_warning(after) |> should.be_true
}
