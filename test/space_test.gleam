import adarkroom/space
import adarkroom/state
import gleam/list
import gleeunit/should

fn thrusters(n: Int) -> state.State {
  state.set_game(state.new(), "spaceShip.thrusters", n)
}

pub fn liftoff_starts_centred_with_the_plated_hull_test() {
  let s =
    state.new()
    |> state.set_game("spaceShip.hull", 3)
  let flight = space.begin(s)
  flight.x |> should.equal(350.0)
  flight.y |> should.equal(350.0)
  flight.hull |> should.equal(3)
  flight.altitude |> should.equal(0)
}

pub fn thrusters_set_the_pace_test() {
  space.speed(thrusters(1)) |> should.equal(4.0)
  space.speed(thrusters(5)) |> should.equal(8.0)
}

pub fn a_held_direction_moves_the_ship_test() {
  let flight = space.set_dir(space.begin(thrusters(1)), space.Up, True)
  let after = space.move(flight, thrusters(1), 33)
  after.y |> should.equal(346.0)
  after.x |> should.equal(350.0)
}

pub fn up_beats_down_test() {
  // The JS else-if: with both held, only up applies.
  let flight =
    space.begin(thrusters(1))
    |> space.set_dir(space.Up, True)
    |> space.set_dir(space.Down, True)
  space.move(flight, thrusters(1), 33).y |> should.equal(346.0)
}

pub fn diagonals_are_normalised_test() {
  let flight =
    space.begin(thrusters(1))
    |> space.set_dir(space.Up, True)
    |> space.set_dir(space.Left, True)
  let after = space.move(flight, thrusters(1), 33)
  // 4 / sqrt(2) ≈ 2.828 off each axis.
  { after.x <. 348.0 && after.x >. 347.0 } |> should.be_true
  { after.y <. 348.0 && after.y >. 347.0 } |> should.be_true
}

pub fn the_field_clamps_the_ship_test() {
  let flight =
    space.Flight(..space.begin(thrusters(20)), x: 12.0)
    |> space.set_dir(space.Left, True)
  space.move(flight, thrusters(20), 33).x |> should.equal(10.0)
}

pub fn a_longer_frame_moves_further_test() {
  // dt-scaling: a 66ms frame covers two frames' ground.
  let flight = space.set_dir(space.begin(thrusters(1)), space.Right, True)
  space.move(flight, thrusters(1), 66).x |> should.equal(358.0)
}

pub fn an_asteroid_falls_on_the_clock_test() {
  let a = space.Asteroid(chara: "#", x: 100.0, spawned_at: 1000, duration: 1500)
  space.asteroid_y(a, 1000) |> should.equal(0.0)
  space.asteroid_y(a, 1750) |> should.equal(370.0)
  space.asteroid_y(a, 2500) |> should.equal(740.0)
}

pub fn a_collision_costs_hull_and_bursts_the_rock_test() {
  // An asteroid right on the ship at this instant: half-fallen at (348, 370).
  let a = space.Asteroid(chara: "#", x: 348.0, spawned_at: 0, duration: 1000)
  let flight =
    space.Flight(..space.begin(thrusters(1)), hull: 2, y: 375.0, asteroids: [a])
  let after = space.collide(flight, 500)
  after.hull |> should.equal(1)
  after.asteroids |> should.equal([])
}

pub fn a_miss_keeps_falling_test() {
  let a = space.Asteroid(chara: "#", x: 100.0, spawned_at: 0, duration: 1000)
  let flight =
    space.Flight(..space.begin(thrusters(1)), hull: 2, asteroids: [a])
  let after = space.collide(flight, 500)
  after.hull |> should.equal(2)
  after.asteroids |> list.length |> should.equal(1)
}

pub fn landed_rocks_vanish_test() {
  let a = space.Asteroid(chara: "#", x: 100.0, spawned_at: 0, duration: 1000)
  let flight = space.Flight(..space.begin(thrusters(1)), asteroids: [a])
  space.collide(flight, 1500).asteroids |> should.equal([])
}

pub fn the_heavens_harden_with_altitude_test() {
  space.wave_size(0) |> should.equal(1)
  space.wave_size(11) |> should.equal(2)
  space.wave_size(21) |> should.equal(4)
  space.wave_size(41) |> should.equal(6)
  space.wave_delay_ms(0) |> should.equal(1000)
  space.wave_delay_ms(50) |> should.equal(500)
}

pub fn a_wave_spawns_from_its_rolls_test() {
  let flight = space.begin(thrusters(1))
  let after = space.spawn(flight, 5000, [0.1, 0.5, 0.0, 0.9, 0.0, 1.0])
  let assert [second, first] = after.asteroids
  first.chara |> should.equal("#")
  first.x |> should.equal(350.0)
  first.duration |> should.equal(1500)
  second.chara |> should.equal("H")
  second.x |> should.equal(0.0)
  // 1500 - floor(1.0 * 975) = 525.
  second.duration |> should.equal(525)
  first.spawned_at |> should.equal(5000)
}

pub fn the_air_thins_by_name_test() {
  space.atmosphere(0) |> should.equal("Troposphere")
  space.atmosphere(10) |> should.equal("Stratosphere")
  space.atmosphere(29) |> should.equal("Mesosphere")
  space.atmosphere(44) |> should.equal("Thermosphere")
  space.atmosphere(59) |> should.equal("Exosphere")
  space.atmosphere(60) |> should.equal("Space")
}
