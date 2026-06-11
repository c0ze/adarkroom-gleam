//// The MVU model: the persistent `State` plus runtime UI state (the active
//// location, the notification log, and a loop tick counter), and the messages
//// that drive updates. `update` returns the new model together with any
//// effects (e.g. one-shot timers for the builder's timed progression).

import adarkroom/audio
import adarkroom/browser
import adarkroom/clock
import adarkroom/combat
import adarkroom/craft
import adarkroom/encounters
import adarkroom/events
import adarkroom/executioner
import adarkroom/fabricator
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/path
import adarkroom/rng
import adarkroom/room
import adarkroom/save
import adarkroom/scoring
import adarkroom/setpieces
import adarkroom/ship
import adarkroom/space
import adarkroom/state.{type State}
import adarkroom/timer
import adarkroom/trade
import adarkroom/world.{type Expedition}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
  /// Arrive in the world on a freshly-seeded map (`cache`: whether prestige
  /// data exists, placing the destroyed village).
  Embarked(seed: Int, cache: Bool)
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
  /// Raise the kinetic shield: the next blow heals instead, then it breaks.
  UseShield
  /// Jam a stim: attack cooldowns halve, at a price in health that can kill.
  UseStim
  /// Grant a setpiece scene's loot from the supplied rolls (two per drop).
  SetpieceLoot(rolls: List(Float))
  /// Run a scene's random `onLoad` (a disaster's toll) with the supplied roll.
  SceneRng(roll: Float)
  /// Timer: a boss special comes due (by index in the fight's specials).
  SpecialFire(index: Int)
  /// Apply a rotation special's pick (the roll chooses among the options).
  ResolveSpecial(index: Int, roll: Float)
  /// Timer: a timed enemy status (enrage, meditation) runs out.
  StatusExpire
  /// Timer: armed poison drips on the player.
  DotTick
  /// Apply scavenged surface maps (one reveal roll per map).
  MapsScavenged(rolls: List(Float))
  /// Timer: the felled enemy detonates — take the blast, then the win or the
  /// grave.
  ExplosionResolve
  /// Plate the starship's hull with an alien alloy.
  ReinforceHull
  /// Tune the starship's engine with an alien alloy.
  UpgradeEngine
  /// Press the lift-off button: the warning first, then up and away.
  CheckLiftoff
  /// Fabricate the named recipe at the whirring fabricator.
  Fabricate(name: String)
  /// Timer: one 33ms flight frame of the ascent (time-stamped). Every ascent
  /// timer carries its run, so a crashed flight's stragglers can't touch a
  /// later one.
  FlightFrame(run: Int, at: Int)
  /// Timer: a second of climb.
  ClimbTick(run: Int)
  /// Timer: the next asteroid wave is due; rolls then spawns.
  WaveTick(run: Int)
  /// Spawn an asteroid wave from its rolls (three per rock), time-stamped.
  SpawnWave(run: Int, at: Int, rolls: List(Float))
  /// Timer: the fade completes — the ascent is survived.
  AscentComplete(run: Int)
  /// A key went down / came up (the ascent's controls).
  KeyDown(key: String)
  KeyUp(key: String)
  /// The ascent is survived: save the score and prestige (the rolls reduce
  /// the carried stores) and begin the ending.
  GameWon(rolls: List(Float))
  /// Timer: the next outro paragraph fades in.
  OutroStep
  /// The outro's wait button: on to the scores.
  EndingWait
  /// Take one of a pending loot row (capacity allowing).
  TakeLoot(name: String)
  /// Take as much of a row as the pack fits.
  TakeAllLoot(name: String)
  /// Take all you can of every row — and leave, if everything fit.
  TakeEverything
  /// Drop `count` of a carried item to make room, then take what wanted it.
  DropCarried(name: String, count: Int)
  /// Close the drop menu untouched.
  CancelDrop
  /// Done looting an encounter: the fight closes and the walk resumes.
  LootDone
  /// Start again — the save is wiped (prestige stays) and the page reloads.
  RestartGame
  /// The ending's app-store links.
  OpenStore(url: String)
  /// Timer: flash the page title "*** EVENT ***" (every 3s while blinking).
  BlinkOn
  /// Timer: restore the page title (1.5s after each flash).
  BlinkOff
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
    /// The ascent in progress, while the ship climbs. Runtime-only.
    space: Option(space.Flight),
    /// The previous flight frame's clock, for dt-scaling. Runtime-only.
    flight_last_move: Int,
    /// Which ascent this is — stale timers from earlier runs are ignored.
    flight_run: Int,
    /// The ending, once the ascent is survived. Runtime-only — the game is
    /// over.
    ending: Option(Ending),
    /// Loot waiting to be taken (a won fight's drops, a scene's cache), as
    /// `(name, count)` rows. Runtime-only; advancing forfeits what's left.
    loot: List(#(String, Int)),
    /// The loot row whose take didn't fit, showing its drop menu. Runtime-only.
    drop_for: Option(String),
    /// Whether the page title is blinking for an event (`blinkTitle`).
    /// Runtime-only.
    blinking: Bool,
    /// The background track currently looping, so location and fire changes
    /// only restart the music when it actually changes. Runtime-only.
    playing: String,
    /// Whether the document key listeners are armed (once per session).
    keys_armed: Bool,
  )
}

/// A random event in progress: the event and the scene currently showing.
pub type ActiveEvent {
  ActiveEvent(event: events.Event, scene: String)
}

