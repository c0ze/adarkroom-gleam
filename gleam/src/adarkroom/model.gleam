//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` returns the new model together with any
//// effects (e.g. one-shot timers for the builder's timed progression).

import adarkroom/craft
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/rng
import adarkroom/room
import adarkroom/state.{type State}
import adarkroom/timer
import adarkroom/trade
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/set.{type Set}
import lustre/effect.{type Effect}

/// The screens the player can be on.
pub type Location {
  Room
  Outside
  World
  Path
  Ship
  Space
  Fabricator
}

pub type Msg {
  /// The periodic game-loop tick.
  Tick
  /// Switch to another location.
  Navigate(to: Location)
  /// Light the fire.
  LightFire
  /// Stoke the fire.
  StokeFire
  /// Timer: a time-stamped check that cools the fire once its deadline passes.
  CoolCheck(at: Int)
  /// Timer: move the temperature toward the fire.
  AdjustTemp
  /// Timer: advance the builder's arrival/progression.
  BuilderProgress
  /// Build or craft the named structure/item.
  Build(name: String)
  /// Buy the named trade good at the trading post.
  Buy(name: String)
  /// Gather wood from the forest (Outside).
  GatherWood
  /// Check the traps (Outside) — rolls the drops, then dispatches `TrapsChecked`.
  CheckTraps
  /// Apply trap drops from the supplied random rolls (one per drop).
  TrapsChecked(rolls: List(Float))
  /// Timer: newcomers arrive (the roll sizes the group); reschedules itself.
  PopulationIncreased(roll: Float)
  /// Timer: collect one round of income (every 10s).
  CollectIncome
}

pub type Model {
  Model(
    state: State,
    location: Location,
    ticks: Int,
    notifications: Notifications,
    /// Craftables whose buttons have been revealed. Runtime-only (not saved):
    /// a reloaded game re-derives it from current resources, as the original does.
    revealed: Set(String),
    /// Current wall-clock time in ms, refreshed each second — drives the
    /// cooldown bars.
    now: Int,
    /// Active button cooldowns, by id, as the wall-clock deadline (ms) at which
    /// they expire. Runtime-only: a reloaded game's buttons are ready.
    cooldowns: Dict(String, Int),
  )
}

/// The initial model for a new game.
pub fn init() -> Model {
  Model(
    state: state.new(),
    location: Room,
    ticks: 0,
    notifications: notifications.new(),
    revealed: set.new(),
    now: 0,
    cooldowns: dict.new(),
  )
}

// --- cooldowns --------------------------------------------------------------

/// Whether a button is currently on cooldown.
pub fn on_cooldown(model: Model, id: String) -> Bool {
  case dict.get(model.cooldowns, id) {
    Ok(deadline) -> model.now < deadline
    Error(Nil) -> False
  }
}

/// The remaining cooldown as a fraction of `duration` (1.0 just started, 0.0
/// ready) — the cooldown-bar width. A non-positive `duration` yields 0.0.
pub fn cooldown_fraction(model: Model, id: String, duration: Int) -> Float {
  case dict.get(model.cooldowns, id), duration > 0 {
    Ok(deadline), True if model.now < deadline ->
      int.to_float(deadline - model.now) /. int.to_float(duration)
    _, _ -> 0.0
  }
}

/// Start (or restart) a cooldown of `duration` ms on a button.
fn start_cooldown(model: Model, id: String, duration: Int) -> Model {
  Model(
    ..model,
    cooldowns: dict.insert(model.cooldowns, id, model.now + duration),
  )
}

/// State transition, paired with any effects to run.
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Tick -> {
      // The game loop also reveals any craftables whose conditions are now met.
      let #(revealed, messages) = craft.reveal(model.state, model.revealed)
      let ticked = Model(..model, ticks: model.ticks + 1, revealed:)
      #(notify_room(ticked, messages), effect.none())
    }

    Navigate(to: location) -> {
      let navigated =
        Model(
          ..model,
          location:,
          // Arriving at a location flushes its queued notifications.
          notifications: notifications.flush(
            model.notifications,
            location_key(location),
          ),
        )
      // Returning to the Room is when the builder, once up, offers to help;
      // the first step Outside notes the bleak forest.
      let arrived = case location {
        Room -> apply_room(navigated, room.become_helper(navigated.state))
        Outside -> apply_outside(navigated, outside.see_forest(navigated.state))
        _ -> navigated
      }
      #(arrived, effect.none())
    }

    LightFire -> fire_action(model, room.light_fire(model.state))
    StokeFire -> fire_action(model, room.stoke_fire(model.state))

    CoolCheck(at: now) -> #(
      apply_room(Model(..model, now:), room.tick_cool(model.state, now)),
      effect.none(),
    )
    AdjustTemp -> #(
      apply_room(model, room.adjust_temp(model.state)),
      effect.none(),
    )

    BuilderProgress -> {
      let progressed = apply_room(model, room.progress_builder(model.state))
      let next = case room.builder_up(progressed.state) {
        True -> effect.none()
        False -> delayed(room.builder_state_delay_ms, BuilderProgress)
      }
      #(progressed, next)
    }

    Build(name: name) -> {
      let had_huts = craft.building_count(model.state, "hut") > 0
      let built = apply_room(model, craft.build(model.state, name))
      // The first hut starts the flow of newcomers.
      let eff = case !had_huts && craft.building_count(built.state, "hut") > 0 {
        True -> schedule_population()
        False -> effect.none()
      }
      #(built, eff)
    }

    Buy(name: name) -> #(
      apply_room(model, trade.buy(model.state, name)),
      effect.none(),
    )

    GatherWood ->
      case on_cooldown(model, "gather") {
        True -> #(model, effect.none())
        False -> {
          let gathered = apply_outside(model, outside.gather_wood(model.state))
          #(
            start_cooldown(gathered, "gather", outside.gather_cooldown_ms),
            effect.none(),
          )
        }
      }

    CheckTraps ->
      case on_cooldown(model, "traps") {
        True -> #(model, effect.none())
        False -> #(
          start_cooldown(model, "traps", outside.traps_cooldown_ms),
          roll_traps(outside.num_drops(model.state)),
        )
      }

    TrapsChecked(rolls: rolls) -> #(
      apply_outside(model, outside.check_traps(model.state, rolls)),
      effect.none(),
    )

    PopulationIncreased(roll: roll) -> #(
      apply_outside(model, outside.increase_population(model.state, roll)),
      // Keep the village growing: schedule the next arrival.
      schedule_population(),
    )

    CollectIncome -> #(
      Model(..model, state: outside.collect_income(model.state)),
      effect.none(),
    )
  }
}

