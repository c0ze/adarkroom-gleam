//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` returns the new model together with any
//// effects (e.g. one-shot timers for the builder's timed progression).

import adarkroom/combat
import adarkroom/craft
import adarkroom/encounters
import adarkroom/events
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/path
import adarkroom/rng
import adarkroom/room
import adarkroom/state.{type State}
import adarkroom/timer
import adarkroom/trade
import adarkroom/world.{type Expedition}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
  /// Assign `by` villagers to a worker role.
  IncreaseWorker(role: String, by: Int)
  /// Return `by` of a role's workers to gathering.
  DecreaseWorker(role: String, by: Int)
  /// Pack `by` more of an item for the path.
  IncreaseSupply(item: String, by: Int)
  /// Unpack `by` of an item from the path bag.
  DecreaseSupply(item: String, by: Int)
  /// Set off into the world; rolls a map seed, then dispatches `Embarked`.
  Embark
  /// Arrive in the world on a freshly-seeded map.
  Embarked(seed: Int)
  /// Step through the world.
  MoveNorth
  MoveSouth
  MoveWest
  MoveEast
  /// Schedule the next random event from a delay roll (initial / no-op reschedule).
  ScheduleEvent(delay: Float)
  /// A scheduled slot came due: reschedule, and start an event if one is free.
  TriggerEvent(pick: Float, delay: Float)
  /// The player pressed an event button; rolls then dispatches `ResolveEvent`.
  ChooseEvent(id: String)
  /// Apply the chosen button's outcome (the roll resolves any `Branch`).
  ResolveEvent(id: String, roll: Float)
  /// After a world step, maybe spring an encounter (rolls: trigger, then pick).
  MaybeFight(fight_roll: Float, pick_roll: Float)
  /// The player swings the named weapon at the enemy; rolls then resolves.
  StrikeEnemy(weapon: String)
  /// Apply the player's swing (the roll is its hit chance).
  ResolveStrike(weapon: String, roll: Float)
  /// The enemy takes its turn; rolls then resolves.
  EnemyTurn
  /// Apply the enemy's blow (the roll is its hit chance).
  ResolveEnemyTurn(roll: Float)
  /// Gather the defeated enemy's loot from the supplied rolls (two per drop).
  CollectLoot(rolls: List(Float))
  /// Use a healing item (cured meat / medicine / hypo) mid-fight.
  Heal(item: String)
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
    /// Sub-unit income carried between collections (e.g. a lone hunter's half
    /// fur), so stores stay whole. Runtime-only.
    income_buffer: Dict(String, Float),
    /// The active world expedition, while the player is out exploring.
    expedition: Option(Expedition),
    /// The random event currently on screen, if any. Runtime-only.
    active_event: Option(ActiveEvent),
    /// Wall-clock deadline (ms) for the next random event; `0` until first
    /// scheduled. Runtime-only, like the cooldowns.
    next_event_at: Int,
    /// The fight currently underway out in the world, if any. Runtime-only.
    combat: Option(combat.CombatState),
    /// Steps taken since the last world fight (the `fightMove` counter), so
    /// encounters can't crowd together. Reset each expedition. Runtime-only.
    fight_move: Int,
  )
}