/// The end of the game, after the fade is survived (`endGame`): the beacon's
/// outro paragraphs, then the scores and the ways onward.
pub type Ending {
  Outro(paragraphs: Int, this_score: Int, total_score: Int)
  EndOptions(this_score: Int, total_score: Int)
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
    space: None,
    flight_last_move: 0,
    flight_run: 0,
    ending: None,
    loot: [],
    drop_for: None,
    blinking: False,
    playing: "",
    keys_armed: False,
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
        // First sight of the old wreck.
        Ship -> apply_at(navigated, "ship", ship.see_ship(navigated.state))
        // The hum of real tools.
        Fabricator ->
          apply_at(
            navigated,
            "fabricator",
            fabricator.see_fabricator(navigated.state),
          )
        _ -> navigated
      }
      // Arrival picks up the location's music.
      let #(arrived, music) = tune_music(arrived)
      // Lift-off proper: the ascent begins with its clocks and controls.
      case location {
        Space -> {
          let run = arrived.flight_run + 1
          let flying =
            Model(
              ..arrived,
              space: Some(space.begin(arrived.state)),
              flight_last_move: 0,
              flight_run: run,
            )
          let #(flying, keys) = arm_keys(flying)
          #(
            flying,
            effect.batch([
              music,
              keys,
              sound(audio.lift_off),
              flight_frame_timer(run),
              delayed(1000, ClimbTick(run)),
              delayed(space.wave_delay_ms(0), WaveTick(run)),
              delayed(space.ascent_ms, AscentComplete(run)),
            ]),
          )
        }
        _ -> #(arrived, music)
      }
    }

    LightFire -> {
      let lit = room.can_light(model.state)
      let #(model, fx) =
        room_music_after(fire_action(model, room.light_fire(model.state)))
      #(model, effect.batch([fx, sound_if(lit, audio.light_fire)]))
    }
    StokeFire -> {
      let stoked = room.can_stoke(model.state)
      let #(model, fx) =
        room_music_after(fire_action(model, room.stoke_fire(model.state)))
      #(model, effect.batch([fx, sound_if(stoked, audio.stoke_fire)]))
    }

    CoolCheck(at: now) -> {
      let cooled =
        apply_room(Model(..model, now:), room.tick_cool(model.state, now))
      // Pending delayed returns (the wanderers' carts) count down on the same
      // heartbeat, announcing in the room when they arrive.
      let delivered = apply_room(cooled, events.tick_delays(cooled.state))
      // The swollen-stores check that summons thieves rides it too (the
      // original runs it on every stores redraw).
      let checked =
        Model(..delivered, state: outside.maybe_start_thieves(delivered.state))
      // A fire that cooled retunes the room (`setMusic`, only while in it).
      let #(checked, music) =
        room_music_after(#(checked, event_schedule_effect(checked)))
      #(checked, music)
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
      // Hammering for a structure, the workbench for an item — when one was
      // actually made.
      let snd = case craft.get(name) {
        Ok(c) ->
          case
            craft.count(built.state, c, name)
            > craft.count(model.state, c, name)
          {
            True ->
              case c.kind {
                craft.Building -> sound(audio.build)
                _ -> sound(audio.craft)
              }
            False -> effect.none()
          }
        Error(_) -> effect.none()
      }
      #(built, effect.batch([eff, snd]))
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
      // The clink of a sale that went through.
      let got =
        state.get_store(unlocked.state, name)
        > state.get_store(model.state, name)
      #(unlocked, sound_if(got, audio.buy))
    }

    GatherWood ->
      case on_cooldown(model, "gather") {
        True -> #(model, effect.none())
        False -> {
          let gathered = apply_outside(model, outside.gather_wood(model.state))
          #(
            start_cooldown(gathered, "gather", outside.gather_cooldown_ms),
            sound(audio.gather_wood),
          )
        }
      }

    CheckTraps ->
      case on_cooldown(model, "traps") {
        True -> #(model, effect.none())
        False -> #(
          start_cooldown(model, "traps", outside.traps_cooldown_ms),
          effect.batch([
            roll_traps(outside.num_drops(model.state)),
            sound(audio.check_traps),
          ]),
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

    Embarked(seed: seed, cache: cache) ->
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
          let map = case cache {
            True -> world.generate_prestige_map(rng.seed(seed))
            False -> world.generate_map(rng.seed(seed))
          }
          let exp = world.begin(map, stocked)
          #(
            Model(
              ..model,
              state: stocked,
              location: World,
              expedition: Some(exp),
              fight_move: 0,
              combat: None,
            ),
            sound(audio.embark),
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
            Ok(event) -> start_event(model, event)
          }
        }
      }
    }

    ChooseEvent(id: id) -> #(model, roll_choice(id))

    ResolveEvent(id: id, roll: roll) -> resolve_event(model, id, roll)

    MaybeFight(fight_roll: fight_roll, pick_roll: pick_roll) -> {
      let was_quiet = model.combat == None
      let model = maybe_start_fight(model, fight_roll, pick_roll)
      // If a fight just began, set the enemy's attack ticking — to its
      // depth's battle music.
      let music = case was_quiet, model.combat, model.expedition {
        True, Some(_), Some(exp) -> encounter_music(world.distance(exp.pos))
        _, _, _ -> effect.none()
      }
      #(model, effect.batch([enemy_timer(model.combat), music]))
    }

    StrikeEnemy(weapon: weapon) ->
      case on_cooldown(model, "attack_" <> weapon) {
        // Still recovering from the last swing — ignore the click.
        True -> #(model, effect.none())
        False -> #(
          start_cooldown(
            model,
            "attack_" <> weapon,
            strike_cooldown_ms(model, weapon),
          ),
          roll_strike(weapon),
        )
      }

    ResolveStrike(weapon: weapon, roll: roll) -> {
      let #(struck, fx) = resolve_strike(model, weapon, roll)
      let snd = case model.combat, combat.get_weapon(weapon) {
        Some(cs), Ok(w) if !cs.won -> weapon_noise(w.kind)
        _, _ -> effect.none()
      }
      #(struck, effect.batch([fx, snd]))
    }

    EnemyTurn -> #(model, roll_enemy_turn())

    ResolveEnemyTurn(roll: roll) -> {
      let dot_before = current_dot(model)
      let had_fight = model.combat != None
      // A blow that actually lands makes its noise — misses, stuns and
      // trances stay silent (the sound lives in the JS hit branch).
      let strike_snd = case model.combat {
        Some(cs) if !cs.won ->
          case combat.enemy_blow_lands(cs, model.state, roll) {
            True ->
              weapon_noise(case cs.enemy.ranged {
                True -> combat.Ranged
                False -> combat.Melee
              })
            False -> effect.none()
          }
        _ -> effect.none()
      }
      let model = resolve_enemy_turn(model, roll)
      // A killing blow fades whatever battle or event music was up.
      let death_fx = case had_fight && model.combat == None {
        True -> die_fx(model)
        False -> effect.none()
      }
      // A venomous blow that just landed arms the poison drip (one chain; a
      // later blow only changes its strength).
      let dot_armed = case dot_before == 0 && current_dot(model) > 0 {
        True -> delayed(combat.dot_tick_ms, DotTick)
        False -> effect.none()
      }
      // The enemy keeps attacking on its delay until the fight ends.
      #(
        model,
        effect.batch([
          enemy_timer(model.combat),
          dot_armed,
          death_fx,
          strike_snd,
        ]),
      )
    }

    CollectLoot(rolls: rolls) -> #(collect_loot(model, rolls), effect.none())

    UseShield ->
      case
        model.combat,
        on_cooldown(model, "shld")
        || state.get_store(model.state, "kinetic armour") <= 0
      {
        Some(cs), False if !cs.won -> #(
          start_cooldown(
            Model(..model, combat: Some(combat.raise_shield(cs))),
            "shld",
            combat.shield_cooldown_ms,
          ),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
      }

    UseStim ->
      case
        model.combat,
        on_cooldown(model, "use-stim")
        || state.get_outfit(model.state, "stim") <= 0
      {
        Some(cs), False if !cs.won -> {
          let stimmed = combat.use_stim(cs)
          let model =
            start_cooldown(
              Model(..model, combat: Some(stimmed)),
              "use-stim",
              combat.stim_cooldown_ms,
            )
          // The tithe can be the last of the wanderer's health.
          case stimmed.player_hp <= 0 {
            True -> {
              let dead = die(model)
              #(dead, die_fx(dead))
            }
            False -> #(model, effect.none())
          }
        }
        _, _ -> #(model, effect.none())
      }

    Heal(item: item) -> {
      let snd = case item {
        "cured meat" -> sound(audio.eat_meat)
        // The hypo borrows the meds' sound, as in the original.
        "medicine" | "hypo" -> sound(audio.use_meds)
        _ -> effect.none()
      }
      #(heal_in_combat(model, item), snd)
    }

    SetpieceLoot(rolls: rolls) -> #(
      grant_setpiece_loot(model, rolls),
      effect.none(),
    )

    SceneRng(roll: roll) -> #(run_scene_rng(model, roll), effect.none())

    SpecialFire(index: index) -> fire_special(model, index)

    ResolveSpecial(index: index, roll: roll) ->
      resolve_special(model, index, roll)

    StatusExpire -> #(set_enemy_status(model, combat.NoStatus), effect.none())

    DotTick -> dot_tick(model)

    MapsScavenged(rolls: rolls) -> #(scavenge_maps(model, rolls), effect.none())

    ExplosionResolve -> resolve_explosion(model)

    ReinforceHull -> {
      let applied = apply_at(model, "ship", ship.reinforce_hull(model.state))
      let paid =
        state.get_store(applied.state, "alien alloy")
        < state.get_store(model.state, "alien alloy")
      #(applied, sound_if(paid, audio.reinforce_hull))
    }

    UpgradeEngine -> {
      let applied = apply_at(model, "ship", ship.upgrade_engine(model.state))
      let paid =
        state.get_store(applied.state, "alien alloy")
        < state.get_store(model.state, "alien alloy")
      #(applied, sound_if(paid, audio.upgrade_engine))
    }

    CheckLiftoff -> {
      // The button arms its cooldown either way; lingering refunds it.
      let model = start_cooldown(model, "liftoff", ship.liftoff_cooldown_ms)
      case ship.seen_warning(model.state) {
        False -> start_event(model, ship.ready_to_leave())
        True -> update(model, Navigate(to: Space))
      }
    }

    Fabricate(name: name) -> {
      let applied =
        apply_at(model, "fabricator", fabricator.fabricate(model.state, name))
      let paid =
        state.get_store(applied.state, "alien alloy")
        < state.get_store(model.state, "alien alloy")
      #(applied, sound_if(paid, audio.craft))
    }

    FlightFrame(run: run, at: now) ->
      case run == model.flight_run {
        True -> flight_frame(model, now)
        False -> #(model, effect.none())
      }

    ClimbTick(run: run) ->
      case current_flight(model, run) {
        // The altitude clock stops past 60km; the win is the fade completing.
        Ok(flight) ->
          case flight.altitude > 60 {
            True -> #(model, effect.none())
            False -> {
              let climbed = space.climb(flight)
              // The music thins with the air (`lowerVolume`).
              let volume = 1.0 -. int.to_float(climbed.altitude) /. 60.0
              #(
                Model(..model, space: Some(climbed)),
                effect.batch([
                  delayed(1000, ClimbTick(run)),
                  effect.from(fn(_) { audio.set_background_volume(volume, 0.3) }),
                ]),
              )
            }
          }
        Error(_) -> #(model, effect.none())
      }

    WaveTick(run: run) ->
      case current_flight(model, run) {
        Ok(flight) -> #(
          model,
          effect.from(fn(dispatch) {
            let rolls =
              list.map(
                list.repeat(Nil, space.wave_size(flight.altitude) * 3),
                fn(_) { rng.random() },
              )
            let _ =
              timer.set_timeout(
                fn() {
                  dispatch(SpawnWave(run, float.round(clock.now()), rolls))
                },
                0,
              )
            Nil
          }),
        )
        Error(_) -> #(model, effect.none())
      }

    SpawnWave(run: run, at: now, rolls: rolls) ->
      case current_flight(model, run) {
        Ok(flight) -> #(
          Model(..model, space: Some(space.spawn(flight, now, rolls))),
          delayed(space.wave_delay_ms(flight.altitude), WaveTick(run)),
        )
        Error(_) -> #(model, effect.none())
      }

    AscentComplete(run: run) ->
      case current_flight(model, run) {
        // Survived the fade: the ascent is won. The flight goes quiet and the
        // prestige reduction rolls its dice.
        Ok(flight) -> #(
          Model(..model, space: Some(space.Flight(..flight, done: True))),
          effect.from(fn(dispatch) {
            let rolls =
              list.map(list.repeat(Nil, scoring.rolls_needed()), fn(_) {
                rng.random()
              })
            dispatch(GameWon(rolls))
          }),
        )
        Error(_) -> #(model, effect.none())
      }

    KeyDown(key: key) -> #(hold_key(model, key, True), effect.none())

    KeyUp(key: key) -> #(hold_key(model, key, False), effect.none())

    GameWon(rolls: rolls) -> game_won(model, rolls)

    OutroStep ->
      case model.ending {
        Some(Outro(paragraphs: n, this_score: this, total_score: total)) -> {
          let shown = n + 1
          let next = case shown < 5 {
            True -> delayed(outro_gap_ms(shown + 1), OutroStep)
            False -> effect.none()
          }
          #(Model(..model, ending: Some(Outro(shown, this, total))), next)
        }
        _ -> #(model, effect.none())
      }

    EndingWait ->
      case model.ending {
        Some(Outro(paragraphs: _, this_score: this, total_score: total)) -> #(
          Model(..model, ending: Some(EndOptions(this, total))),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    TakeLoot(name: name) -> #(take_loot(model, name), effect.none())

    TakeAllLoot(name: name) -> #(take_all_loot(model, name), effect.none())

    TakeEverything -> take_everything(model)

    DropCarried(name: name, count: count) -> #(
      drop_carried(model, name, count),
      effect.none(),
    )

    CancelDrop -> #(Model(..model, drop_for: None), effect.none())

    LootDone -> #(
      finish_looting(model),
      // The encounter is over; its battle music fades (`endEvent`).
      effect.from(fn(_) { audio.stop_event_music() }),
    )

    RestartGame -> #(
      model,
      effect.from(fn(_) {
        save.wipe()
        browser.reload()
      }),
    )

    OpenStore(url: url) -> #(model, open_link(url))

    BlinkOn ->
      case model.blinking {
        // Flash now; queue the restore and the next flash.
        True -> #(
          model,
          effect.batch([
            effect.from(fn(_) { browser.set_title("*** EVENT ***") }),
            delayed(1500, BlinkOff),
            delayed(3000, BlinkOn),
          ]),
        )
        False -> #(model, effect.none())
      }

    BlinkOff -> #(model, restore_title(model))
  }
}

