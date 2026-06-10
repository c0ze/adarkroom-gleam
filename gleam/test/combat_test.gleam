import adarkroom/combat
import adarkroom/state
import gleam/list
import gleeunit/should

// --- weapons table ----------------------------------------------------------

pub fn fists_is_the_unarmed_baseline_test() {
  let assert Ok(w) = combat.get_weapon("fists")
  w.verb |> should.equal("punch")
  w.kind |> should.equal(combat.Unarmed)
  w.damage |> should.equal(combat.Hit(1))
  w.cooldown |> should.equal(2)
  w.cost |> should.equal([])
}

pub fn rifle_costs_a_bullet_per_shot_test() {
  let assert Ok(w) = combat.get_weapon("rifle")
  w.kind |> should.equal(combat.Ranged)
  w.damage |> should.equal(combat.Hit(5))
  w.cooldown |> should.equal(1)
  w.cost |> should.equal([#("bullets", 1)])
}

pub fn bolas_deals_a_stun_not_damage_test() {
  let assert Ok(w) = combat.get_weapon("bolas")
  w.damage |> should.equal(combat.Stun)
  w.cost |> should.equal([#("bolas", 1)])
}

pub fn table_has_all_twelve_weapons_test() {
  combat.weapons() |> list.length |> should.equal(12)
  combat.get_weapon("steel sword") |> should.be_ok
  combat.get_weapon("laser rifle") |> should.be_ok
  combat.get_weapon("energy blade") |> should.be_ok
  combat.get_weapon("disruptor") |> should.be_ok
  combat.get_weapon("plasma rifle") |> should.be_ok
}

pub fn unknown_weapon_is_an_error_test() {
  combat.get_weapon("railgun") |> should.equal(Error(Nil))
}

// --- hit chance -------------------------------------------------------------

pub fn base_hit_chance_is_four_in_five_test() {
  combat.hit_chance(state.new()) |> should.equal(0.8)
}

pub fn precise_perk_adds_ten_percent_test() {
  state.new()
  |> state.add_perk("precise")
  |> combat.hit_chance
  |> should.equal(0.9)
}

// --- player attack ----------------------------------------------------------

fn weapon(name: String) -> combat.Weapon {
  let assert Ok(w) = combat.get_weapon(name)
  w
}

pub fn a_roll_above_hit_chance_misses_test() {
  // base hit chance 0.8; a 0.81 roll whiffs.
  combat.player_attack(weapon("fists"), state.new(), 0.81)
  |> should.equal(combat.Miss)
}

pub fn a_landed_punch_deals_one_test() {
  combat.player_attack(weapon("fists"), state.new(), 0.5)
  |> should.equal(combat.Damage(1))
}

pub fn boxer_doubles_unarmed_damage_test() {
  state.new()
  |> state.add_perk("boxer")
  |> combat.player_attack(weapon("fists"), _, 0.5)
  |> should.equal(combat.Damage(2))
}

pub fn martial_artist_triples_unarmed_damage_test() {
  state.new()
  |> state.add_perk("martial artist")
  |> combat.player_attack(weapon("fists"), _, 0.5)
  |> should.equal(combat.Damage(3))
}

pub fn unarmed_perks_stack_multiplicatively_test() {
  // 1 * 2 (boxer) * 3 (martial artist) * 2 (unarmed master) = 12
  state.new()
  |> state.add_perk("boxer")
  |> state.add_perk("martial artist")
  |> state.add_perk("unarmed master")
  |> combat.player_attack(weapon("fists"), _, 0.5)
  |> should.equal(combat.Damage(12))
}

pub fn barbarian_adds_half_to_melee_floored_test() {
  let s = state.new() |> state.add_perk("barbarian")
  // iron sword 4 -> floor(6.0) = 6
  combat.player_attack(weapon("iron sword"), s, 0.5)
  |> should.equal(combat.Damage(6))
  // bone spear 2 -> floor(3.0) = 3
  combat.player_attack(weapon("bone spear"), s, 0.5)
  |> should.equal(combat.Damage(3))
}

pub fn barbarian_leaves_ranged_alone_test() {
  state.new()
  |> state.add_perk("barbarian")
  |> combat.player_attack(weapon("rifle"), _, 0.5)
  |> should.equal(combat.Damage(5))
}

pub fn boxer_leaves_melee_alone_test() {
  state.new()
  |> state.add_perk("boxer")
  |> combat.player_attack(weapon("iron sword"), _, 0.5)
  |> should.equal(combat.Damage(4))
}

pub fn a_landed_stun_weapon_stuns_test() {
  combat.player_attack(weapon("bolas"), state.new(), 0.5)
  |> should.equal(combat.StunHit)
}

pub fn a_missed_stun_weapon_does_nothing_test() {
  combat.player_attack(weapon("bolas"), state.new(), 0.9)
  |> should.equal(combat.Miss)
}

// --- enemy attack -----------------------------------------------------------

pub fn enemy_lands_its_scene_damage_test() {
  combat.enemy_attack(0.8, 3, state.new(), 0.5)
  |> should.equal(combat.Damage(3))
}

pub fn enemy_misses_above_its_hit_chance_test() {
  combat.enemy_attack(0.8, 3, state.new(), 0.85)
  |> should.equal(combat.Miss)
}

pub fn evasive_perk_shrinks_enemy_hit_chance_test() {
  // scene hit 0.8 -> 0.64 with evasive; a 0.7 roll now whiffs.
  let s = state.new() |> state.add_perk("evasive")
  combat.enemy_attack(0.8, 3, s, 0.7) |> should.equal(combat.Miss)
  // without the perk, 0.7 would have connected.
  combat.enemy_attack(0.8, 3, state.new(), 0.7)
  |> should.equal(combat.Damage(3))
}

// --- applying damage to a fighter's HP --------------------------------------

pub fn damage_subtracts_from_hp_test() {
  combat.apply_damage(5, 5, 2) |> should.equal(3)
}

pub fn damage_never_drops_below_zero_test() {
  combat.apply_damage(2, 5, 8) |> should.equal(0)
}

// --- loot --------------------------------------------------------------------

pub fn loot_is_skipped_when_the_chance_roll_fails_test() {
  // chance 0.8; a 0.9 roll fails (JS `<`), so no drop and no quantity roll.
  combat.roll_loot([combat.LootEntry("fur", 1, 3, 0.8)], [0.9])
  |> should.equal([])
}

pub fn loot_quantity_uses_the_floor_formula_test() {
  // floor(0.5 * (3 - 1)) + 1 = 2
  combat.roll_loot([combat.LootEntry("fur", 1, 3, 1.0)], [0.0, 0.5])
  |> should.equal([#("fur", 2)])
}

pub fn loot_max_is_exclusive_like_the_original_test() {
  // floor(0.999 * 2) + 1 = 2 — a max of 3 never actually drops 3.
  combat.roll_loot([combat.LootEntry("fur", 1, 3, 1.0)], [0.0, 0.999])
  |> should.equal([#("fur", 2)])
}

pub fn loot_with_equal_min_and_max_is_fixed_test() {
  combat.roll_loot([combat.LootEntry("teeth", 2, 2, 1.0)], [0.0, 0.99])
  |> should.equal([#("teeth", 2)])
}

pub fn loot_only_spends_a_quantity_roll_on_a_hit_test() {
  // First entry's chance fails (no qty roll consumed); second succeeds.
  combat.roll_loot(
    [combat.LootEntry("a", 1, 3, 0.8), combat.LootEntry("b", 1, 3, 1.0)],
    [0.9, 0.0, 0.5],
  )
  |> should.equal([#("b", 2)])
}

// --- fight trigger (while walking the world) --------------------------------

pub fn no_fight_within_the_delay_window_test() {
  // FIGHT_DELAY is 3: the counter must exceed 3 before a fight can start.
  // move 1 — far too early even with a guaranteed roll.
  combat.check_fight(state.new(), 0, 0.0) |> should.equal(#(False, 1))
}

pub fn the_delay_boundary_blocks_the_fourth_step_test() {
  // counter 2 -> 3, still not > 3, so no fight despite a 0.0 roll.
  combat.check_fight(state.new(), 2, 0.0) |> should.equal(#(False, 3))
}

pub fn a_fight_starts_past_the_delay_on_a_low_roll_test() {
  // counter 3 -> 4 (> 3); 0.1 < 0.2 chance, so a fight starts and resets.
  combat.check_fight(state.new(), 3, 0.1) |> should.equal(#(True, 0))
}

pub fn a_high_roll_past_the_delay_keeps_walking_test() {
  combat.check_fight(state.new(), 3, 0.5) |> should.equal(#(False, 4))
}

pub fn stealthy_perk_halves_the_fight_chance_test() {
  let s = state.new() |> state.add_perk("stealthy")
  // 0.15 would trigger at the normal 0.2 chance, but stealthy drops it to 0.1.
  combat.check_fight(s, 3, 0.15) |> should.equal(#(False, 4))
  combat.check_fight(state.new(), 3, 0.15) |> should.equal(#(True, 0))
}

// --- which weapons a fight offers -------------------------------------------

pub fn a_melee_weapon_is_always_usable_test() {
  combat.can_attack_with(weapon("iron sword"), state.new())
  |> should.equal(True)
}

pub fn a_gun_needs_ammo_to_be_usable_test() {
  combat.can_attack_with(weapon("rifle"), state.new()) |> should.equal(False)
  state.new()
  |> state.set_outfit("bullets", 1)
  |> combat.can_attack_with(weapon("rifle"), _)
  |> should.equal(True)
}

pub fn a_stun_weapon_is_not_a_usable_damage_dealer_test() {
  combat.can_attack_with(weapon("bolas"), state.new()) |> should.equal(False)
}

pub fn bare_handed_when_carrying_nothing_test() {
  combat.attack_options(state.new()) |> should.equal(["fists"])
}

pub fn a_carried_weapon_is_offered_test() {
  state.new()
  |> state.set_outfit("iron sword", 1)
  |> combat.attack_options
  |> should.equal(["iron sword"])
}

pub fn fists_fall_back_when_the_carried_gun_has_no_ammo_test() {
  // Owns a rifle but no bullets: the rifle still shows, plus fists to fight on.
  state.new()
  |> state.set_outfit("rifle", 1)
  |> combat.attack_options
  |> should.equal(["fists", "rifle"])
}

pub fn offered_weapons_keep_table_order_test() {
  state.new()
  |> state.set_outfit("bayonet", 1)
  |> state.set_outfit("iron sword", 1)
  |> combat.attack_options
  |> should.equal(["iron sword", "bayonet"])
}

// --- a fight in progress ----------------------------------------------------

fn beast() -> combat.Enemy {
  combat.Enemy(
    name: "snarling beast",
    chara: "R",
    health: 5,
    damage: 1,
    hit: 0.8,
    attack_delay: 1.0,
    ranged: False,
    death_message: "the snarling beast is dead",
    loot: [combat.LootEntry("fur", 1, 3, 1.0)],
  )
}

fn weapon_named(name: String) -> combat.Weapon {
  let assert Ok(w) = combat.get_weapon(name)
  w
}

pub fn a_fight_starts_with_both_fighters_at_their_health_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  cs.enemy_hp |> should.equal(5)
  cs.player_hp |> should.equal(10)
  cs.won |> should.equal(False)
  cs.enemy_stunned |> should.equal(False)
}

pub fn a_landed_strike_wounds_the_enemy_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  // iron sword 4; a 0.5 roll lands (<= 0.8): 5 - 4 = 1.
  let after =
    combat.player_strike(cs, weapon_named("iron sword"), state.new(), 0.5)
  after.enemy_hp |> should.equal(1)
  after.won |> should.equal(False)
}

pub fn a_missed_strike_leaves_the_enemy_unhurt_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  let after = combat.player_strike(cs, weapon_named("fists"), state.new(), 0.9)
  after.enemy_hp |> should.equal(5)
}

pub fn killing_the_enemy_wins_the_fight_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  // steel sword 6 > 5 health.
  let after =
    combat.player_strike(cs, weapon_named("steel sword"), state.new(), 0.5)
  after.enemy_hp |> should.equal(0)
  after.won |> should.equal(True)
}

pub fn a_stun_weapon_makes_the_enemy_skip_its_next_attack_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  let stunned =
    combat.player_strike(cs, weapon_named("bolas"), state.new(), 0.5)
  stunned.enemy_stunned |> should.equal(True)
  stunned.enemy_hp |> should.equal(5)
  // The stunned enemy can't connect, and the stun is spent.
  let after = combat.enemy_strike(stunned, state.new(), 0.0)
  after.player_hp |> should.equal(10)
  after.enemy_stunned |> should.equal(False)
}

pub fn an_enemy_strike_wounds_the_player_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  // enemy damage 1, hit 0.8; a 0.5 roll lands: 10 - 1 = 9.
  let after = combat.enemy_strike(cs, state.new(), 0.5)
  after.player_hp |> should.equal(9)
}

pub fn an_enemy_miss_spares_the_player_test() {
  let cs = combat.begin_combat(beast(), 10, 10)
  let after = combat.enemy_strike(cs, state.new(), 0.9)
  after.player_hp |> should.equal(10)
}