/// A random event in progress: the event and the scene currently showing.
pub type ActiveEvent {
  ActiveEvent(event: events.Event, scene: String)
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
    income_buffer: dict.new(),
    expedition: None,
    active_event: None,
    next_event_at: 0,
    combat: None,
    fight_move: 0,
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

    CoolCheck(at: now) -> {
      let cooled =
        apply_room(Model(..model, now:), room.tick_cool(model.state, now))
      #(cooled, event_schedule_effect(cooled))
    }
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

    Buy(name: name) -> {
      let bought = apply_room(model, trade.buy(model.state, name))
      // The compass reveals the dusty path out of the village.
      let unlocked = case
        name == "compass" && state.get_store(bought.state, "compass") > 0
      {
        True ->
          Model(
            ..bought,
            state: state.set_feature(bought.state, "location.path", True),
          )
        False -> bought
      }
      #(unlocked, effect.none())
    }

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

    CollectIncome -> {
      let #(new_state, buffer) =
        outside.collect_income(model.state, model.income_buffer)
      #(Model(..model, state: new_state, income_buffer: buffer), effect.none())
    }

    IncreaseWorker(role: role, by: by) -> #(
      Model(..model, state: outside.increase_worker(model.state, role, by)),
      effect.none(),
    )

    DecreaseWorker(role: role, by: by) -> #(
      Model(..model, state: outside.decrease_worker(model.state, role, by)),
      effect.none(),
    )

    IncreaseSupply(item: item, by: by) -> #(
      Model(..model, state: path.increase_supply(model.state, item, by)),
      effect.none(),
    )

    DecreaseSupply(item: item, by: by) -> #(
      Model(..model, state: path.decrease_supply(model.state, item, by)),
      effect.none(),
    )

    // Only embark from the path, and only when not already exploring — guards
    // against a double-click or a replayed effect re-deducting supplies.
    Embark ->
      case model.location, model.expedition {
        Path, None -> #(model, roll_seed())
        _, _ -> #(model, effect.none())
      }

    Embarked(seed: seed) ->
      case model.location, model.expedition {
        Path, None -> {
          // Take the packed supplies out of the village and set out. Reaching
          // the world unlocks the events that only the well-travelled can draw
          // (the Scout, the Master).
          let stocked =
            list.fold(state.outfit_list(model.state), model.state, fn(s, item) {
              state.add_store(s, item.0, -item.1)
            })
            |> state.set_feature("location.world", True)
          let exp = world.begin(world.generate_map(rng.seed(seed)), stocked)
          #(
            Model(
              ..model,
              state: stocked,
              location: World,
              expedition: Some(exp),
              fight_move: 0,
              combat: None,
            ),
            effect.none(),
          )
        }
        _, _ -> #(model, effect.none())
      }

    MoveNorth -> step(model, world.North)
    MoveSouth -> step(model, world.South)
    MoveWest -> step(model, world.West)
    MoveEast -> step(model, world.East)

    ScheduleEvent(delay: delay) -> #(
      reschedule(model, delay, 1.0),
      effect.none(),
    )

    TriggerEvent(pick: pick, delay: delay) -> {
      let available =
        events.available_events(event_pool(model.location), model.state)
      case model.active_event, available {
        // An event is already on screen, or none qualify: just reschedule.
        Some(_), _ -> #(reschedule(model, delay, 1.0), effect.none())
        None, [] -> #(reschedule(model, delay, 0.5), effect.none())
        None, avail -> {
          let model = reschedule(model, delay, 1.0)
          case events.pick(avail, pick) {
            Error(_) -> #(model, effect.none())
            Ok(event) -> #(start_event(model, event), effect.none())
          }
        }
      }
    }

    ChooseEvent(id: id) -> #(model, roll_choice(id))

    ResolveEvent(id: id, roll: roll) -> #(
      resolve_event(model, id, roll),
      effect.none(),
    )

    MaybeFight(fight_roll: fight_roll, pick_roll: pick_roll) -> {
      let model = maybe_start_fight(model, fight_roll, pick_roll)
      // If a fight just began, set the enemy's attack ticking.
      #(model, enemy_timer(model.combat))
    }

    StrikeEnemy(weapon: weapon) ->
      case on_cooldown(model, "attack_" <> weapon) {
        // Still recovering from the last swing — ignore the click.
        True -> #(model, effect.none())
        False -> #(
          start_cooldown(model, "attack_" <> weapon, weapon_cooldown_ms(weapon)),
          roll_strike(weapon),
        )
      }

    ResolveStrike(weapon: weapon, roll: roll) ->
      resolve_strike(model, weapon, roll)

    EnemyTurn -> #(model, roll_enemy_turn())

    ResolveEnemyTurn(roll: roll) -> {
      let model = resolve_enemy_turn(model, roll)
      // The enemy keeps attacking on its delay until the fight ends.
      #(model, enemy_timer(model.combat))
    }

    CollectLoot(rolls: rolls) -> #(collect_loot(model, rolls), effect.none())

    Heal(item: item) -> #(heal_in_combat(model, item), effect.none())
  }
}

// --- world combat -----------------------------------------------------------