// --- the ending ----------------------------------------------------------------

/// The game is won (`endGame`): the score and the reduced stores are written
/// to the prestige slot, and the ending begins — the beacon's outro when one
/// is aboard, the scores straight away otherwise.
fn game_won(model: Model, rolls: List(Float)) -> #(Model, Effect(Msg)) {
  let this_score = scoring.calculate_score(model.state)
  let total = scoring.total_score() + this_score
  let persist =
    effect.from(fn(_) {
      scoring.save(model.state, rolls)
      // The ending has its own theme, at full volume again.
      audio.set_background_volume(1.0, 1.0)
      audio.play_background_music(audio.music_ending)
    })
  case state.get_store(model.state, "fleet beacon") > 0 {
    True -> #(
      Model(..model, ending: Some(Outro(0, this_score, total))),
      effect.batch([persist, delayed(outro_gap_ms(1), OutroStep)]),
    )
    False -> #(
      Model(..model, ending: Some(EndOptions(this_score, total))),
      persist,
    )
  }
}

/// The outro's timing (`showExpansionEnding`): paragraphs at 2s, 7s, 14s and
/// 17s, the wait button at 19.5s.
fn outro_gap_ms(step: Int) -> Int {
  case step {
    1 -> 2000
    2 -> 5000
    3 -> 7000
    4 -> 3000
    _ -> 2500
  }
}

// --- the ascent ---------------------------------------------------------------

/// One 33ms flight frame: the ship moves by the real time elapsed, the rocks
/// fall and burst, and a spent hull ends the flight (`crash`) — back to the
/// ship with the lift-off button cooling.
fn flight_frame(model: Model, now: Int) -> #(Model, Effect(Msg)) {
  case model.space {
    Some(flight) if !flight.done -> {
      let dt = case model.flight_last_move {
        0 -> space.frame_ms
        last -> now - last
      }
      let flown =
        flight
        |> space.move(model.state, dt)
        |> space.collide(now)
      // Each rock that connected rings its altitude's clang.
      let clangs =
        effect.batch(list.repeat(
          asteroid_noise(flown.altitude),
          flight.hull - flown.hull,
        ))
      case flown.hull <= 0 {
        True -> {
          let crashed =
            Model(..model, space: None, flight_last_move: 0)
            |> start_cooldown("liftoff", ship.liftoff_cooldown_ms)
          let #(landed, fx) = update(crashed, Navigate(to: Ship))
          #(landed, effect.batch([fx, clangs, sound(audio.crash)]))
        }
        False -> #(
          Model(..model, space: Some(flown), flight_last_move: now),
          effect.batch([flight_frame_timer(model.flight_run), clangs]),
        )
      }
    }
    _ -> #(model, effect.none())
  }
}

