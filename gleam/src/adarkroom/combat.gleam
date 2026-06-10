//// The combat engine: weapons, hit chance, attack resolution and loot.
////
//// This is the pure core ported faithfully from `world.js` (`getDamage`,
//// `getHitChance`, `checkFight`) and `events.js` (player/enemy attack, loot).
//// The combat *experience* (buttons, timers, animations) is layered on top of
//// the event/scene runtime; here we keep only the testable formulas.

import adarkroom/state
import gleam/float
import gleam/int
import gleam/list

/// How a weapon is wielded — drives perk bonuses.
pub type WeaponType {
  Unarmed
  Melee
  Ranged
}

/// A weapon either deals numeric damage or stuns the target.
pub type Damage {
  Hit(Int)
  Stun
}

pub type Weapon {
  Weapon(
    name: String,
    verb: String,
    kind: WeaponType,
    damage: Damage,
    cooldown: Int,
    cost: List(#(String, Int)),
  )
}

/// The full weapons table, in display order (matches `World.Weapons`).
pub fn weapons() -> List(Weapon) {
  [
    Weapon("fists", "punch", Unarmed, Hit(1), 2, []),
    Weapon("bone spear", "stab", Melee, Hit(2), 2, []),
    Weapon("iron sword", "swing", Melee, Hit(4), 2, []),
    Weapon("steel sword", "slash", Melee, Hit(6), 2, []),
    Weapon("bayonet", "thrust", Melee, Hit(8), 2, []),
    Weapon("rifle", "shoot", Ranged, Hit(5), 1, [#("bullets", 1)]),
    Weapon("laser rifle", "blast", Ranged, Hit(8), 1, [#("energy cell", 1)]),
    Weapon("grenade", "lob", Ranged, Hit(15), 5, [#("grenade", 1)]),
    Weapon("bolas", "tangle", Ranged, Stun, 15, [#("bolas", 1)]),
    Weapon("plasma rifle", "disintegrate", Ranged, Hit(12), 1, [
      #("energy cell", 1),
    ]),
    Weapon("energy blade", "slice", Melee, Hit(10), 2, []),
    Weapon("disruptor", "stun", Ranged, Stun, 15, []),
  ]
}

/// Look up a weapon by name.
pub fn get_weapon(name: String) -> Result(Weapon, Nil) {
  list.find(weapons(), fn(w) { w.name == name })
}

// --- hit chance -------------------------------------------------------------

const base_hit_chance = 0.8

/// The player's chance to land a blow. The `precise` perk adds 10%.
pub fn hit_chance(s: state.State) -> Float {
  case state.has_perk(s, "precise") {
    True -> base_hit_chance +. 0.1
    False -> base_hit_chance
  }
}

// --- player attack ----------------------------------------------------------

/// The outcome of a single swing.
pub type AttackResult {
  Miss
  Damage(Int)
  StunHit
}

/// Resolve a player attack. `hit_roll` is a uniform sample in `[0, 1)`; the
/// blow lands when it falls within the hit chance (JS uses `<=`). Perks then
/// scale numeric damage by weapon type.
pub fn player_attack(
  weapon: Weapon,
  s: state.State,
  hit_roll: Float,
) -> AttackResult {
  case hit_roll <=. hit_chance(s) {
    False -> Miss
    True ->
      case weapon.damage {
        Stun -> StunHit
        Hit(base) -> Damage(apply_perks(weapon.kind, base, s))
      }
  }
}

/// Apply numeric damage to a fighter's HP, clamped to `[0, max_hp]`.
pub fn apply_damage(hp: Int, max_hp: Int, dmg: Int) -> Int {
  int.min(max_hp, int.max(0, hp - dmg))
}

/// Resolve an enemy attack. The `evasive` perk shrinks the enemy's hit chance
/// to 80% of the scene value.
pub fn enemy_attack(
  scene_hit: Float,
  scene_damage: Int,
  s: state.State,
  hit_roll: Float,
) -> AttackResult {
  let to_hit = case state.has_perk(s, "evasive") {
    True -> scene_hit *. 0.8
    False -> scene_hit
  }
  case hit_roll <=. to_hit {
    True -> Damage(scene_damage)
    False -> Miss
  }
}

fn apply_perks(kind: WeaponType, base: Int, s: state.State) -> Int {
  case kind {
    Unarmed -> {
      let d = case state.has_perk(s, "boxer") {
        True -> base * 2
        False -> base
      }
      let d = case state.has_perk(s, "martial artist") {
        True -> d * 3
        False -> d
      }
      case state.has_perk(s, "unarmed master") {
        True -> d * 2
        False -> d
      }
    }
    Melee ->
      case state.has_perk(s, "barbarian") {
        // floor(base * 1.5); base is always even for melee weapons.
        True -> base * 3 / 2
        False -> base
      }
    Ranged -> base
  }
}

// --- which weapons a fight offers -------------------------------------------

/// Whether a weapon can actually be swung right now: it must deal positive
/// numeric damage (stun weapons don't count) and the outfit must hold enough
/// ammo for one use.
pub fn can_attack_with(weapon: Weapon, s: state.State) -> Bool {
  case weapon.damage {
    Stun -> False
    Hit(n) ->
      n > 0 && list.all(weapon.cost, fn(c) { state.get_outfit(s, c.0) >= c.1 })
  }
}

/// The weapons a fight should offer, in table order: every weapon carried in
/// the outfit, with `fists` prepended as a fallback when none of them is a
/// usable damage-dealer.
pub fn attack_options(s: state.State) -> List(String) {
  let owned = list.filter(weapons(), fn(w) { state.get_outfit(s, w.name) > 0 })
  let names = list.map(owned, fn(w) { w.name })
  case list.any(owned, fn(w) { can_attack_with(w, s) }) {
    True -> names
    False -> ["fists", ..names]
  }
}

// --- fight trigger ----------------------------------------------------------

const fight_chance = 0.2

const fight_delay = 3

/// Advance the "moves since last fight" counter and decide whether a random
/// encounter starts. Returns `#(fight_started, new_counter)`. A fight can only
/// start once the counter exceeds `fight_delay`; the `stealthy` perk halves the
/// per-step chance. When a fight starts the counter resets to 0.
pub fn check_fight(s: state.State, fight_move: Int, roll: Float) -> #(Bool, Int) {
  let moved = fight_move + 1
  case moved > fight_delay {
    False -> #(False, moved)
    True -> {
      let chance = case state.has_perk(s, "stealthy") {
        True -> fight_chance *. 0.5
        False -> fight_chance
      }
      case roll <. chance {
        True -> #(True, 0)
        False -> #(False, moved)
      }
    }
  }
}

// --- loot --------------------------------------------------------------------

/// One row of a loot table: drop `min..max` of `name` with probability `chance`.
pub type LootEntry {
  LootEntry(name: String, min: Int, max: Int, chance: Float)
}

/// Roll a loot table against a list of `[0, 1)` samples, threaded exactly as the
/// original does: one chance roll per entry, plus a quantity roll only when the
/// drop succeeds. Quantity is `floor(roll * (max - min)) + min`, which
/// (faithfully) treats `max` as exclusive.
pub fn roll_loot(
  entries: List(LootEntry),
  rolls: List(Float),
) -> List(#(String, Int)) {
  do_roll_loot(entries, rolls, [])
}

fn do_roll_loot(
  entries: List(LootEntry),
  rolls: List(Float),
  acc: List(#(String, Int)),
) -> List(#(String, Int)) {
  case entries {
    [] -> list.reverse(acc)
    [entry, ..rest] ->
      case rolls {
        [] -> list.reverse(acc)
        [chance_roll, ..rest_rolls] ->
          case chance_roll <. entry.chance {
            False -> do_roll_loot(rest, rest_rolls, acc)
            True ->
              case rest_rolls {
                [] -> list.reverse(acc)
                [qty_roll, ..tail] -> {
                  let span = int.to_float(entry.max - entry.min)
                  let qty = float.truncate(qty_roll *. span) + entry.min
                  do_roll_loot(rest, tail, [#(entry.name, qty), ..acc])
                }
              }
          }
      }
  }
}

// --- a fight in progress ----------------------------------------------------

/// An enemy in a fight — the combat half of an encounter's scene.
pub type Enemy {
  Enemy(
    name: String,
    chara: String,
    health: Int,
    damage: Int,
    hit: Float,
    attack_delay: Float,
    ranged: Bool,
    death_message: String,
    loot: List(LootEntry),
  )
}

/// A fighter's combat status (`Events.setStatus`) — one at a time. The
/// executioner's bosses take these via their specials; the player-side
/// statuses (the shield button, the stim boost) arrive with their Fabricator
/// items.
pub type Status {
  NoStatus
  /// Absorbs the next hit as healing, then breaks (one hit per shield).
  Shield
  /// Attacks every half second while it lasts (the cadence is the model's
  /// job; the strike itself is unchanged).
  Enraged
  /// Sits attacks out; damage dealt to it banks, and is repaid as one
  /// guaranteed blow when the trance ends.
  Meditation
  /// One-hit buff: the next landed blow leaves poison dripping.
  Venomous
  /// One-hit buff: the next landed blow strikes fourfold.
  Energised
}

/// `ENERGISE_MULTIPLIER` — an energised blow strikes fourfold.
pub const energise_multiplier = 4

/// `ENRAGE_DURATION` — how long the half-second fury lasts.
pub const enrage_duration_ms = 4000

/// `MEDITATE_DURATION` — how long the trance lasts.
pub const meditate_duration_ms = 5000

/// `DOT_TICK` — how often armed poison drips.
pub const dot_tick_ms = 1000

/// A boss's recurring special (`scene.specials`): every `delay` seconds it
/// takes a status.
pub type Special {
  /// Always the same status (the wings' bosses).
  SetStatusEvery(delay: Float, status: Status)
  /// One of `options` at random, never the same twice running (the command
  /// deck's rotation; `Events._lastSpecial`).
  RotateStatusEvery(delay: Float, options: List(Status))
}

/// A fight in progress.
pub type CombatState {
  CombatState(
    enemy: Enemy,
    enemy_hp: Int,
    player_hp: Int,
    player_max: Int,
    won: Bool,
    enemy_stunned: Bool,
    /// The enemy's active status, set by its specials or an `atHealth` trigger.
    enemy_status: Status,
    /// Damage banked while the enemy meditates (`Events._meditateDmg`).
    meditate_bank: Int,
    /// Poison dripping on the player: damage per tick, `0` when unpoisoned.
    player_dot: Int,
    /// `atHealth` triggers: crossing a threshold from above takes the status.
    at_health: List(#(Int, Status)),
    /// The enemy's recurring specials; the model runs their timers.
    specials: List(Special),
    /// The rotation's previous pick, never repeated (`Events._lastSpecial`).
    last_special: Status,
  )
}

/// Start a fight: the enemy at full health, the player at the given health.
pub fn begin_combat(
  enemy: Enemy,
  player_hp: Int,
  player_max: Int,
) -> CombatState {
  CombatState(
    enemy:,
    enemy_hp: enemy.health,
    player_hp:,
    player_max:,
    won: False,
    enemy_stunned: False,
    enemy_status: NoStatus,
    meditate_bank: 0,
    player_dot: 0,
    at_health: [],
    specials: [],
    last_special: NoStatus,
  )
}

/// Seconds between enemy attacks right now: an enraged enemy swings every half
/// second (`startEnemyAttacks(0.5)`).
pub fn effective_attack_delay(cs: CombatState) -> Float {
  case cs.enemy_status {
    Enraged -> 0.5
    _ -> cs.enemy.attack_delay
  }
}

/// Resolve a player attack on the enemy. A stun makes it skip its next turn
/// (and leaves any shield intact — only a numeric hit breaks one); numeric
/// damage lowers its HP and may win the fight.
pub fn player_strike(
  cs: CombatState,
  weapon: Weapon,
  s: state.State,
  hit_roll: Float,
) -> CombatState {
  case player_attack(weapon, s, hit_roll) {
    Miss -> cs
    StunHit -> CombatState(..cs, enemy_stunned: True)
    Damage(d) -> strike_enemy(cs, d)
  }
}

/// Land a blow on the enemy, honouring its status: a meditating enemy banks
/// the damage instead of taking it; a shielded one heals by it and the shield
/// pops.
fn strike_enemy(cs: CombatState, d: Int) -> CombatState {
  case cs.enemy_status {
    Meditation -> CombatState(..cs, meditate_bank: cs.meditate_bank + d)
    Shield ->
      CombatState(
        ..cs,
        enemy_hp: int.min(cs.enemy.health, cs.enemy_hp + d),
        enemy_status: NoStatus,
      )
    _ -> {
      let hp = apply_damage(cs.enemy_hp, cs.enemy.health, d)
      trigger_at_health(CombatState(..cs, enemy_hp: hp, won: hp <= 0), hp, d)
    }
  }
}

/// Fire any `atHealth` trigger whose threshold this blow crossed from above
/// (`enemyHp <= k && enemyHp + dmg > k`).
fn trigger_at_health(cs: CombatState, hp: Int, d: Int) -> CombatState {
  list.fold(cs.at_health, cs, fn(acc, trigger) {
    case hp <= trigger.0 && hp + d > trigger.0 {
      True -> CombatState(..acc, enemy_status: trigger.1)
      False -> acc
    }
  })
}

/// Resolve the enemy's attack on the player. A stunned enemy whiffs and spends
/// the stun; a meditating one sits the turn out. Once the trance ends, any
/// banked damage lands as one guaranteed blow — no hit roll.
pub fn enemy_strike(
  cs: CombatState,
  s: state.State,
  hit_roll: Float,
) -> CombatState {
  case cs.enemy_stunned, cs.enemy_status, cs.meditate_bank {
    True, _, _ -> CombatState(..cs, enemy_stunned: False)
    False, Meditation, _ -> cs
    False, _, bank if bank > 0 ->
      hurt_player(CombatState(..cs, meditate_bank: 0), bank)
    False, _, _ ->
      case enemy_attack(cs.enemy.hit, cs.enemy.damage, s, hit_roll) {
        Damage(d) -> land_enemy_hit(cs, d)
        Miss -> cs
        StunHit -> cs
      }
  }
}

fn hurt_player(cs: CombatState, d: Int) -> CombatState {
  CombatState(..cs, player_hp: apply_damage(cs.player_hp, cs.player_max, d))
}

/// An enemy blow that connects: an energised enemy strikes fourfold, a
/// venomous one leaves poison dripping at half the blow — each buff spends
/// itself on the one hit.
fn land_enemy_hit(cs: CombatState, d: Int) -> CombatState {
  case cs.enemy_status {
    Energised ->
      hurt_player(
        CombatState(..cs, enemy_status: NoStatus),
        d * energise_multiplier,
      )
    Venomous ->
      hurt_player(
        CombatState(..cs, enemy_status: NoStatus, player_dot: d / 2),
        d,
      )
    _ -> hurt_player(cs, d)
  }
}
