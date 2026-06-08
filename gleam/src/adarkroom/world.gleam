//// The World: the procedurally generated overworld. This module ports the
//// original's map generation — a 61×61 grid spiralling out from the village at
//// its centre, each tile chosen from terrain probabilities that "stick" to
//// their neighbours. Generation is seeded (a `rng.Seed` is threaded through),
//// so a given seed always yields the same map. Landmarks are layered on next.

import adarkroom/rng.{type Seed}
import adarkroom/state.{type State}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// The map reaches `radius` tiles out from the village in every direction.
pub const radius = 30

const stickiness = 0.5

/// Every kind of map tile (the original's single-character codes).
pub type Tile {
  Village
  IronMine
  CoalMine
  SulphurMine
  Forest
  Field
  Barrens
  Road
  House
  Cave
  Town
  City
  Outpost
  Ship
  Borehole
  Battlefield
  Swamp
  Cache
  Executioner
}

/// The overworld: a tile at each `(x, y)` coordinate.
pub type Map =
  Dict(#(Int, Int), Tile)

/// The passable open ground that terrain is generated from (and on which
/// landmarks may be placed).
pub fn is_terrain(t: Tile) -> Bool {
  case t {
    Forest | Field | Barrens -> True
    _ -> False
  }
}

/// The tile at `(x, y)`, if any.
pub fn tile_at(map: Map, x: Int, y: Int) -> Result(Tile, Nil) {
  dict.get(map, #(x, y))
}

/// The chance weight of each terrain tile before stickiness.
fn terrain_prob(t: Tile) -> Float {
  case t {
    Forest -> 0.15
    Field -> 0.35
    Barrens -> 0.5
    _ -> 0.0
  }
}

/// Generate a full overworld for `seed`: terrain, then every landmark scattered
/// across it at its allotted distance band.
pub fn generate_map(seed: Seed) -> Map {
  let #(terrain, after_terrain) = generate_terrain(seed)
  let #(map, _) =
    list.fold(landmarks(), #(terrain, after_terrain), fn(acc, landmark) {
      let #(tile, count, min_radius, max_radius) = landmark
      place_n(acc.0, tile, count, min_radius, max_radius, acc.1)
    })
  map
}

/// Each landmark as `(tile, count, min_radius, max_radius)`, in placement order.
/// (`max = min` pins a landmark to an exact ring; the outpost is placed in play,
/// not at generation.)
fn landmarks() -> List(#(Tile, Int, Int, Int)) {
  [
    #(IronMine, 1, 5, 5),
    #(CoalMine, 1, 10, 10),
    #(SulphurMine, 1, 20, 20),
    #(House, 10, 0, 45),
    #(Cave, 5, 3, 10),
    #(Town, 10, 10, 20),
    #(City, 20, 20, 45),
    #(Ship, 1, 28, 28),
    #(Borehole, 10, 15, 45),
    #(Battlefield, 5, 18, 45),
    #(Swamp, 1, 15, 45),
    #(Executioner, 1, 28, 28),
  ]
}

/// Place `count` copies of a landmark.
fn place_n(
  map: Map,
  tile: Tile,
  count: Int,
  min_radius: Int,
  max_radius: Int,
  seed: Seed,
) -> #(Map, Seed) {
  case count <= 0 {
    True -> #(map, seed)
    False -> {
      let #(map, seed) = place_landmark(map, tile, min_radius, max_radius, seed)
      place_n(map, tile, count - 1, min_radius, max_radius, seed)
    }
  }
}

/// Place one landmark on open terrain, trying random spots within the radius
/// band until one lands on terrain (faithful to the original's retry loop). If
/// no open spot turns up within the fuel budget the landmark is skipped rather
/// than overwriting the village or another landmark.
fn place_landmark(
  map: Map,
  tile: Tile,
  min_radius: Int,
  max_radius: Int,
  seed: Seed,
) -> #(Map, Seed) {
  case find_spot(map, min_radius, max_radius, seed, 1000) {
    #(Ok(pos), seed) -> #(dict.insert(map, pos, tile), seed)
    #(Error(Nil), seed) -> #(map, seed)
  }
}

fn find_spot(
  map: Map,
  min_radius: Int,
  max_radius: Int,
  seed: Seed,
  fuel: Int,
) -> #(Result(#(Int, Int), Nil), Seed) {
  let #(pos, seed) = candidate(min_radius, max_radius, seed)
  let terrain = case dict.get(map, pos) {
    Ok(t) -> is_terrain(t)
    Error(Nil) -> False
  }
  case terrain, fuel <= 0 {
    True, _ -> #(Ok(pos), seed)
    False, True -> #(Error(Nil), seed)
    False, False -> find_spot(map, min_radius, max_radius, seed, fuel - 1)
  }
}