/// The next 33ms frame, time-stamped from the wall clock.
fn flight_frame_timer(run: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ =
      timer.set_timeout(
        fn() { dispatch(FlightFrame(run, float.round(clock.now()))) },
        space.frame_ms,
      )
    Nil
  })
}

/// This run's live, still-flying flight — stale-run timers get nothing.
fn current_flight(model: Model, run: Int) -> Result(space.Flight, Nil) {
  case model.space {
    Some(flight) ->
      case run == model.flight_run && !flight.done {
        True -> Ok(flight)
        False -> Error(Nil)
      }
    None -> Error(Nil)
  }
}

/// Press or release an ascent control (`keyDown`/`keyUp`: arrows or WASD).
fn hold_key(model: Model, key: String, held: Bool) -> Model {
  case model.space, dir_for_key(key) {
    Some(flight), Ok(dir) ->
      Model(..model, space: Some(space.set_dir(flight, dir, held)))
    _, _ -> model
  }
}

fn dir_for_key(key: String) -> Result(space.Dir, Nil) {
  case key {
    "ArrowUp" | "w" | "W" -> Ok(space.Up)
    "ArrowDown" | "s" | "S" -> Ok(space.Down)
    "ArrowLeft" | "a" | "A" -> Ok(space.Left)
    "ArrowRight" | "d" | "D" -> Ok(space.Right)
    _ -> Error(Nil)
  }
}

/// Arm the document key listeners, once.
fn arm_keys(model: Model) -> #(Model, Effect(Msg)) {
  case model.keys_armed {
    True -> #(model, effect.none())
    False -> #(
      Model(..model, keys_armed: True),
      effect.from(fn(dispatch) {
        browser.on_keys(fn(key) { dispatch(KeyDown(key)) }, fn(key) {
          dispatch(KeyUp(key))
        })
      }),
    )
  }
}

// --- world combat -----------------------------------------------------------

/// The encounter's battle music by depth (`Events.triggerFight`):
/// tier 3 past 20, tier 2 past 10, tier 1 nearer home.
/// A one-shot action sound.
fn sound(src: String) -> Effect(Msg) {
  effect.from(fn(_) { audio.play_sound(src) })
}

/// The sound of an action that may have been refused.
fn sound_if(play: Bool, src: String) -> Effect(Msg) {
  case play {
    True -> sound(src)
    False -> effect.none()
  }
}

/// A random footstep. The original rolls `floor(random * 5) + 1`, so the
/// sixth recording exists on disk but never plays.
fn footstep() -> Effect(Msg) {
  effect.from(fn(_) {
    audio.play_sound(audio.footsteps(float.truncate(rng.random() *. 5.0) + 1))
  })
}

/// A swing's noise: one of two variations for the weapon's type.
fn weapon_noise(kind: combat.WeaponType) -> Effect(Msg) {
  effect.from(fn(_) {
    let variant = float.truncate(rng.random() *. 2.0) + 1
    let kind = case kind {
      combat.Unarmed -> "unarmed"
      combat.Melee -> "melee"
      combat.Ranged -> "ranged"
    }
    audio.play_sound(audio.weapon_sound(kind, variant))
  })
}

/// An asteroid strike's clang, pitched by the altitude band.
fn asteroid_noise(altitude: Int) -> Effect(Msg) {
  effect.from(fn(_) {
    let roll = float.truncate(rng.random() *. 2.0)
    let base = case altitude {
      a if a > 40 -> 6
      a if a > 20 -> 4
      _ -> 1
    }
    audio.play_sound(audio.asteroid_hit(roll + base))
  })
}

fn encounter_music(distance: Int) -> Effect(Msg) {
  let track = case distance {
    d if d > 20 -> audio.encounter_tier_3
    d if d > 10 -> audio.encounter_tier_2
    _ -> audio.encounter_tier_1
  }
  effect.from(fn(_) { audio.play_event_music(track) })
}

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
    Some(before), Ok(weapon) -> {
      let cs = combat.player_strike(before, weapon, model.state, roll)
      let model = Model(..model, combat: Some(cs))
      // An atHealth trigger may have taken hold mid-blow; timed statuses
      // (enrage, meditation) need their expiry clock started.
      let expiry = case cs.enemy_status != before.enemy_status {
        True -> status_expiry(cs.enemy_status)
        False -> effect.none()
      }
      case cs.won, cs.exploding {
        // The kill pauses while the dying enemy detonates (`Events.explode`);
        // the loot waits on surviving the blast.
        True, Some(_) -> #(
          model,
          effect.batch([
            delayed(combat.explosion_duration_ms, ExplosionResolve),
            expiry,
          ]),
        )
        True, None -> #(model, effect.batch([roll_loot(cs.enemy), expiry]))
        False, _ -> #(model, expiry)
      }
    }
    _, _ -> #(model, effect.none())
  }
}

/// The felled enemy detonates (`Events.explode`): the blast lands on the
/// player as one wound; survive it and the win — and the loot — proceed.
fn resolve_explosion(model: Model) -> #(Model, Effect(Msg)) {
  case model.combat {
    Some(cs) ->
      case cs.won, cs.exploding {
        True, Some(blast) -> {
          let hp = int.max(0, cs.player_hp - blast)
          case hp <= 0 {
            True -> {
              let dead = die(model)
              #(dead, die_fx(dead))
            }
            False -> #(
              Model(
                ..model,
                combat: Some(combat.CombatState(..cs, player_hp: hp)),
              ),
              roll_loot(cs.enemy),
            )
          }
        }
        _, _ -> #(model, effect.none())
      }
    None -> #(model, effect.none())
  }
}

/// The poison currently dripping on the player, if a fight is on.
fn current_dot(model: Model) -> Int {
  case model.combat {
    Some(cs) -> cs.player_dot
    None -> 0
  }
}

/// Resolve the enemy's blow. Should it fell the player, the expedition ends.
/// A felled enemy throws none (the explosion window keeps the fight on screen
/// after the win; the JS clears its timers there).
fn resolve_enemy_turn(model: Model, roll: Float) -> Model {
  case model.combat {
    Some(cs) ->
      case cs.won {
        True -> model
        False -> {
          let cs = combat.enemy_strike(cs, model.state, roll)
          case cs.player_hp <= 0 {
            True -> die(model)
            False -> Model(..model, combat: Some(cs))
          }
        }
      }
    None -> model
  }
}

/// Take the defeated enemy's loot into the carried outfit, carry the wound back
/// to the expedition, and resume walking.
fn collect_loot(model: Model, rolls: List(Float)) -> Model {
  case model.combat {
    // The fight stays on screen as a looting phase (`winFight`): the drops
    // wait in rows, and only the death message is announced.
    Some(cs) -> {
      let loot =
        combat.roll_loot(cs.enemy.loot, rolls)
        |> list.filter(fn(l) { l.1 > 0 })
      let messages = [cs.enemy.death_message] |> list.filter(fn(m) { m != "" })
      // The leave and take-everything buttons start their second of cooling
      // as the screen appears (`Button.cooldown` on creation).
      let model =
        model
        |> start_cooldown("loot_leave", leave_cooldown_ms)
        |> start_cooldown("loot_take_et", leave_cooldown_ms)
      notify_world(Model(..model, loot: loot, drop_for: None), messages)
    }
    None -> model
  }
}

/// Done looting a won fight: the wound carries back to the expedition, the
/// leftovers are forfeited, and the walk resumes.
fn finish_looting(model: Model) -> Model {
  let model = Model(..model, loot: [], drop_for: None)
  case model.combat, model.expedition {
    Some(cs), Some(exp) ->
      Model(
        ..model,
        combat: None,
        expedition: Some(
          world.Expedition(
            ..exp,
            vitals: world.Vitals(..exp.vitals, health: cs.player_hp),
          ),
        ),
      )
    _, _ -> Model(..model, combat: None)
  }
}