/// After a live step, check for an encounter and, if the dice favour it, pick
/// one for the current distance and terrain and begin the fight.
fn maybe_start_fight(model: Model, fight_roll: Float, pick_roll: Float) -> Model {
  case model.expedition, model.combat {
    Some(exp), None -> {
      let #(triggered, fight_move) =
        combat.check_fight(model.state, model.fight_move, fight_roll)
      let model = Model(..model, fight_move:)
      case triggered, world.tile_at(exp.map, exp.pos.0, exp.pos.1) {
        True, Ok(tile) -> {
          let options = encounters.available(world.distance(exp.pos), tile)
          case events.pick(options, pick_roll) {
            Ok(encounter) -> start_fight(model, exp, encounter)
            Error(_) -> model
          }
        }
        _, _ -> model
      }
    }
    _, _ -> model
  }
}

/// Begin a fight: the enemy at full health, the player at the expedition's.
fn start_fight(
  model: Model,
  exp: Expedition,
  encounter: encounters.Encounter,
) -> Model {
  let cs =
    combat.begin_combat(
      encounter.enemy,
      exp.vitals.health,
      world.max_health(model.state),
    )
  notify_world(Model(..model, combat: Some(cs)), [encounter.notification])
}

/// Resolve a player's swing. Winning the fight rolls the enemy's loot.
fn resolve_strike(
  model: Model,
  weapon_name: String,
  roll: Float,
) -> #(Model, Effect(Msg)) {
  case model.combat, combat.get_weapon(weapon_name) {
    Some(cs), Ok(weapon) -> {
      let cs = combat.player_strike(cs, weapon, model.state, roll)
      let model = Model(..model, combat: Some(cs))
      case cs.won {
        True -> #(model, roll_loot(cs.enemy))
        False -> #(model, effect.none())
      }
    }
    _, _ -> #(model, effect.none())
  }
}

/// Resolve the enemy's blow. Should it fell the player, the expedition ends.
fn resolve_enemy_turn(model: Model, roll: Float) -> Model {
  case model.combat {
    Some(cs) -> {
      let cs = combat.enemy_strike(cs, model.state, roll)
      case cs.player_hp <= 0 {
        True -> die(model)
        False -> Model(..model, combat: Some(cs))
      }
    }
    None -> model
  }
}

/// Take the defeated enemy's loot into the carried outfit, carry the wound back
/// to the expedition, and resume walking.
fn collect_loot(model: Model, rolls: List(Float)) -> Model {
  case model.combat, model.expedition {
    Some(cs), Some(exp) -> {
      let loot = combat.roll_loot(cs.enemy.loot, rolls)
      let state =
        list.fold(loot, model.state, fn(s, item) {
          state.set_outfit(s, item.0, state.get_outfit(s, item.0) + item.1)
        })
      let exp =
        world.Expedition(
          ..exp,
          vitals: world.Vitals(..exp.vitals, health: cs.player_hp),
        )
      let messages = [
        cs.enemy.death_message,
        ..list.map(loot, fn(l) { int.to_string(l.1) <> " " <> l.0 })
      ]
      notify_world(
        Model(..model, state:, expedition: Some(exp), combat: None),
        messages,
      )
    }
    _, _ -> Model(..model, combat: None)
  }
}

/// Use a healing item mid-fight: spend one from the outfit and mend the player,
/// once its cooldown is up. Cured meat is the gastronome-boosted `meat_heal`;
/// medicine and hypos mend a fixed amount.
fn heal_in_combat(model: Model, item: String) -> Model {
  let #(cd_id, cd_ms) = heal_cooldown(item)
  let have = state.get_outfit(model.state, item) > 0
  case model.combat {
    Some(cs) if have ->
      case on_cooldown(model, cd_id) {
        True -> model
        False -> {
          let amount = heal_amount(model.state, item)
          let healed = int.min(cs.player_max, cs.player_hp + amount)
          let model =
            Model(
              ..model,
              state: state.set_outfit(
                model.state,
                item,
                state.get_outfit(model.state, item) - 1,
              ),
              combat: Some(combat.CombatState(..cs, player_hp: healed)),
            )
          start_cooldown(model, cd_id, cd_ms)
        }
      }
    _ -> model
  }
}

/// How much a healing item mends.
fn heal_amount(s: State, item: String) -> Int {
  case item {
    "cured meat" -> world.meat_heal(s)
    "medicine" -> 20
    "hypo" -> 30
    _ -> 0
  }
}