/// A random candidate position within the radius band: a distance, split into x
/// and y offsets, each independently negated. Four seeded rolls, as in the
/// original.
fn candidate(
  min_radius: Int,
  max_radius: Int,
  seed: Seed,
) -> #(#(Int, Int), Seed) {
  let #(f1, seed) = rng.next_float(seed)
  let r =
    float.truncate(f1 *. int.to_float(max_radius - min_radius)) + min_radius
  let #(f2, seed) = rng.next_float(seed)
  let x_off = float.truncate(f2 *. int.to_float(r))
  let y_off = r - x_off
  let #(f3, seed) = rng.next_float(seed)
  let x_off = case f3 <. 0.5 {
    True -> -x_off
    False -> x_off
  }
  let #(f4, seed) = rng.next_float(seed)
  let y_off = case f4 <. 0.5 {
    True -> -y_off
    False -> y_off
  }
  let x = int.clamp(radius + x_off, 0, radius * 2)
  let y = int.clamp(radius + y_off, 0, radius * 2)
  #(#(x, y), seed)
}

/// Every coordinate holding `tile`.
pub fn positions_of(map: Map, tile: Tile) -> List(#(Int, Int)) {
  dict.to_list(map)
  |> list.filter_map(fn(entry) {
    case entry.1 == tile {
      True -> Ok(entry.0)
      False -> Error(Nil)
    }
  })
}

/// Generate the terrain: the village at the centre, then tiles spiralling
/// outward ring by ring, each chosen from its already-placed neighbours.
pub fn generate_terrain(seed: Seed) -> #(Map, Seed) {
  let start = dict.insert(dict.new(), #(radius, radius), Village)
  list.fold(seq(1, radius + 1), #(start, seed), fn(acc, r) {
    list.fold(ring(r), acc, fn(inner, pos) {
      let #(map, sd) = inner
      let #(tile, sd2) = choose_tile(map, pos.0, pos.1, sd)
      #(dict.insert(map, pos, tile), sd2)
    })
  })
}

/// The coordinates of ring `r`, walked clockwise (matching the original's
/// spiral order so neighbour effects line up).
fn ring(r: Int) -> List(#(Int, Int)) {
  list.map(seq(0, r * 8), fn(t) {
    case t {
      _ if t < 2 * r -> #(radius - r + t, radius - r)
      _ if t < 4 * r -> #(radius + r, radius - 3 * r + t)
      _ if t < 6 * r -> #(radius + 5 * r - t, radius + r)
      _ -> #(radius - r, radius + 7 * r - t)
    }
  })
}

/// Choose a tile for `(x, y)` from its placed orthogonal neighbours: bordering
/// the village forces forest; otherwise neighbours lend their kind a
/// "stickiness" weight, and the remainder is split by the terrain
/// probabilities, with one seeded roll selecting the result.
fn choose_tile(map: Map, x: Int, y: Int, seed: Seed) -> #(Tile, Seed) {
  let neighbours =
    [#(x, y - 1), #(x, y + 1), #(x + 1, y), #(x - 1, y)]
    |> list.filter_map(fn(p) { dict.get(map, p) })
  case list.contains(neighbours, Village) {
    True -> #(Forest, seed)
    False -> {
      let non_sticky =
        1.0 -. stickiness *. int.to_float(list.length(neighbours))
      let sticky =
        list.fold(neighbours, dict.new(), fn(c, t) {
          dict.insert(c, t, weight(c, t) +. stickiness)
        })
      let chances =
        list.fold([Forest, Field, Barrens], sticky, fn(c, t) {
          dict.insert(c, t, weight(c, t) +. terrain_prob(t) *. non_sticky)
        })
      pick(chances, seed)
    }
  }
}

/// Pick a tile from weighted `chances` (highest first), using one seeded roll.
fn pick(chances: Dict(Tile, Float), seed: Seed) -> #(Tile, Seed) {
  let ordered =
    dict.to_list(chances)
    |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
  let #(roll, seed2) = rng.next_float(seed)
  #(accumulate(ordered, roll, 0.0), seed2)
}