/// Take one of a row (`getLoot`): into the pack if it fits, else the row's
/// drop menu opens.
fn take_loot(model: Model, name: String) -> Model {
  case path.weight(name) <=. path.free_space(model.state) {
    True -> {
      let model =
        Model(
          ..model,
          state: state.set_outfit(
            model.state,
            name,
            state.get_outfit(model.state, name) + 1,
          ),
          drop_for: None,
        )
      shrink_row(model, name, 1)
    }
    False -> Model(..model, drop_for: Some(name))
  }
}

/// Take as much of a row as fits (`takeAll`): `min(floor(free / weight), n)`.
fn take_all_loot(model: Model, name: String) -> Model {
  case list.key_find(model.loot, name) {
    Error(_) -> model
    Ok(left) -> {
      let fits = fits_of(model.state, name)
      let num = int.min(fits, left)
      case num > 0 {
        False -> model
        True -> {
          let model =
            Model(
              ..model,
              state: state.set_outfit(
                model.state,
                name,
                state.get_outfit(model.state, name) + num,
              ),
            )
          shrink_row(model, name, num)
        }
      }
    }
  }
}

/// How many of an item the pack can still fit.
fn fits_of(s: State, name: String) -> Int {
  case path.weight(name) >. 0.0 {
    True -> float.truncate(path.free_space(s) /. path.weight(name))
    False -> 1_000_000
  }
}

/// Take all you can of every row (`takeEverything`); when everything fit and
/// it's a plain encounter, that's also the leave.
fn take_everything(model: Model) -> #(Model, Effect(Msg)) {
  let everything_fits = loot_fits_entirely(model)
  let taken =
    list.fold(model.loot, model, fn(m, row) { take_all_loot(m, row.0) })
  let taken = start_cooldown(taken, "loot_take_et", leave_cooldown_ms)
  case everything_fits && taken.active_event == None && taken.combat != None {
    True -> #(finish_looting(taken), effect.none())
    False -> #(taken, effect.none())
  }
}

/// Whether every pending row would fit in the pack at once (`setTakeAll`'s
/// running tally) — the difference between "take everything" and "take all
/// you can".
pub fn loot_fits_entirely(model: Model) -> Bool {
  let needed =
    list.fold(model.loot, 0.0, fn(acc, row) {
      acc +. int.to_float(row.1) *. path.weight(row.0)
    })
  needed <=. path.free_space(model.state)
}

/// Drop `count` of a carried item to make room (`dropStuff`): the dropped
/// join the loot rows — they can be taken back — and the wanted item is
/// taken in the same motion.
fn drop_carried(model: Model, name: String, count: Int) -> Model {
  let had = state.get_outfit(model.state, name)
  let count = int.min(count, had)
  let model =
    Model(
      ..model,
      state: state.set_outfit(model.state, name, had - count),
      loot: grow_row(model.loot, name, count),
    )
  case model.drop_for {
    Some(wanted) -> take_loot(Model(..model, drop_for: None), wanted)
    None -> model
  }
}

/// Take `n` off a row, removing it when spent.
fn shrink_row(model: Model, name: String, n: Int) -> Model {
  let loot =
    list.filter_map(model.loot, fn(row) {
      case row.0 == name, row.1 - n {
        True, left if left <= 0 -> Error(Nil)
        True, left -> Ok(#(name, left))
        False, _ -> Ok(row)
      }
    })
  Model(..model, loot: loot)
}

/// Add `n` to a row, creating it at the end if absent.
fn grow_row(
  loot: List(#(String, Int)),
  name: String,
  n: Int,
) -> List(#(String, Int)) {
  case list.key_find(loot, name) {
    Ok(have) ->
      list.map(loot, fn(row) {
        case row.0 == name {
          True -> #(name, have + n)
          False -> row
        }
      })
    Error(_) -> list.append(loot, [#(name, n)])
  }
}

/// `Events._LEAVE_COOLDOWN` — the second the leave/take-everything buttons
/// spend cooling.
pub const leave_cooldown_ms = 1000

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

/// A swing's cooldown right now: halved while the stim's boost holds
/// (`Button.cooldown`'s `boosted` check). The view's bars read it too.
pub fn strike_cooldown_ms(model: Model, weapon: String) -> Int {
  let ms = weapon_cooldown_ms(weapon)
  case model.combat {
    Some(cs) if cs.player_status == combat.Boost -> ms / 2
    _ -> ms
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
    // A felled enemy's timer stays down (the explosion window).
    Some(cs) ->
      case cs.won {
        True -> effect.none()
        False ->
          delayed(
            float.round(combat.effective_attack_delay(cs) *. 1000.0),
            EnemyTurn,
          )
      }
    None -> effect.none()
  }
}

// --- boss specials and statuses ----------------------------------------------

/// A boss special comes due: a fixed one takes hold and re-arms; a rotation
/// rolls its pick first. Quiet once the fight is over.
fn fire_special(model: Model, index: Int) -> #(Model, Effect(Msg)) {
  case active_special(model, index) {
    Error(_) -> #(model, effect.none())
    Ok(combat.SetStatusEvery(delay: delay, status: status)) -> #(
      set_enemy_status(model, status),
      effect.batch([status_expiry(status), special_timer(index, delay)]),
    )
    Ok(combat.RotateStatusEvery(..)) -> #(
      model,
      effect.from(fn(dispatch) { dispatch(ResolveSpecial(index, rng.random())) }),
    )
  }
}

/// Apply a rotation's pick: one of its options at random, never the previous
/// one again (`Events._lastSpecial`).
fn resolve_special(
  model: Model,
  index: Int,
  roll: Float,
) -> #(Model, Effect(Msg)) {
  case active_special(model, index), model.combat {
    Ok(combat.RotateStatusEvery(delay: delay, options: options)), Some(cs) -> {
      let possible = list.filter(options, fn(o) { o != cs.last_special })
      case events.pick(possible, roll) {
        Error(_) -> #(model, special_timer(index, delay))
        Ok(status) -> {
          let cs =
            combat.CombatState(..cs, enemy_status: status, last_special: status)
          #(
            Model(..model, combat: Some(cs)),
            effect.batch([status_expiry(status), special_timer(index, delay)]),
          )
        }
      }
    }
    _, _ -> #(model, effect.none())
  }
}

/// The indexed special of the live, still-unwon fight.
fn active_special(model: Model, index: Int) -> Result(combat.Special, Nil) {
  case model.combat {
    Some(cs) ->
      case cs.won {
        True -> Error(Nil)
        False -> cs.specials |> list.drop(index) |> list.first
      }
    None -> Error(Nil)
  }
}

/// Re-arm a special's timer.
fn special_timer(index: Int, delay: Float) -> Effect(Msg) {
  delayed(float.round(delay *. 1000.0), SpecialFire(index))
}

/// Arm a fight's boss-special timers, one per special.
fn specials_timers(specials: List(combat.Special)) -> Effect(Msg) {
  specials
  |> list.index_map(fn(special, index) {
    case special {
      combat.SetStatusEvery(delay: delay, ..)
      | combat.RotateStatusEvery(delay: delay, ..) ->
        special_timer(index, delay)
    }
  })
  |> effect.batch
}

/// Put a status on the live enemy.
fn set_enemy_status(model: Model, status: combat.Status) -> Model {
  case model.combat {
    Some(cs) ->
      Model(
        ..model,
        combat: Some(combat.CombatState(..cs, enemy_status: status)),
      )
    None -> model
  }
}

/// Enrage and meditation run out on their clocks (the JS setTimeout sets
/// 'none' unconditionally); shields and the one-hit buffs spend themselves.
fn status_expiry(status: combat.Status) -> Effect(Msg) {
  case status {
    combat.Enraged -> delayed(combat.enrage_duration_ms, StatusExpire)
    combat.Meditation -> delayed(combat.meditate_duration_ms, StatusExpire)
    _ -> effect.none()
  }
}

