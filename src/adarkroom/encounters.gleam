//// The world encounters — the combat events that lie in wait out in the
//// wilds, ported from `events/encounters.js`. Each is gated by how far from
//// the village the player has wandered and by the terrain underfoot.
////
//// This bridges `combat` (the enemy/fight types) and `world` (the terrain and
//// distance), so it lives apart from both. Tier 1 (within ten tiles of home)
//// is here; the deeper tiers follow.

import adarkroom/combat.{type Enemy, type LootEntry, Enemy, LootEntry}
import adarkroom/world.{type Tile}
import gleam/list

/// A world encounter: an enemy that appears within a distance band on a kind of
/// terrain.
pub type Encounter {
  Encounter(
    title: String,
    min_dist: Int,
    max_dist: Int,
    terrain: Tile,
    enemy: Enemy,
    notification: String,
  )
}

/// Every world encounter, in tier order.
pub fn encounters() -> List(Encounter) {
  [
    // --- Tier 1: within ten tiles of the village ---
    tier1(
      "A Snarling Beast",
      world.Forest,
      melee(
        "snarling beast",
        "R",
        5,
        1,
        0.8,
        1.0,
        "the snarling beast is dead",
        [
          LootEntry("fur", 1, 3, 1.0),
          LootEntry("meat", 1, 3, 1.0),
          LootEntry("teeth", 1, 3, 0.8),
        ],
      ),
      "a snarling beast leaps out of the underbrush",
    ),
    tier1(
      "A Gaunt Man",
      world.Barrens,
      melee("gaunt man", "E", 6, 2, 0.8, 2.0, "the gaunt man is dead", [
        LootEntry("cloth", 1, 3, 0.8),
        LootEntry("teeth", 1, 2, 0.8),
        LootEntry("leather", 1, 2, 0.5),
      ]),
      "a gaunt man approaches, a crazed look in his eye",
    ),
    tier1(
      "A Strange Bird",
      world.Field,
      melee("strange bird", "R", 4, 3, 0.8, 2.0, "the strange bird is dead", [
        LootEntry("scales", 1, 3, 0.8),
        LootEntry("teeth", 1, 2, 0.5),
        LootEntry("meat", 1, 3, 0.8),
      ]),
      "a strange looking bird speeds across the plains",
    ),
    tier1(
      "A Two-Headed Creature",
      world.Field,
      melee(
        "two-headed creature",
        "K",
        10,
        2,
        0.5,
        3.0,
        "the two creatures are dead",
        [
          LootEntry("fur", 2, 4, 1.0),
          LootEntry("teeth", 2, 3, 0.8),
          LootEntry("meat", 2, 3, 0.8),
        ],
      ),
      "a two-headed creature appears, the smaller head trembling",
    ),
    // --- Tier 2: eleven to twenty tiles out ---
    tier2(
      "A Shivering Man",
      world.Barrens,
      melee("shivering man", "E", 20, 5, 0.5, 1.0, "the shivering man is dead", [
        LootEntry("cloth", 1, 1, 0.2),
        LootEntry("teeth", 1, 2, 0.8),
        LootEntry("leather", 1, 1, 0.2),
        LootEntry("medicine", 1, 3, 0.7),
      ]),
      "a shivering man approaches and attacks with surprising strength",
    ),
    tier2(
      "A Man-Eater",
      world.Forest,
      melee("man-eater", "T", 25, 3, 0.8, 1.0, "the man-eater is dead", [
        LootEntry("fur", 5, 10, 1.0),
        LootEntry("meat", 5, 10, 1.0),
        LootEntry("teeth", 5, 10, 0.8),
      ]),
      "a large creature attacks, claws freshly bloodied",
    ),
    tier2(
      "A Scavenger",
      world.Barrens,
      melee("scavenger", "E", 30, 4, 0.8, 2.0, "the scavenger is dead", [
        LootEntry("cloth", 5, 10, 0.8),
        LootEntry("leather", 5, 10, 0.8),
        LootEntry("iron", 1, 5, 0.5),
        LootEntry("medicine", 1, 2, 0.1),
      ]),
      "a scavenger draws close, hoping for an easy score",
    ),
    tier2(
      "A Huge Lizard",
      world.Field,
      melee("lizard", "T", 20, 5, 0.8, 2.0, "the lizard is dead", [
        LootEntry("scales", 5, 10, 0.8),
        LootEntry("teeth", 5, 10, 0.5),
        LootEntry("meat", 5, 10, 0.8),
      ]),
      "the grass thrashes wildly as a huge lizard pushes through",
    ),
    // --- Tier 3: deeper than twenty tiles ---
    tier3(
      "A Feral Terror",
      world.Forest,
      melee("feral terror", "T", 45, 6, 0.8, 1.0, "the feral terror is dead", [
        LootEntry("fur", 5, 10, 1.0),
        LootEntry("meat", 5, 10, 1.0),
        LootEntry("teeth", 5, 10, 0.8),
      ]),
      "a beast, wilder than imagining, erupts out of the foliage",
    ),
    tier3(
      "A Soldier",
      world.Barrens,
      ranged("soldier", "D", 50, 8, 0.8, 2.0, "the soldier is dead", [
        LootEntry("cloth", 5, 10, 0.8),
        LootEntry("bullets", 1, 5, 0.5),
        LootEntry("rifle", 1, 1, 0.2),
        LootEntry("medicine", 1, 2, 0.1),
      ]),
      "a soldier opens fire from across the desert",
    ),
    tier3(
      "A Sniper",
      world.Field,
      ranged("sniper", "D", 30, 15, 0.8, 4.0, "the sniper is dead", [
        LootEntry("cloth", 5, 10, 0.8),
        LootEntry("bullets", 1, 5, 0.5),
        LootEntry("rifle", 1, 1, 0.2),
        LootEntry("medicine", 1, 2, 0.1),
      ]),
      "a shot rings out, from somewhere in the long grass",
    ),
  ]
}