fn accumulate(entries: List(#(Tile, Float)), roll: Float, total: Float) -> Tile {
  case entries {
    [] -> Barrens
    [#(tile, chance), ..rest] -> {
      let total = total +. chance
      case roll <. total {
        True -> tile
        False -> accumulate(rest, roll, total)
      }
    }
  }
}

fn weight(chances: Dict(Tile, Float), t: Tile) -> Float {
  result.unwrap(dict.get(chances, t), 0.0)
}

/// The integers `[from, to)`.
fn seq(from: Int, to: Int) -> List(Int) {
  case from < to {
    True -> [from, ..seq(from + 1, to)]
    False -> []
  }
}

// --- survival ---------------------------------------------------------------

const base_water = 10

const base_health = 10

const meat_heal_amount = 8

const moves_per_food = 2

const moves_per_water = 1

/// The most water the player can carry, raised by water-storage upgrades.
pub fn max_water(s: State) -> Int {
  let has = fn(item) { state.get_store(s, item) > 0 }
  base_water
  + case
    has("fluid recycler"),
    has("water tank"),
    has("cask"),
    has("waterskin")
  {
    True, _, _, _ -> 100
    _, True, _, _ -> 50
    _, _, True, _ -> 20
    _, _, _, True -> 10
    _, _, _, _ -> 0
  }
}

/// The player's maximum health, raised by armour.
pub fn max_health(s: State) -> Int {
  let has = fn(item) { state.get_store(s, item) > 0 }
  base_health
  + case
    has("kinetic armour"),
    has("s armour"),
    has("i armour"),
    has("l armour")
  {
    True, _, _, _ -> 75
    _, True, _, _ -> 35
    _, _, True, _ -> 15
    _, _, _, True -> 5
    _, _, _, _ -> 0
  }
}

/// How much health a meal of cured meat restores (doubled for a gastronome).
pub fn meat_heal(s: State) -> Int {
  meat_heal_amount
  * case state.has_perk(s, "gastronome") {
    True -> 2
    False -> 1
  }
}

/// The expedition's running vitals — what the world drains as the player moves.
pub type Vitals {
  Vitals(
    water: Int,
    health: Int,
    food_move: Int,
    water_move: Int,
    starvation: Bool,
    thirst: Bool,
  )
}

/// The result of one move's supply use: the (possibly changed) state, the new
/// vitals, any notices, and whether the player is still alive.
pub type Supplies {
  Supplies(state: State, vitals: Vitals, messages: List(String), alive: Bool)
}

/// Consume one move's supplies: water drains every move, cured meat every couple
/// (healing), and running dry brings on thirst or starvation — fatal the second
/// time. Repeated brushes with each grant a survival perk.
pub fn use_supplies(s: State, v: Vitals) -> Supplies {
  let v = Vitals(..v, food_move: v.food_move + 1, water_move: v.water_move + 1)
  let fed = eat(s, v)
  case fed.alive {
    False -> fed
    True -> drink(fed.state, fed.vitals, fed.messages)
  }
}

fn eat(s: State, v: Vitals) -> Supplies {
  let interval =
    moves_per_food
    * case state.has_perk(s, "slow metabolism") {
      True -> 2
      False -> 1
    }
  case v.food_move >= interval {
    False -> Supplies(s, v, [], True)
    True -> {
      let v = Vitals(..v, food_move: 0)
      case state.get_outfit(s, "cured meat") - 1 {
        0 ->
          Supplies(
            state.set_outfit(s, "cured meat", 0),
            v,
            ["the meat has run out"],
            True,
          )
        remaining if remaining < 0 ->
          case v.starvation {
            False ->
              Supplies(
                state.set_outfit(s, "cured meat", 0),
                Vitals(..v, starvation: True),
                ["starvation sets in"],
                True,
              )
            True -> {
              let s = note_affliction(s, "starved", "slow metabolism")
              Supplies(state.set_outfit(s, "cured meat", 0), v, [], False)
            }
          }
        remaining -> {
          let healed = int.min(v.health + meat_heal(s), max_health(s))
          Supplies(
            state.set_outfit(s, "cured meat", remaining),
            Vitals(..v, health: healed, starvation: False),
            [],
            True,
          )
        }
      }
    }
  }
}

fn drink(s: State, v: Vitals, messages: List(String)) -> Supplies {
  let interval =
    moves_per_water
    * case state.has_perk(s, "desert rat") {
      True -> 2
      False -> 1
    }
  case v.water_move >= interval {
    False -> Supplies(s, v, messages, True)
    True -> {
      let v = Vitals(..v, water_move: 0)
      case v.water - 1 {
        0 ->
          Supplies(
            s,
            Vitals(..v, water: 0),
            list.append(messages, ["there is no more water"]),
            True,
          )
        remaining if remaining < 0 ->
          case v.thirst {
            False ->
              Supplies(
                s,
                Vitals(..v, water: 0, thirst: True),
                list.append(messages, ["the thirst becomes unbearable"]),
                True,
              )
            True -> {
              let s = note_affliction(s, "dehydrated", "desert rat")
              Supplies(s, Vitals(..v, water: 0), messages, False)
            }
          }
        remaining ->
          Supplies(
            s,
            Vitals(..v, water: remaining, thirst: False),
            messages,
            True,
          )
      }
    }
  }
}

/// Record another bout of an affliction; ten of them earn the matching perk.
fn note_affliction(s: State, counter: String, perk: String) -> State {
  let count = state.get_character(s, counter) + 1
  let s = state.set_character(s, counter, count)
  case count >= 10 && !state.has_perk(s, perk) {
    True -> state.add_perk(s, perk)
    False -> s
  }
}