/// Armed poison drips on the player each tick for as long as the fight lasts
/// (the JS interval is only cleared by the fight ending).
fn dot_tick(model: Model) -> #(Model, Effect(Msg)) {
  case model.combat {
    Some(cs) ->
      case cs.player_dot > 0 && !cs.won {
        True -> {
          let hp = int.max(0, cs.player_hp - cs.player_dot)
          case hp <= 0 {
            True -> {
              let dead = die(model)
              #(dead, die_fx(dead))
            }
            False -> #(
              Model(
                ..model,
                combat: Some(combat.CombatState(..cs, player_hp: hp)),
              ),
              delayed(combat.dot_tick_ms, DotTick),
            )
          }
        }
        False -> #(model, effect.none())
      }
    None -> #(model, effect.none())
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
  case model.active_event, model.combat, model.expedition {
    // No wandering off with a setpiece on screen or mid-fight.
    Some(_), _, _ -> #(model, effect.none())
    _, Some(_), _ -> #(model, effect.none())
    _, _, None -> #(model, effect.none())
    _, _, Some(exp) -> {
      let s = world.move(model.state, exp, dir)
      let model = notify_world(Model(..model, state: s.state), s.messages)
      // Every step crunches — even the one that ends at home or in the grave.
      let steps = footstep()
      let on_village =
        world.tile_at(s.expedition.map, s.expedition.pos.0, s.expedition.pos.1)
        == Ok(world.Village)
      case s.alive, on_village {
        // Death is checked first; reaching the village costs no supplies (see
        // `world.move`), so a safe return is always a live one — only then are
        // cleared mines credited.
        False, _ -> {
          let dead = die(model)
          #(dead, effect.batch([die_fx(dead), steps]))
        }
        True, True -> #(go_home(model), steps)
        True, False -> {
          let model = Model(..model, expedition: Some(s.expedition))
          // A landmark launches its setpiece (the `doSpace` order); open ground
          // may instead spring an encounter.
          let #(model, fx) = case setpiece_at(s.expedition, s.state) {
            Ok(event) -> start_event(model, event)
            Error(_) -> #(model, roll_fight())
          }
          #(model, effect.batch([fx, steps]))
        }
      }
    }
  }
}

/// The setpiece to launch on arriving here: a landmark not yet dealt with this
/// trip whose scene we have ported. Open ground and visited landmarks are
/// `Error`, leaving the step to the ordinary encounter roll.
fn setpiece_at(exp: Expedition, s: State) -> Result(events.Event, Nil) {
  use tile <- result.try(world.tile_at(exp.map, exp.pos.0, exp.pos.1))
  case tile {
    // The battleship is its own gate (the `doSpace` executioner branch, ahead
    // of the landmark table): the intro until the ship is unsealed, the
    // elevator antechamber ever after — never marked visited.
    world.Executioner ->
      case state.get_game(s, "world.executioner") == 0 {
        True -> executioner.event("executioner-intro")
        False -> executioner.event("executioner-antechamber")
      }
    _ ->
      case world.should_trigger_setpiece(exp, tile) {
        False -> Error(Nil)
        True -> {
          use name <- result.try(world.setpiece_scene(tile))
          setpieces.setpiece(name)
        }
      }
  }
}

/// Make it home safe — the carried supplies and loot are unloaded, then the
/// expedition ends and the player returns to the room.
fn go_home(model: Model) -> Model {
  // Home safe (`goHome`): cleared mines are credited, the crashed ship and
  // the strange device commission their locations, and carried blueprints
  // are redeemed — all before the outfit is unloaded, so blueprints never
  // reach the stores.
  let cleared = case model.expedition {
    Some(exp) -> set.to_list(exp.mines_cleared)
    None -> []
  }
  let s = list.fold(cleared, model.state, grant_mine)
  let #(s, unlock_messages) = unlock_returns(s)
  let #(s, blueprint_messages) = world.redeem_blueprints(s)
  let s = return_outfit(s)
  let home =
    Model(
      ..notify_world(model, ["a haze falls over the village"]),
      state: s,
      location: Room,
      expedition: None,
      combat: None,
    )
  // Announced once home, where the player now stands.
  notify_room(home, list.append(unlock_messages, blueprint_messages))
}

/// A safe return commissions what was found out there: the crashed ship opens
/// its location (`Ship.init` — hull 0, thrusters 1, the once-only guard), and
/// the strange device opens the fabricator's (`Fabricator.init`).
fn unlock_returns(s: State) -> #(State, List(String)) {
  let s = case
    state.get_game(s, "world.ship") == 1
    && !state.has_feature(s, "location.ship")
  {
    True ->
      s
      |> state.set_feature("location.ship", True)
      |> state.set_game("spaceShip.hull", 0)
      |> state.set_game("spaceShip.thrusters", 1)
    False -> s
  }
  case
    state.get_game(s, "world.executioner") == 1
    && !state.has_feature(s, "location.fabricator")
  {
    True -> #(state.set_feature(s, "location.fabricator", True), [
      "builder knows the strange device when she sees it. takes it for herself real quick. doesn’t ask where it came from.",
    ])
    False -> #(s, [])
  }
}

/// Raise a cleared mine's building on a safe return, the first time only — it
/// opens up its workers in the village (`goHome`).
fn grant_mine(s: State, building: String) -> State {
  case craft.building_count(s, building) {
    0 -> state.set_game(s, craft.building_key(building), 1)
    _ -> s
  }
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
/// Death's audio: the knell, and whatever event or battle music was up fades.
fn die_fx(model: Model) -> Effect(Msg) {
  effect.batch([event_closed_fx(model), sound(audio.death)])
}

fn die(model: Model) -> Model {
  let model = notify_world(model, ["the world fades"])
  Model(
    ..model,
    state: state.State(..model.state, outfit: dict.new()),
    location: Room,
    expedition: None,
    combat: None,
    // A setpiece modal closes with the death — there's no scene to return to.
    active_event: None,
    loot: [],
    drop_for: None,
    blinking: False,
  )
}

/// An effect that rolls a map seed and dispatches `Embarked`.
fn roll_seed() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    dispatch(Embarked(
      seed: float.round(rng.random() *. 1_000_000.0),
      // Prestige data places the destroyed village on this world.
      cache: option.is_some(scoring.load()),
    ))
  })
}

// --- random events ----------------------------------------------------------

/// The event pool that can fire at the current location: the global pool plus
/// the location's own. The global events only call on the settled locations —
/// the Thief needs a store room to be caught in — and the World runs its own
/// encounters, so away from home there is none.
fn event_pool(location: Location) -> List(events.Event) {
  case location {
    Room ->
      list.flatten([
        events.global_events(),
        events.room_events(),
        events.marketing_events(),
      ])
    Outside ->
      list.flatten([
        events.global_events(),
        events.outside_events(),
        events.marketing_events(),
      ])
    _ -> []
  }
}

// --- background music ------------------------------------------------------------

/// The track a location plays on arrival: the Room follows its fire, the
/// Outside its huts; the rest have their own themes.
fn location_track(model: Model) -> String {
  case model.location {
    Room -> fire_track(model.state)
    Outside -> village_track(model.state)
    Path -> audio.music_dusty_path
    World -> audio.music_world
    Ship | Fabricator -> audio.music_ship
    Space -> audio.music_space
  }
}

/// `Room.setMusic` — the fire's five moods.
fn fire_track(s: State) -> String {
  case room.fire(s) {
    room.Dead -> audio.music_fire_dead
    room.Smoldering -> audio.music_fire_smoldering
    room.Flickering -> audio.music_fire_flickering
    room.Burning -> audio.music_fire_burning
    room.Roaring -> audio.music_fire_roaring
  }
}

