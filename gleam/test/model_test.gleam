import adarkroom/craft
import adarkroom/model.{
  CollectLoot, MaybeFight, Navigate, ResolveEnemyTurn, ResolveEvent,
  ResolveStrike, ScheduleEvent, Tick, TriggerEvent,
}
import adarkroom/notifications
import adarkroom/outside
import adarkroom/rng
import adarkroom/room
import adarkroom/state
import adarkroom/world
import gleam/dict
import gleam/list
import gleam/option
import gleam/set
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

pub fn tick_reveals_buildings_when_builder_helps_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("builder", 4)
        |> state.set_store("wood", 5),
    )
  let after = run(m, Tick)
  set.contains(after.revealed, "trap") |> should.equal(True)
  notifications.messages(after.notifications)
  |> should.equal([
    "builder says she can make traps to catch any creatures might still be alive out there.",
  ])
}

pub fn tick_reveals_nothing_without_helper_test() {
  let after = run(model.init(), Tick)
  set.size(after.revealed) |> should.equal(0)
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
  // The queued note is flushed on arrival (alongside the first-visit forest note).
  notifications.messages(arrived.notifications)
  |> list.contains("a stranger arrives.")
  |> should.equal(True)
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
  // Newest first: the forest reveal follows the stumble-in, after lighting.
  notifications.messages(m.notifications)
  |> should.equal([
    "the wood is running out.",
    "the wind howls outside.",
    "a ragged stranger stumbles through the door and collapses in the corner.",
    "the light from the fire spills from the windows, out into the dark.",
    "the fire is burning.",
  ])
}

pub fn arriving_at_room_makes_sleeping_builder_help_test() {
  // Builder is "up" (level 3, sleeping) and the player is away; returning to the
  // Room is when she offers to help (faithful to the original's onArrival).
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Outside,
      state: state.set_game(base.state, "builder", 3),
    )
  let arrived = run(m, Navigate(to: model.Room))
  room.builder_helping(arrived.state) |> should.equal(True)
  notifications.messages(arrived.notifications)
  |> should.equal([
    "the stranger is standing by the fire. she says she can help. says she builds things.",
  ])
}

pub fn arriving_at_room_noop_when_builder_not_sleeping_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Outside,
      state: state.set_game(base.state, "builder", 2),
    )
  let arrived = run(m, Navigate(to: model.Room))
  room.builder_level(arrived.state) |> should.equal(2)
  notifications.messages(arrived.notifications) |> should.equal([])
}

pub fn arriving_elsewhere_does_not_make_builder_help_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: state.set_feature(
        state.set_game(base.state, "builder", 3),
        "location.outside",
        True,
      ),
    )
  let arrived = run(m, Navigate(to: model.Outside))
  room.builder_level(arrived.state) |> should.equal(3)
}

pub fn failed_light_does_not_summon_builder_test() {
  let base = model.init()
  let m = model.Model(..base, state: state.set_store(base.state, "wood", 3))
  let after = run(m, model.LightFire)
  room.fire(after.state) |> should.equal(room.Dead)
  room.builder_level(after.state) |> should.equal(-1)
  state.has_feature(after.state, "location.outside") |> should.equal(False)
}

pub fn build_message_raises_building_and_notifies_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("temperature", 2)
        |> state.set_store("wood", 50),
    )
  let after = run(m, model.Build("trap"))
  craft.building_count(after.state, "trap") |> should.equal(1)
  state.get_store(after.state, "wood") |> should.equal(40)
  notifications.messages(after.notifications)
  |> should.equal(["more traps to catch more creatures."])
}

pub fn cool_check_updates_now_test() {
  let after = run(model.init(), model.CoolCheck(at: 12_345))
  after.now |> should.equal(12_345)
}

pub fn gather_wood_message_adds_wood_test() {
  let after = run(model.init(), model.GatherWood)
  state.get_store(after.state, "wood") |> should.equal(10)
}

pub fn gather_wood_starts_a_cooldown_test() {
  let m = model.Model(..model.init(), now: 1000)
  let after = run(m, model.GatherWood)
  model.on_cooldown(after, "gather") |> should.equal(True)
}

pub fn gather_wood_blocked_while_on_cooldown_test() {
  let m = model.Model(..model.init(), now: 1000)
  let once = run(m, model.GatherWood)
  // Time has not advanced — a second gather is refused, no extra wood.
  let twice = run(once, model.GatherWood)
  state.get_store(twice.state, "wood") |> should.equal(10)
}

pub fn cooldown_expires_once_now_passes_the_deadline_test() {
  let m = model.Model(..model.init(), now: 1000)
  let after = run(m, model.GatherWood)
  model.on_cooldown(after, "gather") |> should.equal(True)
  let later = model.Model(..after, now: 1000 + outside.gather_cooldown_ms)
  model.on_cooldown(later, "gather") |> should.equal(False)
}

