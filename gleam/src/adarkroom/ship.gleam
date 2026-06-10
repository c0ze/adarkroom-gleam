//// An Old Starship, ported from `ship.js`: hull plating and engine tuning
//// bought with alien alloy, and — once there's any hull at all — the way off
//// this rock. The lift-off itself lands with Space.

import adarkroom/events.{type Event, Event, Scene, SceneButton}
import adarkroom/state.{type State}
import gleam/option.{None, Some}

/// `ALLOY_PER_HULL` — one alien alloy per point of hull.
pub const alloy_per_hull = 1

/// `ALLOY_PER_THRUSTER` — one alien alloy per engine upgrade.
pub const alloy_per_thruster = 1

/// `LIFTOFF_COOLDOWN` (120s), in milliseconds.
pub const liftoff_cooldown_ms = 120_000

/// The ship's hull plating (`game.spaceShip.hull`).
pub fn hull(s: State) -> Int {
  state.get_game(s, "spaceShip.hull")
}

/// The ship's thrusters (`game.spaceShip.thrusters`).
pub fn thrusters(s: State) -> Int {
  state.get_game(s, "spaceShip.thrusters")
}

/// First sight of the old wreck (`Ship.onArrival`): a note, once.
pub fn see_ship(s: State) -> #(State, List(String)) {
  case state.get_game(s, "spaceShip.seenShip") {
    0 -> #(state.set_game(s, "spaceShip.seenShip", 1), [
      "somewhere above the debris cloud, the wanderer fleet hovers. been on this rock too long.",
    ])
    _ -> #(s, [])
  }
}

/// Plate the hull with an alien alloy (`reinforceHull`).
pub fn reinforce_hull(s: State) -> #(State, List(String)) {
  buy_upgrade(s, alloy_per_hull, "spaceShip.hull")
}

/// Tune the engine with an alien alloy (`upgradeEngine`).
pub fn upgrade_engine(s: State) -> #(State, List(String)) {
  buy_upgrade(s, alloy_per_thruster, "spaceShip.thrusters")
}

fn buy_upgrade(s: State, cost: Int, key: String) -> #(State, List(String)) {
  case state.get_store(s, "alien alloy") < cost {
    True -> #(s, ["not enough alien alloy"])
    False -> #(
      s
        |> state.add_store("alien alloy", -cost)
        |> state.set_game(key, state.get_game(s, key) + 1),
      [],
    )
  }
}

/// Whether the player has been warned there's no coming back.
pub fn seen_warning(s: State) -> Bool {
  state.get_game(s, "spaceShip.seenWarning") != 0
}

/// The Ready to Leave? warning, shown the first time the lift-off button is
/// pressed (`checkLiftOff`): fly, or linger — lingering refunds the button's
/// cooldown.
pub fn ready_to_leave() -> Event {
  Event(title: "Ready to Leave?", is_available: fn(_) { True }, scenes: [
    #(
      "start",
      Scene(
        text: ["time to get out of this place. won't be coming back."],
        notification: None,
        reward: [],
        combat: False,
        on_load: None,
        on_load_rng: None,
        setpiece: None,
        buttons: [
          #(
            "fly",
            SceneButton(
              text: "lift off",
              cost: [],
              reward: [],
              notification: None,
              available: None,
              on_click: Some(fn(s) {
                #(state.set_game(s, "spaceShip.seenWarning", 1), [])
              }),
              link: None,
              effect: Some(events.LiftOff),
              next: events.End,
            ),
          ),
          #(
            "wait",
            SceneButton(
              text: "linger",
              cost: [],
              reward: [],
              notification: None,
              available: None,
              on_click: None,
              link: None,
              effect: Some(events.ClearCooldown("liftoff")),
              next: events.End,
            ),
          ),
        ],
      ),
    ),
  ])
}