/// The cooldown button id and duration (ms) for a healing item.
fn heal_cooldown(item: String) -> #(String, Int) {
  case item {
    "cured meat" -> #("eat", 5000)
    "medicine" -> #("meds", 7000)
    "hypo" -> #("hypo", 7000)
    _ -> #("heal", 5000)
  }
}

/// How long (ms) a weapon takes to recover between swings.
fn weapon_cooldown_ms(weapon: String) -> Int {
  case combat.get_weapon(weapon) {
    Ok(w) -> w.cooldown * 1000
    Error(_) -> 0
  }
}

/// An effect that rolls for an encounter (trigger + pick) after a step.
fn roll_fight() -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(MaybeFight(rng.random(), rng.random())) })
}

/// An effect that rolls the player's hit and reports it as `ResolveStrike`.
fn roll_strike(weapon: String) -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(ResolveStrike(weapon, rng.random())) })
}

/// An effect that rolls the enemy's hit and reports it as `ResolveEnemyTurn`.
fn roll_enemy_turn() -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(ResolveEnemyTurn(rng.random())) })
}

/// Schedule the enemy's next attack while a fight is on; nothing once it ends.
/// Re-armed after each enemy turn, so the timer naturally stops on win or death.
fn enemy_timer(combat: Option(combat.CombatState)) -> Effect(Msg) {
  case combat {
    Some(cs) -> delayed(cs.enemy.attack_delay * 1000, EnemyTurn)
    None -> effect.none()
  }
}

/// An effect that rolls a defeated enemy's loot (two samples per drop).
fn roll_loot(enemy: combat.Enemy) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let rolls =
      list.map(list.repeat(Nil, list.length(enemy.loot) * 2), fn(_) {
        rng.random()
      })
    dispatch(CollectLoot(rolls))
  })
}

/// Take one step in the world, then resolve where it leaves the player: safely
/// home at the village, dead in the wilds, or still out exploring.
fn step(model: Model, dir: world.Dir) -> #(Model, Effect(Msg)) {
  case model.combat, model.expedition {
    // No wandering off mid-fight.
    Some(_), _ -> #(model, effect.none())
    _, None -> #(model, effect.none())
    _, Some(exp) -> {
      let s = world.move(model.state, exp, dir)
      let model = notify_world(Model(..model, state: s.state), s.messages)
      let on_village =
        world.tile_at(s.expedition.map, s.expedition.pos.0, s.expedition.pos.1)
        == Ok(world.Village)
      case s.alive, on_village {
        _, True -> #(go_home(model), effect.none())
        False, _ -> #(die(model), effect.none())
        // Still out in the wilds — a fresh step may spring an encounter.
        True, False -> #(
          Model(..model, expedition: Some(s.expedition)),
          roll_fight(),
        )
      }
    }
  }
}

/// Make it home safe — the carried supplies and loot are unloaded, then the
/// expedition ends and the player returns to the room.
fn go_home(model: Model) -> Model {
  Model(
    ..notify_world(model, ["a haze falls over the village"]),
    state: return_outfit(model.state),
    location: Room,
    expedition: None,
    combat: None,
  )
}

/// Unload the outfit on returning home (`returnOutfit`): every carried item is
/// credited back to the stores; raw loot and resources are then unpacked, while
/// supplies, weapons, and craftables stay in the loadout for the next trip.
pub fn return_outfit(s: State) -> State {
  list.fold(state.outfit_list(s), s, fn(acc, item) {
    let acc = state.add_store(acc, item.0, item.1)
    case leave_at_home(item.0) {
      True -> state.set_outfit(acc, item.0, 0)
      False -> acc
    }
  })
}

/// Whether an item is unpacked on return (loot/resources) rather than kept in
/// the loadout (supplies, weapons, craftables) — the JS `leaveItAtHome`.
fn leave_at_home(item: String) -> Bool {
  let supply =
    list.contains(
      [
        "cured meat",
        "bullets",
        "energy cell",
        "charm",
        "medicine",
        "stim",
        "hypo",
      ],
      item,
    )
  let weapon = case combat.get_weapon(item) {
    Ok(_) -> True
    Error(_) -> False
  }
  let craftable = case craft.get(item) {
    Ok(_) -> True
    Error(_) -> False
  }
  !supply && !weapon && !craftable
}