pub fn cooldown_fraction_decreases_with_time_test() {
  let m = model.Model(..model.init(), now: 0)
  let after = run(m, model.GatherWood)
  model.cooldown_fraction(after, "gather", outside.gather_cooldown_ms)
  |> should.equal(1.0)
  let mid = model.Model(..after, now: 30_000)
  model.cooldown_fraction(mid, "gather", outside.gather_cooldown_ms)
  |> should.equal(0.5)
}

pub fn cooldown_fraction_guards_zero_duration_test() {
  let m = model.Model(..model.init(), now: 0)
  let after = run(m, model.GatherWood)
  // A zero (or negative) duration must not divide by zero.
  model.cooldown_fraction(after, "gather", 0) |> should.equal(0.0)
}

pub fn increase_worker_message_assigns_villagers_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.set_game(state.new(), "population", 5),
    )
  let after = run(m, model.IncreaseWorker(role: "hunter", by: 2))
  outside.worker_count(after.state, "hunter") |> should.equal(2)
  outside.num_gatherers(after.state) |> should.equal(3)
}

pub fn decrease_worker_message_unassigns_villagers_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.new()
        |> state.set_game("population", 5)
        |> state.set_game("worker.hunter", 4),
    )
  let after = run(m, model.DecreaseWorker(role: "hunter", by: 1))
  outside.worker_count(after.state, "hunter") |> should.equal(3)
}

pub fn collect_income_message_gives_builder_wood_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.set_game(state.new(), "builder", 4),
    )
  let after = run(m, model.CollectIncome)
  state.get_store(after.state, "wood") |> should.equal(2)
}

pub fn population_increased_adds_villagers_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.set_game(state.new(), "building.hut", 2),
    )
  let after = run(m, model.PopulationIncreased(roll: 0.0))
  outside.population(after.state) |> should.equal(4)
}

pub fn check_traps_message_starts_a_cooldown_test() {
  let m =
    model.Model(
      ..model.init(),
      now: 1000,
      state: state.set_game(state.new(), "building.trap", 2),
    )
  let after = run(m, model.CheckTraps)
  model.on_cooldown(after, "traps") |> should.equal(True)
}

pub fn check_traps_blocked_while_on_cooldown_test() {
  let m =
    model.Model(
      ..model.init(),
      now: 1000,
      state: state.set_game(state.new(), "building.trap", 2),
    )
  let once = run(m, model.CheckTraps)
  // The cooldown deadline does not move on a second, blocked click.
  let twice = run(once, model.CheckTraps)
  twice.cooldowns |> should.equal(once.cooldowns)
}

pub fn traps_checked_applies_drops_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.set_game(state.new(), "building.trap", 1),
    )
  let after = run(m, model.TrapsChecked(rolls: [0.1]))
  state.get_store(after.state, "fur") |> should.equal(1)
}

pub fn buy_message_adds_good_and_spends_fur_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("building.trading post", 1)
        |> state.set_store("fur", 200),
    )
  let after = run(m, model.Buy("scales"))
  state.get_store(after.state, "scales") |> should.equal(1)
  state.get_store(after.state, "fur") |> should.equal(50)
}

pub fn increase_supply_message_packs_the_bag_test() {
  let m =
    model.Model(
      ..model.init(),
      state: state.set_store(state.new(), "cured meat", 5),
    )
  let after = run(m, model.IncreaseSupply(item: "cured meat", by: 3))
  state.get_outfit(after.state, "cured meat") |> should.equal(3)
  let removed = run(after, model.DecreaseSupply(item: "cured meat", by: 1))
  state.get_outfit(removed.state, "cured meat") |> should.equal(2)
}

pub fn buying_the_compass_reveals_the_path_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("building.trading post", 1)
        |> state.set_store("fur", 500)
        |> state.set_store("scales", 50)
        |> state.set_store("teeth", 50),
    )
  let after = run(m, model.Buy("compass"))
  state.get_store(after.state, "compass") |> should.equal(1)
  state.has_feature(after.state, "location.path") |> should.equal(True)
  model.unlocked_locations(after)
  |> list.contains(model.Path)
  |> should.equal(True)
}

pub fn light_fire_resets_cool_deadline_test() {
  let base = model.init()
  let m = model.Model(..base, state: state.set_game(base.state, "coolAt", 9999))
  let after = run(m, model.LightFire)
  // fire_action re-arms cooling: the deadline is reset (next CoolCheck re-arms).
  state.get_game(after.state, "coolAt") |> should.equal(0)
}

// --- world expedition lifecycle ---------------------------------------------

