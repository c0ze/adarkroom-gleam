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
    attack_delay: Int,
    ranged: Bool,
    death_message: String,
    loot: List(LootEntry),
  )
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
  )
}

/// Resolve a player attack on the enemy. A stun makes it skip its next turn;
/// numeric damage lowers its HP and may win the fight.
pub fn player_strike(
  cs: CombatState,
  weapon: Weapon,
  s: state.State,
  hit_roll: Float,
) -> CombatState {
  case player_attack(weapon, s, hit_roll) {
    Miss -> cs
    StunHit -> CombatState(..cs, enemy_stunned: True)
    Damage(d) -> {
      let hp = apply_damage(cs.enemy_hp, cs.enemy.health, d)
      CombatState(..cs, enemy_hp: hp, won: hp <= 0)
    }
  }
}

/// Resolve the enemy's attack on the player. A stunned enemy whiffs and spends
/// the stun.
pub fn enemy_strike(
  cs: CombatState,
  s: state.State,
  hit_roll: Float,
) -> CombatState {
  case cs.enemy_stunned {
    True -> CombatState(..cs, enemy_stunned: False)
    False ->
      case enemy_attack(cs.enemy.hit, cs.enemy.damage, s, hit_roll) {
        Damage(d) ->
          CombatState(
            ..cs,
            player_hp: apply_damage(cs.player_hp, cs.player_max, d),
          )
        Miss -> cs
        StunHit -> cs
      }
  }
}