/// Die in the wilds: the supplies are lost and the player wakes in the room.
fn die(model: Model) -> Model {
  let model = notify_world(model, ["the world fades"])
  Model(
    ..model,
    state: state.State(..model.state, outfit: dict.new()),
    location: Room,
    expedition: None,
    combat: None,
  )
}

/// An effect that rolls a map seed and dispatches `Embarked`.
fn roll_seed() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    dispatch(Embarked(float.round(rng.random() *. 1_000_000.0)))
  })
}

// --- random events ----------------------------------------------------------

/// The event pool that can fire at the current location: the global pool plus
/// the location's own. The World runs its own encounters, so it has none here.
fn event_pool(location: Location) -> List(events.Event) {
  let local = case location {
    Room -> events.room_events()
    Outside -> events.outside_events()
    _ -> []
  }
  list.append(events.global_events(), local)
}

/// The effect that drives event scheduling, run each second from `CoolCheck`:
/// schedule the first event, or fire a slot that has come due.
fn event_schedule_effect(model: Model) -> Effect(Msg) {
  case model.next_event_at {
    0 -> roll_schedule()
    deadline ->
      case model.now >= deadline {
        True -> roll_trigger()
        False -> effect.none()
      }
  }
}

/// Push the next-event deadline out by a fresh (scaled) delay.
fn reschedule(model: Model, delay: Float, scale: Float) -> Model {
  Model(
    ..model,
    next_event_at: model.now + events.next_event_delay_ms(delay, scale),
  )
}

/// Begin an event on its `start` scene, applying that scene's reward + notice.
fn start_event(model: Model, event: events.Event) -> Model {
  case list.key_find(event.scenes, "start") {
    Error(_) -> model
    Ok(scene) -> {
      let #(new_state, messages) = events.enter_scene(scene, model.state)
      notify_here(
        Model(
          ..model,
          state: new_state,
          active_event: Some(ActiveEvent(event, "start")),
        ),
        messages,
      )
    }
  }
}

/// Apply a chosen button's outcome to the running event.
fn resolve_event(model: Model, id: String, roll: Float) -> Model {
  case model.active_event {
    None -> model
    Some(ActiveEvent(event, scene_name)) ->
      case list.key_find(event.scenes, scene_name) {
        Error(_) -> model
        Ok(scene) ->
          case list.key_find(scene.buttons, id) {
            Error(_) -> model
            Ok(button) ->
              case events.click_button(button, model.state, roll) {
                // Too expensive: a no-op, like the JS.
                Error(_) -> model
                Ok(#(new_state, messages, step)) ->
                  advance_event(
                    notify_here(Model(..model, state: new_state), messages),
                    event,
                    step,
                  )
              }
          }
      }
  }
}

/// Move the running event along after a button outcome.
fn advance_event(model: Model, event: events.Event, step: events.Step) -> Model {
  case step {
    events.StayOnScene -> model
    events.EndEvent -> Model(..model, active_event: None)
    events.LoadScene(next) ->
      case list.key_find(event.scenes, next) {
        Error(_) -> Model(..model, active_event: None)
        Ok(scene) -> {
          let #(new_state, messages) = events.enter_scene(scene, model.state)
          notify_here(
            Model(
              ..model,
              state: new_state,
              active_event: Some(ActiveEvent(event, next)),
            ),
            messages,
          )
        }
      }
  }
}

/// Emit messages to the current location's notification stream.
fn notify_here(model: Model, messages: List(String)) -> Model {
  notify_at(model, location_key(model.location), messages)
}

/// Roll to pick an event + a reschedule delay, reported as `TriggerEvent`.
fn roll_trigger() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    dispatch(TriggerEvent(rng.random(), rng.random()))
  })
}

/// Roll a delay, reported as `ScheduleEvent`.
fn roll_schedule() -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(ScheduleEvent(rng.random())) })
}

/// Roll for a button choice (resolves any `Branch`), reported as `ResolveEvent`.
fn roll_choice(id: String) -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(ResolveEvent(id, rng.random())) })
}

/// Emit messages to the World's notification stream.
fn notify_world(model: Model, messages: List(String)) -> Model {
  notify_at(model, "world", messages)
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
