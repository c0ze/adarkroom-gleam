import adarkroom/combat
import adarkroom/craft
import adarkroom/events
import adarkroom/executioner
import adarkroom/model.{
  CollectLoot, MaybeFight, Navigate, ResolveEnemyTurn, ResolveEvent,
  ResolveStrike, ScheduleEvent, Tick, TriggerEvent,
}
import adarkroom/notifications
import adarkroom/outside
import adarkroom/rng
import adarkroom/room
import adarkroom/ship
import adarkroom/space
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
  let after = run(m, model.Embarked(seed: 1, cache: False))
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
  let embarked = run(m, model.Embarked(seed: 1, cache: False))
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
  let embarked = run(m, model.Embarked(seed: 1, cache: False))
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
  // No fur (no Nomad) and Penrose already given in to: no event starts — but
  // a slot is set.
  let base = room_with_fur(0, 1000)
  let m =
    model.Model(
      ..base,
      state: state.set_game(base.state, "marketing.penrose", 1),
    )
  let after = run(m, TriggerEvent(0.0, 0.0))
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
  let after = run(m, model.Embarked(seed: 42, cache: False))
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
    visited: set.new(),
    used_outposts: set.new(),
    mines_cleared: set.new(),
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

pub fn felling_the_enemy_offers_its_loot_in_rows_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  // steel sword deals 6 > the beast's 5 HP; a 0.5 roll lands.
  let won = run(fighting, ResolveStrike("steel sword", 0.5))
  let assert option.Some(cs) = won.combat
  cs.won |> should.equal(True)
  // The drops wait in rows — the fight stays open as a looting phase.
  let looting = run(won, CollectLoot([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
  looting.combat |> should.not_equal(option.None)
  looting.loot |> should.equal([#("fur", 1), #("meat", 1), #("teeth", 1)])
  // Take everything: all fits, so the encounter also closes.
  let done = run(looting, model.TakeEverything)
  done.combat |> should.equal(option.None)
  done.loot |> should.equal([])
  state.get_outfit(done.state, "fur") |> should.equal(1)
  state.get_outfit(done.state, "meat") |> should.equal(1)
  state.get_outfit(done.state, "teeth") |> should.equal(1)
}

pub fn loot_that_does_not_fit_offers_the_drop_menu_test() {
  // A pack stuffed with 10 bone spears (20 of 10 capacity? no — capacity 10,
  // spears weigh 2: 5 fill it). Taking a fur (weight 1) cannot fit.
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  let won = run(fighting, ResolveStrike("steel sword", 0.5))
  let stuffed =
    model.Model(..won, state: state.set_outfit(won.state, "bone spear", 5))
  let looting = run(stuffed, CollectLoot([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
  let refused = run(looting, model.TakeLoot("fur"))
  refused.drop_for |> should.equal(option.Some("fur"))
  state.get_outfit(refused.state, "fur") |> should.equal(0)
  // Drop a spear: room for two furs' weight; the wanted fur is taken in the
  // same motion, and the spear joins the rows for the taking.
  let dropped = run(refused, model.DropCarried("bone spear", 1))
  state.get_outfit(dropped.state, "bone spear") |> should.equal(4)
  state.get_outfit(dropped.state, "fur") |> should.equal(1)
  list.key_find(dropped.loot, "bone spear") |> should.equal(Ok(1))
  dropped.drop_for |> should.equal(option.None)
}

pub fn leaving_the_loot_screen_forfeits_the_rest_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  let won = run(fighting, ResolveStrike("steel sword", 0.5))
  let looting = run(won, CollectLoot([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
  let left = run(looting, model.LootDone)
  left.combat |> should.equal(option.None)
  left.loot |> should.equal([])
  state.get_outfit(left.state, "fur") |> should.equal(0)
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

pub fn medicine_mends_twenty_with_room_to_spare_test() {
  // Kinetic armour lifts the max so the full heal shows (no clamp).
  let base = world_model(1)
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_outfit("medicine", 1)
        |> state.set_store("kinetic armour", 1),
    )
  let healed = run(run(m, MaybeFight(0.0, 0.0)), model.Heal("medicine"))
  let assert option.Some(cs) = healed.combat
  cs.player_hp |> should.equal(21)
  // Medicine has its own cooldown — eating meat is still allowed.
  model.on_cooldown(healed, "meds") |> should.equal(True)
  model.on_cooldown(healed, "eat") |> should.equal(False)
}

pub fn a_hypo_mends_thirty_test() {
  let base = world_model(1)
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_outfit("hypo", 1)
        |> state.set_store("kinetic armour", 1),
    )
  let healed = run(run(m, MaybeFight(0.0, 0.0)), model.Heal("hypo"))
  let assert option.Some(cs) = healed.combat
  cs.player_hp |> should.equal(31)
  model.on_cooldown(healed, "hypo") |> should.equal(True)
}

pub fn a_swing_starts_the_weapons_cooldown_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  let after = run(fighting, model.StrikeEnemy("iron sword"))
  // The iron sword (2s cooldown) is now cooling — no rapid second swing.
  model.on_cooldown(after, "attack_iron sword") |> should.equal(True)
}

pub fn a_weapon_on_cooldown_refuses_a_second_swing_test() {
  let fighting = run(world_model(10), MaybeFight(0.0, 0.0))
  // Arm the iron sword with a far-future deadline, then try to swing again.
  let cooling =
    model.Model(
      ..fighting,
      now: 1000,
      cooldowns: dict.insert(fighting.cooldowns, "attack_iron sword", 999_999),
    )
  let after = run(cooling, model.StrikeEnemy("iron sword"))
  // The deadline is untouched — the swing was refused, not re-armed (which
  // would have dropped it to now + 2000).
  dict.get(after.cooldowns, "attack_iron sword") |> should.equal(Ok(999_999))
}

// --- setpieces --------------------------------------------------------------

/// A model out in the world with `tile` one step east of the player.
fn at_landmark(tile: world.Tile) -> model.Model {
  let center = #(world.radius, world.radius)
  let east = #(world.radius + 1, world.radius)
  let exp =
    world.Expedition(
      pos: center,
      map: dict.from_list([#(center, world.Forest), #(east, tile)]),
      seen: set.new(),
      vitals: world.Vitals(10, 10, 0, 0, False, False),
      visited: set.new(),
      used_outposts: set.new(),
      mines_cleared: set.new(),
    )
  model.Model(
    ..model.init(),
    location: model.World,
    expedition: option.Some(exp),
  )
}

pub fn stepping_onto_a_landmark_launches_its_setpiece_test() {
  let after = run(at_landmark(world.Battlefield), model.MoveEast)
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("A Forgotten Battlefield")
  active.scene |> should.equal("start")
  // A setpiece, not a random encounter.
  after.combat |> should.equal(option.None)
}

pub fn open_ground_springs_no_setpiece_test() {
  let after = run(at_landmark(world.Forest), model.MoveEast)
  after.active_event |> should.equal(option.None)
}

pub fn you_cannot_wander_off_with_a_setpiece_open_test() {
  let open = run(at_landmark(world.Battlefield), model.MoveEast)
  let after = run(open, model.MoveEast)
  after.expedition |> should.equal(open.expedition)
  after.active_event |> should.equal(open.active_event)
}

pub fn arriving_at_the_battlefield_marks_it_visited_test() {
  let after = run(at_landmark(world.Battlefield), model.MoveEast)
  let assert option.Some(exp) = after.expedition
  set.contains(exp.visited, exp.pos) |> should.be_true
}

pub fn battlefield_loot_waits_in_rows_until_taken_test() {
  let open = run(at_landmark(world.Battlefield), model.MoveEast)
  // Each chance roll of 0.0 passes; each qty roll of 0.0 → the entry's min.
  let offered = run(open, model.SetpieceLoot(list.repeat(0.0, 12)))
  state.get_outfit(offered.state, "rifle") |> should.equal(0)
  list.key_find(offered.loot, "rifle") |> should.equal(Ok(1))
  let looted = run(offered, model.TakeEverything)
  state.get_outfit(looted.state, "rifle") |> should.equal(1)
  state.get_outfit(looted.state, "bullets") |> should.equal(5)
  state.get_outfit(looted.state, "alien alloy") |> should.equal(1)
  // A scene's loot screen has its own buttons; the event stays.
  looted.active_event |> should.not_equal(option.None)
}

pub fn arriving_at_an_outpost_refills_water_and_spends_it_test() {
  let base = at_landmark(world.Outpost)
  let assert option.Some(exp0) = base.expedition
  let parched =
    model.Model(
      ..base,
      expedition: option.Some(
        world.Expedition(..exp0, vitals: world.Vitals(..exp0.vitals, water: 2)),
      ),
    )
  let after = run(parched, model.MoveEast)
  let assert option.Some(exp) = after.expedition
  exp.vitals.water |> should.equal(world.max_water(after.state))
  set.contains(exp.used_outposts, exp.pos) |> should.be_true
}

pub fn the_swamp_wanderer_grants_gastronome_for_a_charm_test() {
  let base = at_landmark(world.Swamp)
  let ready =
    model.Model(..base, state: state.set_outfit(base.state, "charm", 1))
  let start = run(ready, model.MoveEast)
  let cabin = run(start, ResolveEvent("enter", 0.5))
  let talked = run(cabin, ResolveEvent("talk", 0.5))
  state.has_perk(talked.state, "gastronome") |> should.be_true
  state.get_outfit(talked.state, "charm") |> should.equal(0)
  let assert option.Some(exp) = talked.expedition
  set.contains(exp.visited, exp.pos) |> should.be_true
}

// --- setpiece combat scenes (the house) -------------------------------------

/// Arrive at the house and take the `enter` branch the roll selects.
fn enter_house(roll: Float) -> model.Model {
  run(
    run(at_landmark(world.House), model.MoveEast),
    ResolveEvent("enter", roll),
  )
}

pub fn an_occupied_house_starts_the_squatter_fight_test() {
  // 0.7 lands in the third branch ({0.25: medicine, 0.5: supplies, 1: occupied}).
  let occupied = enter_house(0.7)
  let assert option.Some(cs) = occupied.combat
  cs.enemy.name |> should.equal("squatter")
  // The scene is still active — its buttons return once the fight is won.
  occupied.active_event |> should.not_equal(option.None)
}

pub fn winning_the_squatter_fight_drops_loot_and_keeps_the_scene_test() {
  let occupied = enter_house(0.7)
  // Two steel-sword blows (6 each) fell the 10-hp squatter.
  let won =
    occupied
    |> run(ResolveStrike("steel sword", 0.5))
    |> run(ResolveStrike("steel sword", 0.5))
  let assert option.Some(cs) = won.combat
  cs.won |> should.be_true
  // The squatter's loot waits in rows over the still-open fight; the scene
  // stays active beneath.
  let looting = run(won, CollectLoot([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
  looting.combat |> should.not_equal(option.None)
  looting.active_event |> should.not_equal(option.None)
  let done = run(looting, model.TakeEverything)
  state.get_outfit(done.state, "cured meat") |> should.equal(1)
  state.get_outfit(done.state, "cloth") |> should.equal(1)
  // A setpiece's take-everything never auto-leaves; the scene button does,
  // closing the fight on the way out.
  done.combat |> should.not_equal(option.None)
  let out = run(done, ResolveEvent("leave", 0.5))
  out.active_event |> should.equal(option.None)
  out.combat |> should.equal(option.None)
}

pub fn dying_in_the_house_closes_the_setpiece_test() {
  let base = at_landmark(world.House)
  let assert option.Some(exp0) = base.expedition
  let wounded =
    model.Model(
      ..base,
      expedition: option.Some(
        world.Expedition(..exp0, vitals: world.Vitals(..exp0.vitals, health: 1)),
      ),
    )
  let occupied = run(run(wounded, model.MoveEast), ResolveEvent("enter", 0.7))
  // The squatter's blow (3 dmg, 0.0 ≤ 0.8 hit) fells the 1-hp player.
  let dead = run(occupied, ResolveEnemyTurn(0.0))
  dead.location |> should.equal(model.Room)
  dead.combat |> should.equal(option.None)
  dead.active_event |> should.equal(option.None)
  dead.expedition |> should.equal(option.None)
}

pub fn the_house_well_refills_water_and_marks_visited_test() {
  let base = at_landmark(world.House)
  let assert option.Some(exp0) = base.expedition
  let parched =
    model.Model(
      ..base,
      expedition: option.Some(
        world.Expedition(..exp0, vitals: world.Vitals(..exp0.vitals, water: 3)),
      ),
    )
  // 0.3 lands in the second branch (supplies — the old well).
  let supplies = run(run(parched, model.MoveEast), ResolveEvent("enter", 0.3))
  let assert option.Some(exp) = supplies.expedition
  exp.vitals.water |> should.equal(world.max_water(supplies.state))
  set.contains(exp.visited, exp.pos) |> should.be_true
  // No fight — the well is a story scene.
  supplies.combat |> should.equal(option.None)
}

pub fn the_house_floorboards_hide_medicine_test() {
  // 0.1 lands in the first branch (medicine).
  let medicine = enter_house(0.1)
  medicine.combat |> should.equal(option.None)
  let offered = run(medicine, model.SetpieceLoot([0.0, 0.0]))
  let looted = run(offered, model.TakeAllLoot("medicine"))
  state.get_outfit(looted.state, "medicine") |> should.equal(2)
}

pub fn finding_the_ship_marks_it_and_records_the_way_off_test() {
  let after = run(at_landmark(world.Ship), model.MoveEast)
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("A Crashed Ship")
  // The landmark is dealt with, and the ship is recorded for the endgame.
  let assert option.Some(exp) = after.expedition
  set.contains(exp.visited, exp.pos) |> should.be_true
  state.get_game(after.state, "world.ship") |> should.equal(1)
}

pub fn clearing_the_iron_mine_flags_its_building_test() {
  let base = at_landmark(world.IronMine)
  let ready =
    model.Model(..base, state: state.set_outfit(base.state, "torch", 1))
  // Pay the torch to enter; the matriarch lunges.
  let fighting = run(run(ready, model.MoveEast), ResolveEvent("enter", 0.5))
  let assert option.Some(cs) = fighting.combat
  cs.enemy.name |> should.equal("beastly matriarch")
  // Two steel-sword blows fell the 10-hp matriarch; collect, then push on.
  let cleared =
    fighting
    |> run(ResolveStrike("steel sword", 0.5))
    |> run(ResolveStrike("steel sword", 0.5))
    |> run(CollectLoot(list.repeat(0.0, 6)))
    |> run(ResolveEvent("leave", 0.5))
  let assert option.Some(exp) = cleared.expedition
  set.contains(exp.mines_cleared, "iron mine") |> should.be_true
}

pub fn a_safe_return_grants_a_cleared_mine_building_test() {
  // Out in the world, one step east of the village, having cleared the coal mine.
  let exp =
    world.Expedition(
      pos: #(31, 30),
      map: dict.from_list([
        #(#(31, 30), world.Forest),
        #(#(30, 30), world.Village),
      ]),
      seen: set.new(),
      vitals: world.Vitals(10, 10, 0, 0, False, False),
      visited: set.new(),
      used_outposts: set.new(),
      mines_cleared: set.from_list(["coal mine"]),
    )
  let m =
    model.Model(
      ..model.init(),
      location: model.World,
      expedition: option.Some(exp),
    )
  // Step west onto the village — home safe.
  let home = run(m, model.MoveWest)
  home.location |> should.equal(model.Room)
  craft.building_count(home.state, "coal mine") |> should.equal(1)
}

pub fn delving_the_cave_clears_it_into_an_outpost_test() {
  let base = at_landmark(world.Cave)
  let ready =
    model.Model(..base, state: state.set_outfit(base.state, "torch", 2))
  let start = run(ready, model.MoveEast)
  // Enter (0.4 -> a2, the narrows); press on (0.3 -> b2, the torch dies);
  // relight (b2's continue costs a torch) into c1, the large beast.
  let at_c1 =
    start
    |> run(ResolveEvent("enter", 0.4))
    |> run(ResolveEvent("continue", 0.3))
    |> run(ResolveEvent("continue", 0.5))
  let assert option.Some(cs) = at_c1.combat
  cs.enemy.name |> should.equal("beast")
  cs.enemy.health |> should.equal(10)
  // Fell it with two steel-sword blows, take the cache (0.9 -> end2), which
  // clears the cave into a road-connected outpost.
  let cleared =
    at_c1
    |> run(ResolveStrike("steel sword", 0.5))
    |> run(ResolveStrike("steel sword", 0.5))
    |> run(CollectLoot([0.0, 0.0, 0.0, 0.0]))
    |> run(ResolveEvent("continue", 0.9))
  let assert option.Some(exp) = cleared.expedition
  world.tile_at(exp.map, exp.pos.0, exp.pos.1)
  |> should.equal(Ok(world.Outpost))
  // Two torches spent: entering, then relighting.
  state.get_outfit(cleared.state, "torch") |> should.equal(0)
}

pub fn clearing_the_town_turns_it_into_an_outpost_test() {
  let base = at_landmark(world.Town)
  let ready =
    model.Model(..base, state: state.set_outfit(base.state, "torch", 1))
  // Explore (0.5 -> a3, the clinic), torch the door (0.9 -> end5), which clears
  // the town — no fight on this branch.
  let cleared =
    ready
    |> run(model.MoveEast)
    |> run(ResolveEvent("enter", 0.5))
    |> run(ResolveEvent("enter", 0.9))
  cleared.combat |> should.equal(option.None)
  let assert option.Some(exp) = cleared.expedition
  world.tile_at(exp.map, exp.pos.0, exp.pos.1)
  |> should.equal(Ok(world.Outpost))
  state.get_outfit(cleared.state, "torch") |> should.equal(0)
}

pub fn a_parched_step_onto_the_village_is_a_safe_return_not_a_death_test() {
  // Bone dry and already thirsty, one step from home, having cleared the iron
  // mine. The village costs no supplies, so this is a safe return — not a death
  // that would forfeit the mine.
  let exp =
    world.Expedition(
      pos: #(31, 30),
      map: dict.from_list([
        #(#(31, 30), world.Forest),
        #(#(30, 30), world.Village),
      ]),
      seen: set.new(),
      vitals: world.Vitals(0, 1, 0, 0, False, True),
      visited: set.new(),
      used_outposts: set.new(),
      mines_cleared: set.from_list(["iron mine"]),
    )
  let m =
    model.Model(
      ..model.init(),
      location: model.World,
      expedition: option.Some(exp),
    )
  let home = run(m, model.MoveWest)
  home.location |> should.equal(model.Room)
  home.expedition |> should.equal(option.None)
  craft.building_count(home.state, "iron mine") |> should.equal(1)
}

pub fn a_disaster_scene_exacts_its_toll_on_scene_rng_test() {
  // A beast attack on a 20-strong village: its `on_load_rng` toll runs when the
  // model supplies the roll (`SceneRng`).
  let assert Ok(beast) =
    list.find(events.outside_events(), fn(e) { e.title == "A Beast Attack" })
  let m =
    model.Model(
      ..model.init(),
      location: model.Outside,
      state: state.set_game(state.new(), "population", 20),
      active_event: option.Some(model.ActiveEvent(beast, "start")),
    )
  // roll 0.0 → one villager falls.
  run(m, model.SceneRng(0.0))
  |> fn(after) { outside.population(after.state) }
  |> should.equal(19)
}

pub fn cool_check_summons_thieves_on_swollen_stores_test() {
  // Any store over 5000 once the world has been seen brings the skimming.
  let m =
    model.Model(
      ..model.init(),
      state: state.new()
        |> state.set_store("wood", 5001)
        |> state.set_feature("location.world", True),
    )
  run(m, model.CoolCheck(at: 1000)).state
  |> state.get_game("thieves")
  |> should.equal(1)
}

pub fn cool_check_delivers_a_due_delayed_return_test() {
  // A wanderer countdown at 1 fires on the next heartbeat: the cart returns.
  let m =
    model.Model(
      ..model.init(),
      state: state.set_game(state.new(), "delay.wanderer.wood100", 1),
    )
  let after = run(m, model.CoolCheck(at: 1000))
  state.get_store(after.state, "wood") |> should.equal(300)
  notifications.messages(after.notifications)
  |> list.contains(
    "the mysterious wanderer returns, cart piled high with wood.",
  )
  |> should.be_true
}

pub fn a_link_button_ends_the_event_test() {
  // The JS runs onClick, ends the event, and window.opens the link; the modal
  // must not linger.
  let assert Ok(penrose) =
    list.find(events.marketing_events(), fn(e) { e.title == "Penrose" })
  let m =
    model.Model(
      ..model.init(),
      active_event: option.Some(model.ActiveEvent(penrose, "start")),
    )
  let after = run(m, model.ResolveEvent("give in", 0.5))
  after.active_event |> should.equal(option.None)
  state.get_game(after.state, "marketing.penrose") |> should.equal(1)
}

// --- the ravaged battleship (executioner) -------------------------------------

/// An expedition standing in forest one step west of the battleship, with the
/// village on the map for the road-drawing fallback.
fn battleship_expedition() -> world.Expedition {
  let pos = #(world.radius + 3, world.radius)
  world.Expedition(
    pos: pos,
    map: dict.from_list([
      #(#(world.radius, world.radius), world.Village),
      #(pos, world.Forest),
      #(#(world.radius + 4, world.radius), world.Executioner),
    ]),
    seen: set.new(),
    vitals: world.Vitals(
      water: 10,
      health: 10,
      food_move: 0,
      water_move: 0,
      starvation: False,
      thirst: False,
    ),
    visited: set.new(),
    used_outposts: set.new(),
    mines_cleared: set.new(),
  )
}

fn battleship_model() -> model.Model {
  let base = model.init()
  model.Model(
    ..base,
    location: model.World,
    expedition: option.Some(battleship_expedition()),
  )
}

pub fn stepping_onto_the_battleship_opens_the_intro_test() {
  let after = run(battleship_model(), model.MoveEast)
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("A Ravaged Battleship")
  active.scene |> should.equal("start")
}

pub fn the_unsealed_battleship_opens_the_antechamber_test() {
  // With world.executioner set, stepping onto the ship reaches the elevators.
  let base = battleship_model()
  let m =
    model.Model(
      ..base,
      state: state.set_game(base.state, "world.executioner", 1),
    )
  let after = run(m, model.MoveEast)
  let assert option.Some(active) = after.active_event
  let assert Ok(start) = list.key_find(active.event.scenes, "start")
  let assert Ok(lift) = list.key_find(start.buttons, "engineering")
  lift.next |> should.equal(events.GotoEvent("executioner-engineering"))
}

pub fn riding_the_elevator_reaches_the_wing_test() {
  // Choose the engineering elevator: the wing event takes the stage.
  let assert Ok(hub) = executioner.event("executioner-antechamber")
  let m =
    model.Model(
      ..battleship_model(),
      active_event: option.Some(model.ActiveEvent(hub, "start")),
    )
  let after = run(m, model.ResolveEvent("engineering", 0.5))
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("Engineering Wing")
  active.scene |> should.equal("start")
}

pub fn an_elevator_to_nowhere_stays_put_test() {
  // The whole chain is ported now, so probe the runtime guard with a stub: a
  // GotoEvent to an unknown key stays put (the JS switchEvent's bare return).
  let ride =
    events.SceneButton(
      text: "descend",
      cost: [],
      reward: [],
      notification: option.None,
      available: option.None,
      on_click: option.None,
      link: option.None,
      effect: option.None,
      next: events.GotoEvent("no-such-event"),
    )
  let hub =
    events.Event(
      title: "hub",
      is_available: fn(_) { True },
      audio: option.None,
      scenes: [
        #(
          "start",
          events.Scene(
            text: ["a dark stairwell"],
            notification: option.None,
            reward: [],
            combat: False,
            blink: False,
            on_load: option.None,
            on_load_rng: option.None,
            setpiece: option.None,
            buttons: [#("down", ride)],
          ),
        ),
      ],
    )
  let m =
    model.Model(
      ..battleship_model(),
      active_event: option.Some(model.ActiveEvent(hub, "start")),
    )
  let after = run(m, model.ResolveEvent("down", 0.5))
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("hub")
  active.scene |> should.equal("start")
}

pub fn the_regenerative_machine_reknits_to_full_test() {
  // An alien alloy in the pack buys a full heal in the R&D lab.
  let assert Ok(wing) = executioner.event("executioner-engineering")
  let base = battleship_model()
  let assert option.Some(exp) = base.expedition
  let wounded =
    world.Expedition(..exp, vitals: world.Vitals(..exp.vitals, health: 2))
  let m =
    model.Model(
      ..base,
      state: state.set_outfit(base.state, "alien alloy", 1),
      expedition: option.Some(wounded),
      active_event: option.Some(model.ActiveEvent(wing, "4")),
    )
  let after = run(m, model.ResolveEvent("use", 0.5))
  let assert option.Some(healed) = after.expedition
  healed.vitals.health |> should.equal(world.max_health(after.state))
  state.get_outfit(after.state, "alien alloy") |> should.equal(0)
  let assert option.Some(active) = after.active_event
  active.scene |> should.equal("4-heal")
}

pub fn rushing_the_fire_costs_hit_points_test() {
  let assert Ok(wing) = executioner.event("executioner-engineering")
  let m =
    model.Model(
      ..battleship_model(),
      active_event: option.Some(model.ActiveEvent(wing, "1-3")),
    )
  // A 0.9 branch roll lands in the quiet robot bay (2-3b).
  let after = run(m, model.ResolveEvent("run", 0.9))
  let assert option.Some(exp) = after.expedition
  exp.vitals.health |> should.equal(0)
  let assert option.Some(active) = after.active_event
  active.scene |> should.equal("2-3b")
}

pub fn an_elevator_button_switches_events_test() {
  // A stub hub whose button rides GotoEvent — the JS nextEvent path.
  let ride =
    events.SceneButton(
      text: "ride",
      cost: [],
      reward: [],
      notification: option.None,
      available: option.None,
      on_click: option.None,
      link: option.None,
      effect: option.None,
      next: events.GotoEvent("executioner-intro"),
    )
  let hub =
    events.Event(
      title: "hub",
      is_available: fn(_) { True },
      audio: option.None,
      scenes: [
        #(
          "start",
          events.Scene(
            text: ["elevator doors"],
            notification: option.None,
            reward: [],
            combat: False,
            blink: False,
            on_load: option.None,
            on_load_rng: option.None,
            setpiece: option.None,
            buttons: [#("ride", ride)],
          ),
        ),
      ],
    )
  let m =
    model.Model(
      ..model.init(),
      active_event: option.Some(model.ActiveEvent(hub, "start")),
    )
  let after = run(m, model.ResolveEvent("ride", 0.5))
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("A Ravaged Battleship")
  active.scene |> should.equal("start")
}

pub fn taking_the_device_lays_a_road_and_sets_the_flag_test() {
  let assert Ok(intro) = executioner.event("executioner-intro")
  let base = battleship_model()
  let m =
    model.Model(
      ..base,
      active_event: option.Some(model.ActiveEvent(intro, "6")),
    )
  // The turret is down; continue ({1: '7'}) enters the device antechamber.
  let after = run(m, model.ResolveEvent("continue", 0.5))
  state.get_game(after.state, "world.executioner") |> should.equal(1)
  let assert option.Some(active) = after.active_event
  active.scene |> should.equal("7")
}

pub fn a_world_event_pays_costs_from_the_pack_test() {
  // Entering the battleship spends a carried torch; the home stores and the
  // identical store-room torches stay untouched.
  let base = battleship_model()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_store("torch", 3)
        |> state.set_outfit("torch", 1),
    )
  let entered = run(run(m, model.MoveEast), model.ResolveEvent("enter", 0.5))
  state.get_outfit(entered.state, "torch") |> should.equal(0)
  state.get_store(entered.state, "torch") |> should.equal(3)
  let assert option.Some(active) = entered.active_event
  active.scene |> should.equal("1")
}

pub fn a_world_event_can_cost_vitals_test() {
  // The engineering wing's fire: dousing it drinks the expedition's water.
  let douse =
    events.SceneButton(
      text: "extinguish",
      cost: [#("water", 4)],
      reward: [],
      notification: option.None,
      available: option.None,
      link: option.None,
      effect: option.None,
      on_click: option.None,
      next: events.End,
    )
  let fire =
    events.Event(
      title: "fire",
      is_available: fn(_) { True },
      audio: option.None,
      scenes: [
        #(
          "start",
          events.Scene(
            text: ["flames"],
            notification: option.None,
            reward: [],
            combat: False,
            blink: False,
            on_load: option.None,
            on_load_rng: option.None,
            setpiece: option.None,
            buttons: [#("water", douse)],
          ),
        ),
      ],
    )
  let m =
    model.Model(
      ..battleship_model(),
      active_event: option.Some(model.ActiveEvent(fire, "start")),
    )
  let after = run(m, model.ResolveEvent("water", 0.5))
  let assert option.Some(exp) = after.expedition
  exp.vitals.water |> should.equal(6)
  exp.vitals.health |> should.equal(10)
}

// --- boss specials and statuses ------------------------------------------------

/// A model mid-fight against a brute with the given specials armed.
fn special_fight(
  specials: List(combat.Special),
  last: combat.Status,
) -> model.Model {
  let brute =
    combat.Enemy(
      name: "brute",
      chara: "B",
      health: 60,
      damage: 3,
      hit: 0.8,
      attack_delay: 2.0,
      ranged: False,
      death_message: "",
      loot: [],
    )
  let cs =
    combat.CombatState(
      ..combat.begin_combat(brute, 10, 10),
      specials: specials,
      last_special: last,
    )
  model.Model(
    ..model.init(),
    location: model.World,
    expedition: option.Some(forest_expedition(3, 10)),
    combat: option.Some(cs),
  )
}

pub fn a_fixed_special_takes_hold_test() {
  let m =
    special_fight([combat.SetStatusEvery(5.0, combat.Shield)], combat.NoStatus)
  let after = run(m, model.SpecialFire(0))
  let assert option.Some(cs) = after.combat
  cs.enemy_status |> should.equal(combat.Shield)
}

pub fn a_won_fight_silences_the_specials_test() {
  let m =
    special_fight([combat.SetStatusEvery(5.0, combat.Shield)], combat.NoStatus)
  let assert option.Some(cs) = m.combat
  let m =
    model.Model(..m, combat: option.Some(combat.CombatState(..cs, won: True)))
  let after = run(m, model.SpecialFire(0))
  let assert option.Some(after_cs) = after.combat
  after_cs.enemy_status |> should.equal(combat.NoStatus)
}

pub fn the_rotation_never_repeats_itself_test() {
  // Last pick was shield; a 0.0 roll takes the first of the remaining two.
  let rotation =
    combat.RotateStatusEvery(7.0, [
      combat.Shield,
      combat.Enraged,
      combat.Meditation,
    ])
  let m = special_fight([rotation], combat.Shield)
  let after = run(m, model.ResolveSpecial(0, 0.0))
  let assert option.Some(cs) = after.combat
  cs.enemy_status |> should.equal(combat.Enraged)
  cs.last_special |> should.equal(combat.Enraged)
}

pub fn a_status_expires_on_its_clock_test() {
  let m = special_fight([], combat.NoStatus)
  let assert option.Some(cs) = m.combat
  let raging =
    model.Model(
      ..m,
      combat: option.Some(
        combat.CombatState(..cs, enemy_status: combat.Enraged),
      ),
    )
  let after = run(raging, model.StatusExpire)
  let assert option.Some(calm) = after.combat
  calm.enemy_status |> should.equal(combat.NoStatus)
}

pub fn poison_drips_each_tick_test() {
  let m = special_fight([], combat.NoStatus)
  let assert option.Some(cs) = m.combat
  let poisoned =
    model.Model(
      ..m,
      combat: option.Some(combat.CombatState(..cs, player_dot: 3)),
    )
  let after = run(poisoned, model.DotTick)
  let assert option.Some(dripping) = after.combat
  dripping.player_hp |> should.equal(7)
}

pub fn poison_can_finish_the_fight_test() {
  let m = special_fight([], combat.NoStatus)
  let assert option.Some(cs) = m.combat
  let nearly =
    model.Model(
      ..m,
      combat: option.Some(combat.CombatState(..cs, player_dot: 3, player_hp: 2)),
    )
  let after = run(nearly, model.DotTick)
  // The world fades: gear lost, back to the room.
  after.combat |> should.equal(option.None)
  after.expedition |> should.equal(option.None)
  after.location |> should.equal(model.Room)
}

// --- the dying blast (explosion) -------------------------------------------------

/// Mid-fight against a detonating brute: felled (won) with the blast pending.
fn exploding_fight(player_hp: Int) -> model.Model {
  let bomb =
    combat.Enemy(
      name: "unstable automaton",
      chara: "A",
      health: 100,
      damage: 10,
      hit: 0.7,
      attack_delay: 2.0,
      ranged: False,
      death_message: "",
      loot: [combat.LootEntry("glowstone blueprint", 1, 1, 1.0)],
    )
  let cs =
    combat.CombatState(
      ..combat.begin_combat(bomb, player_hp, 100),
      enemy_hp: 0,
      won: True,
      exploding: option.Some(30),
    )
  model.Model(
    ..model.init(),
    location: model.World,
    expedition: option.Some(forest_expedition(3, player_hp)),
    combat: option.Some(cs),
  )
}

pub fn surviving_the_blast_wins_the_fight_test() {
  let after = run(exploding_fight(50), model.ExplosionResolve)
  let assert option.Some(cs) = after.combat
  cs.player_hp |> should.equal(20)
}

pub fn the_blast_can_be_the_end_test() {
  let after = run(exploding_fight(30), model.ExplosionResolve)
  after.combat |> should.equal(option.None)
  after.expedition |> should.equal(option.None)
  after.location |> should.equal(model.Room)
}

pub fn a_felled_enemy_throws_no_blows_test() {
  // During the explosion window the dead enemy's timer must stay down.
  let m = exploding_fight(50)
  let after = run(m, model.ResolveEnemyTurn(0.0))
  let assert option.Some(cs) = after.combat
  cs.player_hp |> should.equal(50)
}

// --- safe-return commissions (M6) ------------------------------------------------

/// One step east of the village, ready to walk home.
fn homebound(s: state.State) -> model.Model {
  let exp =
    world.Expedition(
      pos: #(31, 30),
      map: dict.from_list([
        #(#(31, 30), world.Forest),
        #(#(30, 30), world.Village),
      ]),
      seen: set.new(),
      vitals: world.Vitals(10, 10, 0, 0, False, False),
      visited: set.new(),
      used_outposts: set.new(),
      mines_cleared: set.new(),
    )
  model.Model(
    ..model.init(),
    state: s,
    location: model.World,
    expedition: option.Some(exp),
  )
}

pub fn a_safe_return_commissions_the_old_starship_test() {
  let s = state.set_game(state.new(), "world.ship", 1)
  let home = run(homebound(s), model.MoveWest)
  state.has_feature(home.state, "location.ship") |> should.be_true
  state.get_game(home.state, "spaceShip.thrusters") |> should.equal(1)
  state.get_game(home.state, "spaceShip.hull") |> should.equal(0)
  model.unlocked_locations(home)
  |> list.contains(model.Ship)
  |> should.be_true
}

pub fn the_starship_is_commissioned_only_once_test() {
  // A reinforced hull survives later returns (the Ship.init guard).
  let s =
    state.new()
    |> state.set_game("world.ship", 1)
    |> state.set_feature("location.ship", True)
    |> state.set_game("spaceShip.hull", 5)
  let home = run(homebound(s), model.MoveWest)
  state.get_game(home.state, "spaceShip.hull") |> should.equal(5)
}

pub fn the_strange_device_opens_the_fabricator_test() {
  let s = state.set_game(state.new(), "world.executioner", 1)
  let home = run(homebound(s), model.MoveWest)
  state.has_feature(home.state, "location.fabricator") |> should.be_true
  notifications.messages(home.notifications)
  |> list.contains(
    "builder knows the strange device when she sees it. takes it for herself real quick. doesn’t ask where it came from.",
  )
  |> should.be_true
}

pub fn carried_blueprints_feed_the_data_port_test() {
  let s =
    state.new()
    |> state.set_outfit("hypo blueprint", 1)
    |> state.set_outfit("stim blueprint", 1)
  let home = run(homebound(s), model.MoveWest)
  state.get_character(home.state, "blueprints.hypo") |> should.equal(1)
  state.get_character(home.state, "blueprints.stim") |> should.equal(1)
  // Spent from the pack, never credited to the stores.
  state.get_outfit(home.state, "hypo blueprint") |> should.equal(0)
  state.get_store(home.state, "hypo blueprint") |> should.equal(0)
  notifications.messages(home.notifications)
  |> list.contains(
    "blueprints feed into the fabricator data port. possibilities grow.",
  )
  |> should.be_true
}

pub fn an_empty_pack_redeems_nothing_test() {
  let home = run(homebound(state.new()), model.MoveWest)
  notifications.messages(home.notifications)
  |> list.contains(
    "blueprints feed into the fabricator data port. possibilities grow.",
  )
  |> should.be_false
}

// --- the old starship -------------------------------------------------------------

fn at_the_ship() -> model.Model {
  let base = model.init()
  model.Model(
    ..base,
    location: model.Ship,
    state: state.new()
      |> state.set_feature("location.ship", True)
      |> state.set_game("spaceShip.thrusters", 1)
      |> state.set_game("spaceShip.hull", 1),
  )
}

pub fn the_first_liftoff_press_warns_test() {
  let after = run(at_the_ship(), model.CheckLiftoff)
  let assert option.Some(active) = after.active_event
  active.event.title |> should.equal("Ready to Leave?")
  // The button went on cooldown with the press.
  model.on_cooldown(model.Model(..after, now: 1), "liftoff")
  |> should.be_true
}

pub fn lingering_refunds_the_cooldown_test() {
  let warned = run(at_the_ship(), model.CheckLiftoff)
  let after = run(warned, model.ResolveEvent("wait", 0.5))
  after.active_event |> should.equal(option.None)
  model.on_cooldown(model.Model(..after, now: 1), "liftoff")
  |> should.be_false
}

pub fn flying_lifts_off_for_good_test() {
  let warned = run(at_the_ship(), model.CheckLiftoff)
  let after = run(warned, model.ResolveEvent("fly", 0.5))
  after.location |> should.equal(model.Space)
  ship.seen_warning(after.state) |> should.be_true
  after.active_event |> should.equal(option.None)
}

pub fn a_warned_pilot_lifts_off_directly_test() {
  let base = at_the_ship()
  let m =
    model.Model(
      ..base,
      state: state.set_game(base.state, "spaceShip.seenWarning", 1),
    )
  run(m, model.CheckLiftoff).location |> should.equal(model.Space)
}

pub fn arriving_at_the_wreck_notes_the_fleet_test() {
  let m = model.Model(..at_the_ship(), location: model.Room)
  let after = run(m, model.Navigate(to: model.Ship))
  notifications.messages(after.notifications)
  |> list.contains(
    "somewhere above the debris cloud, the wanderer fleet hovers. been on this rock too long.",
  )
  |> should.be_true
}

// --- the ascent ---------------------------------------------------------------

fn lifting_off() -> model.Model {
  let base = model.init()
  let m =
    model.Model(
      ..base,
      state: base.state
        |> state.set_game("spaceShip.hull", 2)
        |> state.set_game("spaceShip.thrusters", 1),
    )
  run(m, model.Navigate(to: model.Space))
}

pub fn arriving_in_space_begins_the_flight_test() {
  let flying = lifting_off()
  let assert option.Some(flight) = flying.space
  flight.hull |> should.equal(2)
  flight.x |> should.equal(350.0)
}

pub fn a_flight_frame_moves_the_held_ship_test() {
  let flying = lifting_off()
  let steering = run(flying, model.KeyDown("ArrowLeft"))
  let after = run(steering, model.FlightFrame(run: 1, at: 1033))
  let assert option.Some(flight) = after.space
  flight.x |> should.equal(346.0)
  after.flight_last_move |> should.equal(1033)
}

pub fn releasing_the_key_stops_the_ship_test() {
  let flying = lifting_off()
  let coasting =
    flying
    |> run(model.KeyDown("a"))
    |> run(model.KeyUp("a"))
    |> run(model.FlightFrame(run: 1, at: 1033))
  let assert option.Some(flight) = coasting.space
  flight.x |> should.equal(350.0)
}

pub fn a_spent_hull_crashes_back_to_the_ship_test() {
  // A rock within collision range and one point of hull: the frame ends the flight.
  let flying = lifting_off()
  let assert option.Some(flight) = flying.space
  let doomed =
    model.Model(
      ..flying,
      space: option.Some(
        space.Flight(..flight, hull: 1, y: 375.0, asteroids: [
          space.Asteroid(chara: "#", x: 348.0, spawned_at: 0, duration: 1000),
        ]),
      ),
      flight_last_move: 467,
    )
  let after = run(doomed, model.FlightFrame(run: 1, at: 500))
  after.space |> should.equal(option.None)
  after.location |> should.equal(model.Ship)
  // The lift-off button cools again.
  model.on_cooldown(model.Model(..after, now: 1), "liftoff")
  |> should.be_true
}

pub fn the_climb_counts_kilometres_test() {
  let flying = lifting_off()
  let after = run(flying, model.ClimbTick(run: 1))
  let assert option.Some(flight) = after.space
  flight.altitude |> should.equal(1)
}

pub fn a_wave_falls_from_its_rolls_test() {
  let flying = lifting_off()
  let after =
    run(flying, model.SpawnWave(run: 1, at: 2000, rolls: [0.1, 0.5, 0.0]))
  let assert option.Some(flight) = after.space
  flight.asteroids |> list.length |> should.equal(1)
}

pub fn surviving_the_fade_wins_test() {
  let flying = lifting_off()
  let after = run(flying, model.AscentComplete(run: 1))
  let assert option.Some(flight) = after.space
  flight.done |> should.be_true
  // A quiet flight spawns and climbs no more.
  let still = run(after, model.ClimbTick(run: 1))
  let assert option.Some(done_flight) = still.space
  done_flight.altitude |> should.equal(0)
}

pub fn a_crashed_runs_stragglers_cannot_touch_the_next_flight_test() {
  // Lift off twice (run 2); run 1's leftover 60s fade and climb must do
  // nothing to the new flight.
  let second =
    lifting_off()
    |> run(model.Navigate(to: model.Ship))
    |> run(model.Navigate(to: model.Space))
  second.flight_run |> should.equal(2)
  let after =
    second
    |> run(model.AscentComplete(run: 1))
    |> run(model.ClimbTick(run: 1))
  let assert option.Some(flight) = after.space
  flight.done |> should.be_false
  flight.altitude |> should.equal(0)
  // The live run's clocks still work.
  let won = run(after, model.AscentComplete(run: 2))
  let assert option.Some(done_flight) = won.space
  done_flight.done |> should.be_true
}

// --- the ending ---------------------------------------------------------------

pub fn winning_with_the_beacon_begins_the_outro_test() {
  let base = lifting_off()
  let won =
    model.Model(..base, state: state.set_store(base.state, "fleet beacon", 1))
    |> run(model.GameWon([0.5]))
  let assert option.Some(model.Outro(paragraphs: 0, this_score: this, ..)) =
    won.ending
  // The beacon (500) plus the two-point hull (100).
  this |> should.equal(600)
}

pub fn winning_without_the_beacon_goes_straight_to_the_scores_test() {
  let won = run(lifting_off(), model.GameWon([0.5]))
  let assert option.Some(model.EndOptions(..)) = won.ending
}

pub fn the_outro_paces_its_paragraphs_test() {
  let base = lifting_off()
  let telling =
    model.Model(..base, ending: option.Some(model.Outro(0, 500, 500)))
  let after = run(run(telling, model.OutroStep), model.OutroStep)
  let assert option.Some(model.Outro(paragraphs: 2, ..)) = after.ending
}

pub fn waiting_brings_the_scores_test() {
  let base = lifting_off()
  let told = model.Model(..base, ending: option.Some(model.Outro(5, 500, 1200)))
  let after = run(told, model.EndingWait)
  after.ending
  |> should.equal(option.Some(model.EndOptions(500, 1200)))
}

pub fn scene_loot_arms_the_take_everything_cooldown_test() {
  // Cache scenes honour _LEAVE_COOLDOWN like won fights (CodeRabbit on #111).
  let open = run(at_landmark(world.Battlefield), model.MoveEast)
  let offered = run(open, model.SetpieceLoot(list.repeat(0.0, 12)))
  model.on_cooldown(
    model.Model(..offered, now: offered.now + 1),
    "loot_take_et",
  )
  |> should.be_true
}

// --- the title blink ------------------------------------------------------------

pub fn a_blinking_event_starts_the_title_flashing_test() {
  // The Nomad's start scene blinks.
  let started = run(room_with_fur(10, 1000), TriggerEvent(0.0, 0.0))
  let assert option.Some(active) = started.active_event
  active.event.title |> should.equal("The Nomad")
  started.blinking |> should.be_true
}

pub fn ending_the_event_stops_the_blink_test() {
  let started = run(room_with_fur(10, 1000), TriggerEvent(0.0, 0.0))
  let done = run(started, ResolveEvent("goodbye", 0.5))
  done.active_event |> should.equal(option.None)
  done.blinking |> should.be_false
}

pub fn the_shady_builder_keeps_quiet_test() {
  // The one room event whose start does not blink — preserved verbatim.
  let assert Ok(shady) =
    list.find(events.room_events(), fn(e) { e.title == "The Shady Builder" })
  let assert Ok(start) = list.key_find(shady.scenes, "start")
  start.blink |> should.be_false
  // And every disaster's start does.
  events.outside_events()
  |> list.each(fn(e) {
    let assert Ok(start) = list.key_find(e.scenes, "start")
    start.blink |> should.be_true
  })
}