/// The encounters that can spring at the given distance and terrain.
pub fn available(distance: Int, terrain: Tile) -> List(Encounter) {
  list.filter(encounters(), fn(e) {
    e.terrain == terrain && distance >= e.min_dist && distance <= e.max_dist
  })
}

/// A Tier 1 encounter (distance 0–10).
fn tier1(
  title: String,
  terrain: Tile,
  enemy: Enemy,
  notification: String,
) -> Encounter {
  Encounter(title:, min_dist: 0, max_dist: 10, terrain:, enemy:, notification:)
}

/// A melee enemy (the common case — only some deeper foes fight at range).
fn melee(
  name: String,
  chara: String,
  health: Int,
  damage: Int,
  hit: Float,
  attack_delay: Float,
  death_message: String,
  loot: List(LootEntry),
) -> Enemy {
  Enemy(
    name:,
    chara:,
    health:,
    damage:,
    hit:,
    attack_delay:,
    ranged: False,
    death_message:,
    loot:,
  )
}

/// A Tier 2 encounter (distance 11–20).
fn tier2(
  title: String,
  terrain: Tile,
  enemy: Enemy,
  notification: String,
) -> Encounter {
  Encounter(title:, min_dist: 11, max_dist: 20, terrain:, enemy:, notification:)
}

/// A Tier 3 encounter (distance 21 and beyond).
fn tier3(
  title: String,
  terrain: Tile,
  enemy: Enemy,
  notification: String,
) -> Encounter {
  Encounter(
    title:,
    min_dist: 21,
    max_dist: 9999,
    terrain:,
    enemy:,
    notification:,
  )
}

/// A ranged enemy (the desert soldiers and snipers).
fn ranged(
  name: String,
  chara: String,
  health: Int,
  damage: Int,
  hit: Float,
  attack_delay: Float,
  death_message: String,
  loot: List(LootEntry),
) -> Enemy {
  Enemy(
    name:,
    chara:,
    health:,
    damage:,
    hit:,
    attack_delay:,
    ranged: True,
    death_message:,
    loot:,
  )
}