pub fn embarking_drops_into_the_world_with_supplies_taken_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Path,
      state: base.state
        |> state.set_store("cured meat", 5)
        |> state.set_outfit("cured meat", 3),
    )
  let after = run(m, model.Embarked(seed: 1))
  after.location |> should.equal(model.World)
  // The 3 packed meat leave the village stores.
  state.get_store(after.state, "cured meat") |> should.equal(2)
  option.is_some(after.expedition) |> should.equal(True)
}

pub fn moving_keeps_exploring_until_home_or_dead_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Path,
      state: state.set_outfit(state.new(), "cured meat", 5),
    )
  let embarked = run(m, model.Embarked(seed: 1))
  let moved = run(embarked, model.MoveEast)
  moved.location |> should.equal(model.World)
  option.is_some(moved.expedition) |> should.equal(True)
}

pub fn reaching_the_village_ends_the_expedition_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Path,
      state: state.set_outfit(state.new(), "cured meat", 5),
    )
  let embarked = run(m, model.Embarked(seed: 1))
  // Step out and back onto the village.
  let home = run(run(embarked, model.MoveEast), model.MoveWest)
  home.location |> should.equal(model.Room)
  option.is_none(home.expedition) |> should.equal(True)
}

pub fn dying_returns_to_the_room_and_drops_the_supplies_test() {
  let base = model.init()
  let s = state.set_outfit(state.new(), "cured meat", 5)
  // Already parched, away from the village — the next step is fatal.
  let exp =
    world.Expedition(
      ..world.begin(world.generate_map(rng.seed(1)), s),
      pos: #(31, 30),
      vitals: world.Vitals(
        water: 0,
        health: 10,
        food_move: 0,
        water_move: 0,
        starvation: False,
        thirst: True,
      ),
    )
  let m =
    model.Model(
      ..base,
      state: s,
      location: model.World,
      expedition: option.Some(exp),
    )
  let after = run(m, model.MoveEast)
  after.location |> should.equal(model.Room)
  state.get_outfit(after.state, "cured meat") |> should.equal(0)
}

// --- random events ----------------------------------------------------------

/// A Room model with a wall clock set and the given fur on hand.
fn room_with_fur(fur: Int, now: Int) -> model.Model {
  let base = model.init()
  model.Model(..base, now: now, state: state.set_store(base.state, "fur", fur))
}

pub fn trigger_event_starts_an_available_event_test() {
  // Fur on hand makes the Nomad available; pick 0.0 selects it.
  let after = run(room_with_fur(10, 1000), TriggerEvent(0.0, 0.0))
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("The Nomad")
  active.scene |> should.equal("start")
}

pub fn trigger_event_stays_idle_when_nothing_qualifies_test() {
  // No fur: the Nomad isn't available, so no event starts — but a slot is set.
  let after = run(room_with_fur(0, 1000), TriggerEvent(0.0, 0.0))
  after.active_event |> should.equal(option.None)
  { after.next_event_at > 1000 } |> should.equal(True)
}

pub fn buying_scales_from_the_nomad_updates_stores_and_stays_test() {
  let started = run(room_with_fur(150, 1000), TriggerEvent(0.0, 0.0))
  let after = run(started, ResolveEvent("buyScales", 0.5))
  state.get_store(after.state, "fur") |> should.equal(50)
  state.get_store(after.state, "scales") |> should.equal(1)
  // A trade button has no nextScene — the merchant stays open.
  let assert option.Some(active) = after.active_event
  active.scene |> should.equal("start")
}

pub fn an_unaffordable_choice_is_a_no_op_test() {
  // Scales cost 100 fur; with only 10 the click does nothing.
  let started = run(room_with_fur(10, 1000), TriggerEvent(0.0, 0.0))
  let after = run(started, ResolveEvent("buyScales", 0.5))
  state.get_store(after.state, "fur") |> should.equal(10)
  after.active_event |> should.not_equal(option.None)
}

pub fn saying_goodbye_closes_the_event_test() {
  let started = run(room_with_fur(10, 1000), TriggerEvent(0.0, 0.0))
  let after = run(started, ResolveEvent("goodbye", 0.5))
  after.active_event |> should.equal(option.None)
}

pub fn return_outfit_credits_carried_items_and_unpacks_loot_test() {
  let s =
    state.new()
    |> state.set_outfit("cured meat", 3)
    |> state.set_outfit("iron sword", 1)
    |> state.set_outfit("fur", 40)
  let after = model.return_outfit(s)
  // everything carried is credited to the village stores
  state.get_store(after, "cured meat") |> should.equal(3)
  state.get_store(after, "iron sword") |> should.equal(1)
  state.get_store(after, "fur") |> should.equal(40)
  // supplies and weapons stay in the loadout; raw loot is unpacked
  state.get_outfit(after, "cured meat") |> should.equal(3)
  state.get_outfit(after, "iron sword") |> should.equal(1)
  state.get_outfit(after, "fur") |> should.equal(0)
}

