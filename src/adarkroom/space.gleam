//// The ascent, ported from `space.js` — the pure flight mechanics: the ship
//// in a 700-pixel field, asteroids falling through it, collisions against
//// the hull, and the climb to 60km. The timers, keyboard and panel ride on
//// top in the app layer.

import adarkroom/ship
import adarkroom/state.{type State}
import gleam/float
import gleam/int
import gleam/list

/// `SHIP_SPEED` — the base pixels-per-frame, before thrusters.
pub const ship_speed = 3.0

/// `BASE_ASTEROID_SPEED` — the slowest fall, in ms; rolls shave up to 65% off.
pub const base_asteroid_ms = 1500

/// `FTB_SPEED` — the fade to black; surviving it is the win.
pub const ascent_ms = 60_000

/// The ship-movement frame (`setInterval(Space.moveShip, 33)`).
pub const frame_ms = 33

/// The field: positions are clamped to [10, 690] of a 700px square; asteroids
/// fall from 0 to 740.
pub const field_floor = 740.0

/// An asteroid's glyph box. The JS measures the rendered character's div;
/// these match the original 12px monospace glyph closely enough to keep the
/// same feel without a DOM measurement.
pub const asteroid_width = 10.0

pub const asteroid_height = 15.0

/// A held direction.
pub type Dir {
  Up
  Down
  Left
  Right
}

/// A falling asteroid: its glyph, horizontal lane, and fall timing — its
/// height at any instant derives from the clock, no per-asteroid state.
pub type Asteroid {
  Asteroid(chara: String, x: Float, spawned_at: Int, duration: Int)
}

/// A flight in progress.
pub type Flight {
  Flight(
    x: Float,
    y: Float,
    hull: Int,
    altitude: Int,
    up: Bool,
    down: Bool,
    left: Bool,
    right: Bool,
    asteroids: List(Asteroid),
    done: Bool,
  )
}

/// Lift off (`onArrival`): centred at (350, 350), the hull as plated.
pub fn begin(s: State) -> Flight {
  Flight(
    x: 350.0,
    y: 350.0,
    hull: ship.hull(s),
    altitude: 0,
    up: False,
    down: False,
    left: False,
    right: False,
    asteroids: [],
    done: False,
  )
}

/// Pixels per frame (`getSpeed`): the base plus one per thruster.
pub fn speed(s: State) -> Float {
  ship_speed +. int.to_float(ship.thrusters(s))
}

/// Press or release a direction.
pub fn set_dir(flight: Flight, dir: Dir, held: Bool) -> Flight {
  case dir {
    Up -> Flight(..flight, up: held)
    Down -> Flight(..flight, down: held)
    Left -> Flight(..flight, left: held)
    Right -> Flight(..flight, right: held)
  }
}

/// One movement frame (`moveShip`): held directions push the ship (up beats
/// down, left beats right — the JS else-if), diagonals are normalised, the
/// step scales with the real time elapsed, and the field clamps to [10, 690].
pub fn move(flight: Flight, s: State, dt_ms: Int) -> Flight {
  let v = speed(s)
  let dy = case flight.up, flight.down {
    True, _ -> 0.0 -. v
    False, True -> v
    False, False -> 0.0
  }
  let dx = case flight.left, flight.right {
    True, _ -> 0.0 -. v
    False, True -> v
    False, False -> 0.0
  }
  let #(dx, dy) = case dx != 0.0 && dy != 0.0 {
    True -> #(dx /. root2, dy /. root2)
    False -> #(dx, dy)
  }
  let scale = int.to_float(dt_ms) /. int.to_float(frame_ms)
  Flight(
    ..flight,
    x: clamp(flight.x +. dx *. scale),
    y: clamp(flight.y +. dy *. scale),
  )
}

const root2 = 1.4142135623730951

fn clamp(v: Float) -> Float {
  float.min(690.0, float.max(10.0, v))
}

/// Where an asteroid hangs at this instant: linear from 0 to the floor over
/// its fall duration.
pub fn asteroid_y(asteroid: Asteroid, now: Int) -> Float {
  int.to_float(now - asteroid.spawned_at)
  /. int.to_float(asteroid.duration)
  *. field_floor
}

/// One collision-and-pruning pass over the field: every asteroid overlapping
/// the ship takes a point of hull and bursts; ones past the floor vanish.
pub fn collide(flight: Flight, now: Int) -> Flight {
  let #(hits, rest) =
    list.partition(flight.asteroids, fn(a) {
      let y = asteroid_y(a, now)
      a.x <=. flight.x
      && a.x +. asteroid_width >=. flight.x
      && y <=. flight.y
      && y +. asteroid_height >=. flight.y
    })
  let falling = list.filter(rest, fn(a) { asteroid_y(a, now) <=. field_floor })
  Flight(..flight, hull: flight.hull - list.length(hits), asteroids: falling)
}

/// How many asteroids a wave brings (`createAsteroid`'s escalation): one, and
/// the heavens harden with altitude.
pub fn wave_size(altitude: Int) -> Int {
  1
  + case altitude > 10 {
    True -> 1
    False -> 0
  }
  + case altitude > 20 {
    True -> 2
    False -> 0
  }
  + case altitude > 40 {
    True -> 2
    False -> 0
  }
}

/// The pause before the next wave: `1000 - altitude * 10` ms.
pub fn wave_delay_ms(altitude: Int) -> Int {
  1000 - altitude * 10
}

/// Spawn a wave from its rolls — three per asteroid: the glyph (fifths of the
/// roll: # $ % & H), the lane (`floor(roll * 700)`), and the fall time
/// (`1500 - floor(roll * 975)`).
pub fn spawn(flight: Flight, now: Int, rolls: List(Float)) -> Flight {
  case rolls {
    [chara, lane, fall, ..rest] -> {
      let asteroid =
        Asteroid(
          chara: glyph(chara),
          x: int.to_float(float.truncate(lane *. 700.0)),
          spawned_at: now,
          duration: base_asteroid_ms
            - float.truncate(fall *. { int.to_float(base_asteroid_ms) *. 0.65 }),
        )
      spawn(
        Flight(..flight, asteroids: [asteroid, ..flight.asteroids]),
        now,
        rest,
      )
    }
    _ -> flight
  }
}

fn glyph(roll: Float) -> String {
  case roll {
    r if r <. 0.2 -> "#"
    r if r <. 0.4 -> "$"
    r if r <. 0.6 -> "%"
    r if r <. 0.8 -> "&"
    _ -> "H"
  }
}

/// A second of climb; the clock tops out past 60km (the win is the fade
/// completing, not the altitude).
/// The air's name at this altitude (`Space.setTitle`), shown as the
/// document title through the ascent.
pub fn atmosphere(altitude: Int) -> String {
  case altitude {
    a if a < 10 -> "Troposphere"
    a if a < 20 -> "Stratosphere"
    a if a < 30 -> "Mesosphere"
    a if a < 45 -> "Thermosphere"
    a if a < 60 -> "Exosphere"
    _ -> "Space"
  }
}

pub fn climb(flight: Flight) -> Flight {
  Flight(..flight, altitude: flight.altitude + 1)
}