/// `Outside.onArrival` — the village grows louder by huts.
fn village_track(s: State) -> String {
  case craft.building_count(s, "hut") {
    0 -> audio.music_silent_forest
    1 -> audio.music_lonely_hut
    n if n <= 4 -> audio.music_tiny_village
    n if n <= 8 -> audio.music_modest_village
    n if n <= 14 -> audio.music_large_village
    _ -> audio.music_raucous_village
  }
}

/// After a fire transition: retune the room's music, but only while standing
/// in it (`// only update music if in the room`).
fn room_music_after(pair: #(Model, Effect(Msg))) -> #(Model, Effect(Msg)) {
  let #(model, fx) = pair
  case model.location {
    Room -> {
      let #(model, music) = tune_music(model)
      #(model, effect.batch([fx, music]))
    }
    _ -> #(model, fx)
  }
}

/// Loop the location's current track — only when it actually changes, so the
/// one-second tick doesn't endlessly restart the crossfade.
fn tune_music(model: Model) -> #(Model, Effect(Msg)) {
  play_track(model, location_track(model))
}

fn play_track(model: Model, track: String) -> #(Model, Effect(Msg)) {
  case track == model.playing {
    True -> #(model, effect.none())
    False -> #(
      Model(..model, playing: track),
      effect.from(fn(_) { audio.play_background_music(track) }),
    )
  }
}

/// The first track of a freshly-loaded game, for the app's init.
pub fn startup_music(model: Model) -> #(Model, Effect(Msg)) {
  tune_music(model)
}

/// Put the location's name back on the page title (`stopTitleBlink`'s
/// restore).
fn restore_title(model: Model) -> Effect(Msg) {
  let title = location_title(model.location)
  effect.from(fn(_) { browser.set_title(title) })
}

/// Everything an event's close lets go of: the blinking title and the music
/// (`stopTitleBlink` + `stopEventMusic`).
fn event_closed_fx(model: Model) -> Effect(Msg) {
  effect.batch([
    restore_title(model),
    effect.from(fn(_) { audio.stop_event_music() }),
  ])
}

/// Open a link button's page in a new tab.
fn open_link(url: String) -> Effect(Msg) {
  effect.from(fn(_) { browser.open_url(url) })
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
fn start_event(model: Model, event: events.Event) -> #(Model, Effect(Msg)) {
  case list.key_find(event.scenes, "start") {
    Error(_) -> #(model, effect.none())
    Ok(scene) -> {
      // The event's music loops over the ducked background
      // (`event.audio && playEventMusic`).
      let music = case event.audio {
        Some(track) -> effect.from(fn(_) { audio.play_event_music(track) })
        None -> effect.none()
      }
      let #(model, fx) = load_scene(model, event, "start", scene)
      #(model, effect.batch([fx, music]))
    }
  }
}

/// Apply a chosen button's outcome to the running event.
fn resolve_event(model: Model, id: String, roll: Float) -> #(Model, Effect(Msg)) {
  case model.active_event {
    None -> #(model, effect.none())
    Some(ActiveEvent(event, scene_name)) ->
      case list.key_find(event.scenes, scene_name) {
        Error(_) -> #(model, effect.none())
        Ok(scene) ->
          case list.key_find(scene.buttons, id) {
            Error(_) -> #(model, effect.none())
            Ok(button) ->
              case
                events.click_button(
                  button,
                  model.state,
                  roll,
                  event_purse(model),
                )
              {
                // Too expensive: a no-op, like the JS.
                Error(_) -> #(model, effect.none())
                Ok(#(new_state, purse, messages, step)) -> {
                  let model =
                    notify_here(
                      apply_purse(Model(..model, state: new_state), purse),
                      messages,
                    )
                  // A scene button pressed over a won fight's loot screen
                  // closes the fight: the wound carries home, leftovers are
                  // forfeited (the JS take-it-or-leave-it).
                  let model = case model.combat {
                    Some(cs) ->
                      case cs.won {
                        True -> finish_looting(model)
                        False -> model
                      }
                    None -> model
                  }
                  let #(model, button_fx) =
                    apply_button_effect(model, button.effect)
                  case button.link {
                    // A link button ends the event and opens the page (the
                    // JS `endEvent()` + `window.open`), skipping nextScene.
                    Some(url) -> {
                      let model =
                        Model(..model, active_event: None, blinking: False)
                      #(
                        model,
                        effect.batch([
                          open_link(url),
                          button_fx,
                          event_closed_fx(model),
                        ]),
                      )
                    }
                    None -> {
                      let #(model, fx) = advance_event(model, event, step)
                      #(model, effect.batch([fx, button_fx]))
                    }
                  }
                }
              }
          }
      }
  }
}

/// The purse event costs draw on here (`Events.getQuantity`): the carried
/// outfit and vitals out in the world, the home stores otherwise.
pub fn event_purse(model: Model) -> events.Purse {
  case model.location, model.expedition {
    World, Some(exp) ->
      events.Carried(water: exp.vitals.water, hp: exp.vitals.health)
    _, _ -> events.HomeStores
  }
}

/// A button's world-level `onChoose`: the wings' regenerative machines reknit
/// muscle and bone (`World.setHp(World.getMaxHealth())`); scavenged maps roll
/// their reveals.
fn apply_button_effect(
  model: Model,
  button_effect: Option(events.ButtonEffect),
) -> #(Model, Effect(Msg)) {
  case button_effect, model.expedition {
    Some(events.HealToMax), Some(exp) -> #(
      Model(
        ..model,
        expedition: Some(
          world.Expedition(
            ..exp,
            vitals: world.Vitals(
              ..exp.vitals,
              health: world.max_health(model.state),
            ),
          ),
        ),
      ),
      effect.none(),
    )
    Some(events.ApplyMap(times: times)), Some(_) -> #(
      model,
      effect.from(fn(dispatch) {
        let rolls = list.map(list.repeat(Nil, times), fn(_) { rng.random() })
        dispatch(MapsScavenged(rolls))
      }),
    )
    Some(events.LiftOff), _ -> update(model, Navigate(to: Space))
    Some(events.ClearCooldown(id)), _ -> #(
      Model(..model, cooldowns: dict.delete(model.cooldowns, id)),
      effect.none(),
    )
    _, _ -> #(model, effect.none())
  }
}

/// Reveal a patch of the world per scavenged map.
fn scavenge_maps(model: Model, rolls: List(Float)) -> Model {
  case model.expedition {
    Some(exp) ->
      Model(
        ..model,
        expedition: Some(
          list.fold(rolls, exp, fn(e, roll) { world.apply_map(e, roll) }),
        ),
      )
    None -> model
  }
}

/// Write a paid purse's water/hp back onto the expedition.
fn apply_purse(model: Model, purse: events.Purse) -> Model {
  case purse, model.expedition {
    events.Carried(water: water, hp: hp), Some(exp) ->
      Model(
        ..model,
        expedition: Some(
          world.Expedition(
            ..exp,
            vitals: world.Vitals(..exp.vitals, water: water, health: hp),
          ),
        ),
      )
    _, _ -> model
  }
}