/// An effect that rolls `n` random values and reports them as `TrapsChecked`.
/// The randomness lives here, in the effect, so `update` stays pure.
fn roll_traps(n: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let rolls = list.map(list.repeat(Nil, n), fn(_) { rng.random() })
    dispatch(TrapsChecked(rolls))
  })
}

/// Schedule the next population increase after a random 0.5–2.5 minute delay
/// (faithful to the original's floor'd `_POP_DELAY`). Start the chain once the
/// first hut goes up; thereafter each increase reschedules itself.
pub fn schedule_population() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let steps = float.truncate(rng.random() *. 2.5)
    let delay = 30_000 + steps * 60_000
    let _ =
      timer.set_timeout(
        fn() { dispatch(PopulationIncreased(rng.random())) },
        delay,
      )
    Nil
  })
}

/// The population timer for a loaded game: resume it if any huts already stand.
pub fn resume_population(model: Model) -> Effect(Msg) {
  case craft.building_count(model.state, "hut") > 0 {
    True -> schedule_population()
    False -> effect.none()
  }
}

/// Apply a fire change, let the builder react (it is summoned once the room
/// first glows), and schedule the builder's progression if it just arrived.
fn fire_action(
  model: Model,
  transition: #(State, List(String)),
) -> #(Model, Effect(Msg)) {
  let after_fire = apply_room(model, transition)
  let after_builder =
    apply_room(after_fire, room.on_fire_change(after_fire.state))
  let just_arrived =
    room.builder_level(model.state) < 0
    && room.builder_level(after_builder.state) == 0
  let eff = case just_arrived {
    True -> delayed(room.builder_state_delay_ms, BuilderProgress)
    False -> effect.none()
  }
  #(after_builder, eff)
}

/// An effect that dispatches `msg` once after `ms` milliseconds.
fn delayed(ms: Int, msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = timer.set_timeout(fn() { dispatch(msg) }, ms)
    Nil
  })
}

/// Apply a transition: adopt the new state and emit its messages to a
/// location's notification stream.
fn apply_at(
  model: Model,
  target: String,
  result: #(State, List(String)),
) -> Model {
  let #(new_state, messages) = result
  notify_at(Model(..model, state: new_state), target, messages)
}

/// Apply a Room transition.
fn apply_room(model: Model, result: #(State, List(String))) -> Model {
  apply_at(model, "room", result)
}

/// Apply an Outside transition.
fn apply_outside(model: Model, result: #(State, List(String))) -> Model {
  apply_at(model, "outside", result)
}

/// Emit messages to a location's notification stream (queued there if the
/// player is elsewhere).
fn notify_at(model: Model, target: String, messages: List(String)) -> Model {
  let notes =
    list.fold(messages, model.notifications, fn(acc, text) {
      notifications.notify(
        acc,
        current: location_key(model.location),
        target: target,
        text: text,
      )
    })
  Model(..model, notifications: notes)
}

/// Emit messages to the Room's notification stream.
fn notify_room(model: Model, messages: List(String)) -> Model {
  notify_at(model, "room", messages)
}

/// Locations the player has unlocked. The Room is always available; the others
/// appear once their `location.*` feature flag is set.
pub fn unlocked_locations(model: Model) -> List(Location) {
  let optional = [
    #(Outside, "location.outside"),
    #(World, "location.world"),
    #(Path, "location.path"),
    #(Ship, "location.ship"),
    #(Space, "location.space"),
    #(Fabricator, "location.fabricator"),
  ]
  let extra =
    list.filter_map(optional, fn(pair) {
      let #(loc, feature) = pair
      case state.has_feature(model.state, feature) {
        True -> Ok(loc)
        False -> Error(Nil)
      }
    })
  [Room, ..extra]
}

/// A stable key for a location (notification queues, DOM ids).
pub fn location_key(location: Location) -> String {
  case location {
    Room -> "room"
    Outside -> "outside"
    World -> "world"
    Path -> "path"
    Ship -> "ship"
    Space -> "space"
    Fabricator -> "fabricator"
  }
}

/// The display title for a location (placeholder; dynamic titles come later).
pub fn location_title(location: Location) -> String {
  case location {
    Room -> "A Dark Room"
    Outside -> "A Silent Forest"
    World -> "The World"
    Path -> "A Dusty Path"
    Ship -> "An Old Starship"
    Space -> "The Stars"
    Fabricator -> "A Whirring Fabricator"
  }
}