pub fn embarking_marks_the_world_as_reached_test() {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      location: model.Path,
      state: base.state |> state.set_outfit("cured meat", 5),
    )
  let after = run(m, model.Embarked(42))
  state.has_feature(after.state, "location.world") |> should.equal(True)
}

pub fn schedule_event_sets_the_next_deadline_test() {
  let base = model.init()
  let m = model.Model(..base, now: 5000)
  // floor(0.0 * 3) + 3 = 3 minutes = 180_000 ms from now.
  run(m, ScheduleEvent(0.0)).next_event_at |> should.equal(185_000)
}

// --- world combat -----------------------------------------------------------

/// An expedition standing on forest, `dist` tiles into the wilds, the player at
/// `health` HP.
fn forest_expedition(dist: Int, health: Int) -> world.Expedition {
  let pos = #(world.radius + dist, world.radius)
  world.Expedition(
    pos: pos,
    map: dict.from_list([#(pos, world.Forest)]),
    seen: set.new(),
    vitals: world.Vitals(
      water: 10,
      health: health,
      food_move: 0,
      water_move: 0,
      starvation: False,
      thirst: False,
    ),
  )
}

/// A model out in the world, far enough since the last fight for one to spring.
fn world_model(health: Int) -> model.Model {
  let base = model.init()
  model.Model(
    ..base,
    location: model.World,
    expedition: option.Some(forest_expedition(3, health)),
    fight_move: 4,
  )
}

pub fn a_step_in_the_forest_can_spring_an_encounter_test() {
  // fight_move 4 (> delay 3); a 0.0 trigger roll fires; pick the first forest foe.
  let after = run(world_model(10), MaybeFight(0.0, 0.0))
  let assert option.Some(cs) = after.combat
  cs.enemy.name |> should.equal("snarling beast")
  cs.player_hp |> should.equal(10)
}

pub fn a_calm_step_starts_no_fight_test() {
  // 0.9 is above the 0.2 fight chance.
  run(world_model(10), MaybeFight(0.9, 0.0)).combat
  |> should.equal(option.None)
}

pub fn felling_the_enemy_wins_and_drops_loot_into_the_outfit_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  // steel sword deals 6 > the beast's 5 HP; a 0.5 roll lands.
  let won = run(fighting, ResolveStrike("steel sword", 0.5))
  let assert option.Some(cs) = won.combat
  cs.won |> should.equal(True)
  // Collect: fur/meat/teeth, each chance roll passes and each qty roll → min 1.
  let done = run(won, CollectLoot([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
  done.combat |> should.equal(option.None)
  state.get_outfit(done.state, "fur") |> should.equal(1)
  state.get_outfit(done.state, "meat") |> should.equal(1)
  state.get_outfit(done.state, "teeth") |> should.equal(1)
}

pub fn a_lethal_enemy_blow_ends_the_expedition_test() {
  // The player starts the fight on 1 HP; the beast's blow fells them.
  let fighting = run(world_model(1), MaybeFight(0.0, 0.0))
  let dead = run(fighting, ResolveEnemyTurn(0.0))
  dead.location |> should.equal(model.Room)
  dead.expedition |> should.equal(option.None)
  dead.combat |> should.equal(option.None)
}

pub fn you_cannot_wander_off_mid_fight_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  let after = run(fighting, model.MoveNorth)
  // The fight (and position) are untouched by the blocked move.
  after.combat |> should.equal(fighting.combat)
  after.expedition |> should.equal(fighting.expedition)
}

pub fn eating_meat_in_a_fight_heals_and_spends_a_meat_test() {
  let base = world_model(3)
  let m =
    model.Model(..base, state: state.set_outfit(base.state, "cured meat", 2))
  let fighting = run(m, MaybeFight(0.0, 0.0))
  let healed = run(fighting, model.Heal("cured meat"))
  let assert option.Some(cs) = healed.combat
  // 3 + 8 meat heal = 11, clamped to the 10 max.
  cs.player_hp |> should.equal(10)
  state.get_outfit(healed.state, "cured meat") |> should.equal(1)
}

pub fn the_eat_cooldown_blocks_a_second_bite_test() {
  let base = world_model(3)
  let m =
    model.Model(..base, state: state.set_outfit(base.state, "cured meat", 5))
  let fighting = run(m, MaybeFight(0.0, 0.0))
  let once = run(fighting, model.Heal("cured meat"))
  // Still on the eat cooldown (now hasn't advanced) — the second bite is refused.
  let twice = run(once, model.Heal("cured meat"))
  state.get_outfit(twice.state, "cured meat") |> should.equal(4)
}