/// Move the running event along after a button outcome.
fn advance_event(
  model: Model,
  event: events.Event,
  step: events.Step,
) -> #(Model, Effect(Msg)) {
  case step {
    events.StayOnScene -> #(model, effect.none())
    events.EndEvent -> {
      let model =
        Model(
          ..model,
          active_event: None,
          loot: [],
          drop_for: None,
          blinking: False,
        )
      #(model, event_closed_fx(model))
    }
    events.LoadScene(next) ->
      case list.key_find(event.scenes, next) {
        Error(_) -> {
          let model =
            Model(
              ..model,
              active_event: None,
              loot: [],
              drop_for: None,
              blinking: False,
            )
          #(model, event_closed_fx(model))
        }
        Ok(scene) ->
          load_scene(
            Model(..model, loot: [], drop_for: None),
            event,
            next,
            scene,
          )
      }
    // The JS switchEvent: close this event, start the keyed one. The registry
    // spans the setpieces and the executioner chain, in that lookup order. An
    // unknown key stays put (`if (!event) return`).
    events.SwitchEvent(key) ->
      case
        setpieces.setpiece(key)
        |> result.lazy_or(fn() { executioner.event(key) })
      {
        Error(_) -> #(model, effect.none())
        Ok(next_event) -> {
          let #(model, fx) = start_event(model, next_event)
          #(
            model,
            effect.batch([
              effect.from(fn(_) { audio.stop_event_music() }),
              fx,
            ]),
          )
        }
      }
  }
}

/// Load one scene of a running event: run its world-level `onLoad` (setpieces
/// marking a landmark visited or draining an outpost), then its `State`-level
/// `onLoad` + reward + notification, set it the active scene, and — when it
/// carries loot — kick off the roll that grants it.
fn load_scene(
  model: Model,
  event: events.Event,
  name: String,
  scene: events.Scene,
) -> #(Model, Effect(Msg)) {
  // A blink-marked scene starts the title flashing (`blinkTitle`).
  let model = case scene.blink && !model.blinking {
    True -> Model(..model, blinking: True)
    False -> model
  }
  let blink_fx = case scene.blink {
    True -> delayed(3000, BlinkOn)
    False -> effect.none()
  }
  let #(model, world_messages) = apply_world_effect(model, scene)
  let #(new_state, messages) = events.enter_scene(scene, model.state)
  let model =
    notify_here(
      Model(
        ..model,
        state: new_state,
        active_event: Some(ActiveEvent(event, name)),
      ),
      list.append(world_messages, messages),
    )
  // A combat scene starts a fight on entry (its loot lands on the win, the way
  // an encounter's does); a story scene grants any loot straight away.
  case combat_scene_enemy(scene), model.expedition {
    Some(foe), Some(exp) -> {
      let cs =
        combat.begin_combat(
          foe,
          exp.vitals.health,
          world.max_health(model.state),
        )
      // A boss scene's specials, atHealth triggers and dying blast ride on
      // the fight.
      let cs = case scene.setpiece {
        Some(extra) ->
          combat.CombatState(
            ..cs,
            specials: extra.specials,
            at_health: extra.at_health,
            exploding: extra.explosion,
          )
        None -> cs
      }
      let model = Model(..model, combat: Some(cs))
      #(
        model,
        effect.batch([
          enemy_timer(model.combat),
          specials_timers(cs.specials),
          blink_fx,
        ]),
      )
    }
    _, _ -> #(
      model,
      effect.batch([
        setpiece_loot_effect(scene),
        scene_rng_effect(scene),
        blink_fx,
      ]),
    )
  }
}

/// An effect that rolls for a scene's random `onLoad` (a disaster's toll),
/// reported as `SceneRng`. Nothing when the scene has no such `onLoad`.
fn scene_rng_effect(scene: events.Scene) -> Effect(Msg) {
  case scene.on_load_rng {
    Some(_) -> effect.from(fn(dispatch) { dispatch(SceneRng(rng.random())) })
    None -> effect.none()
  }
}

/// Run the active scene's random `onLoad` with `roll` (the disasters cut the
/// population, raze huts or wreck traps), logging what it reports.
fn run_scene_rng(model: Model, roll: Float) -> Model {
  case active_scene(model) {
    Ok(events.Scene(on_load_rng: Some(f), ..)) -> {
      let #(state, messages) = f(model.state, roll)
      notify_here(Model(..model, state:), messages)
    }
    _ -> model
  }
}

/// The inline enemy of a combat setpiece scene, if it is one.
fn combat_scene_enemy(scene: events.Scene) -> Option(combat.Enemy) {
  case scene.combat, scene.setpiece {
    True, Some(events.SetpieceExtra(enemy: enemy, ..)) -> enemy
    _, _ -> None
  }
}

/// A setpiece scene's world-level `onLoad`: mark the landmark under the player
/// visited, or drink the outpost dry (refilling water). A no-op for the random
/// events, which carry no `setpiece`.
fn apply_world_effect(
  model: Model,
  scene: events.Scene,
) -> #(Model, List(String)) {
  case scene.setpiece, model.expedition {
    Some(extra), Some(exp) ->
      case extra.world_effect {
        events.MarkVisited -> #(
          Model(..model, expedition: Some(world.mark_visited(exp))),
          [],
        )
        events.UseOutpost -> #(
          Model(..model, expedition: Some(world.use_outpost(exp, model.state))),
          ["water replenished"],
        )
        events.RefillSupplies -> #(
          Model(
            ..model,
            expedition: Some(
              world.mark_visited(world.refill_water(exp, model.state)),
            ),
          ),
          ["water replenished"],
        )
        events.FoundShip -> #(
          Model(
            ..model,
            expedition: Some(world.mark_visited(world.lay_road(exp))),
            // A way off this rock — recorded for the endgame (M6).
            state: state.set_game(model.state, "world.ship", 1),
          ),
          [],
        )
        events.ClearMine(building) -> #(
          Model(..model, expedition: Some(world.clear_mine(exp, building))),
          [],
        )
        events.ClearDungeon -> #(
          Model(..model, expedition: Some(world.clear_dungeon(exp))),
          [],
        )
        events.FoundExecutioner -> #(
          Model(
            ..model,
            expedition: Some(world.lay_road(exp)),
            // Unsealed: from now on the antechamber's elevators await.
            state: state.set_game(model.state, "world.executioner", 1),
          ),
          [],
        )
        events.CollectCache -> {
          // The previous generation's supplies, claimed — read and emptied
          // synchronously, exactly as collectStores mutates $SM in its onLoad.
          let s =
            list.fold(scoring.collect(), model.state, fn(acc, item) {
              state.add_store(acc, item.0, item.1)
            })
          #(
            Model(..model, expedition: Some(world.mark_visited(exp)), state: s),
            [],
          )
        }
        events.NoWorldEffect -> #(model, [])
      }
    _, _ -> #(model, [])
  }
}

/// An effect that rolls a setpiece scene's loot (two samples per drop), reported
/// as `SetpieceLoot`. Nothing to roll when the scene carries no loot.
fn setpiece_loot_effect(scene: events.Scene) -> Effect(Msg) {
  case scene.setpiece {
    Some(events.SetpieceExtra(loot: [_, ..] as loot, ..)) ->
      effect.from(fn(dispatch) {
        let rolls =
          list.map(list.repeat(Nil, list.length(loot) * 2), fn(_) {
            rng.random()
          })
        dispatch(SetpieceLoot(rolls))
      })
    _ -> effect.none()
  }
}

/// Grant the current setpiece scene's rolled loot into the carried outfit (it is
/// credited to stores on a safe return), logging what was found.
fn grant_setpiece_loot(model: Model, rolls: List(Float)) -> Model {
  case active_scene(model) {
    // The scene's drops wait in rows for the player to take (`drawLoot`),
    // not in the pack — and the take-everything button starts its second of
    // cooling here too.
    Ok(events.Scene(setpiece: Some(extra), ..)) -> {
      let loot =
        combat.roll_loot(extra.loot, rolls)
        |> list.filter(fn(l) { l.1 > 0 })
      Model(..model, loot: loot, drop_for: None)
      |> start_cooldown("loot_take_et", leave_cooldown_ms)
    }
    _ -> model
  }
}

/// The scene the running event is currently showing, if any.
fn active_scene(model: Model) -> Result(events.Scene, Nil) {
  case model.active_event {
    Some(ActiveEvent(event, name)) -> list.key_find(event.scenes, name)
    None -> Error(Nil)
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
