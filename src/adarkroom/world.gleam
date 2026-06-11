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
import gleam/set.{type Set}
import gleam/string

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

/// Manhattan distance from the village at the centre of the map — how deep into
/// the wilds a position lies, which sets the danger of the encounters there.
pub fn distance(pos: #(Int, Int)) -> Int {
  int.absolute_value(pos.0 - radius) + int.absolute_value(pos.1 - radius)
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
  generate_map_seeded(seed).0
}

fn generate_map_seeded(seed: Seed) -> #(Map, Seed) {
  let #(terrain, after_terrain) = generate_terrain(seed)
  list.fold(landmarks(), #(terrain, after_terrain), fn(acc, landmark) {
    let #(tile, count, min_radius, max_radius) = landmark
    place_n(acc.0, tile, count, min_radius, max_radius, acc.1)
  })
}

/// The world with a prestige cache (`World.LANDMARKS[CACHE]`): the destroyed
/// village holding the previous game's supplies. The original registers the
/// cache landmark only when prestige data exists, and registers it last — so
/// the rest of the map stays identical for a seed.
pub fn generate_prestige_map(seed: Seed) -> Map {
  let #(map, seed) = generate_map_seeded(seed)
  place_landmark(map, Cache, 10, radius * 3 / 2, seed).0
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
            // Eating (even the last) breaks any starvation streak.
            Vitals(..v, starvation: False),
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
              let #(s, learned) =
                note_affliction(s, "starved", "slow metabolism")
              Supplies(state.set_outfit(s, "cured meat", 0), v, learned, False)
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
            // Drinking (even the last) breaks any thirst streak.
            Vitals(..v, water: 0, thirst: False),
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
              let #(s, learned) = note_affliction(s, "dehydrated", "desert rat")
              Supplies(
                s,
                Vitals(..v, water: 0),
                list.append(messages, learned),
                False,
              )
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
fn note_affliction(
  s: State,
  counter: String,
  perk: String,
) -> #(State, List(String)) {
  let count = state.get_character(s, counter) + 1
  let s = state.set_character(s, counter, count)
  case count >= 10 && !state.has_perk(s, perk) {
    True -> #(state.add_perk(s, perk), [state.perk_notify(perk)])
    False -> #(s, [])
  }
}

// --- expedition: movement & fog ---------------------------------------------

const light_radius = 2

/// A direction of travel.
pub type Dir {
  North
  South
  West
  East
}

fn offset(dir: Dir) -> #(Int, Int) {
  case dir {
    North -> #(0, -1)
    South -> #(0, 1)
    West -> #(-1, 0)
    East -> #(1, 0)
  }
}

/// An expedition into the world: where the player stands, the map, the ground
/// they have seen (the fog mask), and their vitals.
///
/// `visited` and `used_outposts` track the landmarks dealt with this trip so a
/// setpiece won't fire again when you step back onto its tile. The JS keeps the
/// same per-trip state (`map` markers and `usedOutposts`), reset on arrival; our
/// world is re-rolled each embark, so per-trip sets match that behaviour.
pub type Expedition {
  Expedition(
    pos: #(Int, Int),
    map: Map,
    seen: Set(#(Int, Int)),
    vitals: Vitals,
    visited: Set(#(Int, Int)),
    /// Whether the wanderer is out past their armour (`World.danger`).
    danger: Bool,
    used_outposts: Set(#(Int, Int)),
    /// The mines cleared this trip, by building name (`"iron mine"`, …). The JS
    /// flags these on the world and grants the building on a safe return home;
    /// we credit them in `go_home`.
    mines_cleared: Set(String),
  )
}

/// The result of a step: the (possibly changed) state and expedition, any
/// notices, and whether the player is still alive.
pub type Step {
  Step(
    state: State,
    expedition: Expedition,
    messages: List(String),
    alive: Bool,
  )
}

/// How far the player can see (doubled by the scout perk).
fn sight(s: State) -> Int {
  light_radius
  * case state.has_perk(s, "scout") {
    True -> 2
    False -> 1
  }
}

/// Begin an expedition at the village, with the bag's water/health and the
/// starting area lit.
pub fn begin(map: Map, s: State) -> Expedition {
  let pos = #(radius, radius)
  Expedition(
    pos: pos,
    map: map,
    seen: uncover(set.new(), pos, sight(s)),
    vitals: Vitals(
      water: max_water(s),
      health: max_health(s),
      food_move: 0,
      water_move: 0,
      starvation: False,
      thirst: False,
    ),
    visited: set.new(),
    danger: False,
    used_outposts: set.new(),
    mines_cleared: set.new(),
  )
}

/// The crossing of a terrain boundary, narrated (`narrateMove`).
pub fn narrate_move(old_tile: Tile, new_tile: Tile) -> List(String) {
  case old_tile, new_tile {
    Forest, Field -> [
      "the trees yield to dry grass. the yellowed brush rustles in the wind.",
    ]
    Forest, Barrens -> [
      "the trees are gone. parched earth and blowing dust are poor replacements.",
    ]
    Field, Forest -> [
      "trees loom on the horizon. grasses gradually yield to a forest floor of dry branches and fallen leaves.",
    ]
    Field, Barrens -> ["the grasses thin. soon, only dust remains."]
    Barrens, Field -> [
      "the barrens break at a sea of dying grass, swaying in the arid breeze.",
    ]
    Barrens, Forest -> [
      "a wall of gnarled trees rises from the dust. their branches twist into a skeletal canopy overhead.",
    ]
    _, _ -> []
  }
}

/// Watch the wanderer's depth against their armour (`checkDanger`): venturing
/// past 8 without iron armour (or 18 without steel) raises the warning; it
/// only lifts back under 8 — the original's second clearing branch compares
/// the function itself (`World.getDistance < 18`, no parens) and never fires.
/// Returns the expedition and whether the state flipped.
pub fn check_danger(exp: Expedition, s: State) -> #(Expedition, Bool) {
  case exp.danger {
    False ->
      case
        { state.get_store(s, "i armour") == 0 && distance(exp.pos) >= 8 }
        || { state.get_store(s, "s armour") == 0 && distance(exp.pos) >= 18 }
      {
        True -> #(Expedition(..exp, danger: True), True)
        False -> #(exp, False)
      }
    True ->
      case distance(exp.pos) < 8 {
        True -> #(Expedition(..exp, danger: False), True)
        False -> #(exp, False)
      }
  }
}

/// Which way the compass points (`compassDir`): the dominant axis alone past
/// a 2:1 ratio, the diagonal otherwise.
pub fn compass_dir(pos: #(Int, Int)) -> String {
  let dx = pos.0 - radius
  let dy = pos.1 - radius
  let horz = case dx < 0 {
    True -> "west"
    False -> "east"
  }
  let vert = case dy < 0 {
    True -> "north"
    False -> "south"
  }
  let ax = int.absolute_value(dx)
  let ay = int.absolute_value(dy)
  case ax > 2 * ay, ay > 2 * ax {
    True, _ -> horz
    _, True -> vert
    _, _ -> vert <> horz
  }
}

/// Where the crashed starship lies on the saved world, for the compass's
/// tooltip — `Error` until a world exists or if no ship stands.
pub fn saved_ship_dir(ws: state.WorldSave) -> Result(String, Nil) {
  list.index_fold(ws.map, Error(Nil), fn(found, row, y) {
    list.index_fold(row, found, fn(found, letter, x) {
      case found, string.starts_with(letter, "W") {
        Error(_), True -> Ok(compass_dir(#(x, y)))
        _, _ -> found
      }
    })
  })
}

/// Whether the whole world has been seen (`World.seenAll` via `testMap`).
pub fn seen_all(ws: state.WorldSave) -> Bool {
  list.all(ws.mask, fn(row) { list.all(row, fn(lit) { lit }) })
}

/// The letter back to its tile (`tile_char` reversed).
fn char_tile(c: String) -> Result(Tile, Nil) {
  case c {
    "A" -> Ok(Village)
    "I" -> Ok(IronMine)
    "C" -> Ok(CoalMine)
    "S" -> Ok(SulphurMine)
    ";" -> Ok(Forest)
    "," -> Ok(Field)
    "." -> Ok(Barrens)
    "#" -> Ok(Road)
    "H" -> Ok(House)
    "V" -> Ok(Cave)
    "O" -> Ok(Town)
    "Y" -> Ok(City)
    "P" -> Ok(Outpost)
    "W" -> Ok(Ship)
    "B" -> Ok(Borehole)
    "F" -> Ok(Battlefield)
    "M" -> Ok(Swamp)
    "U" -> Ok(Cache)
    "X" -> Ok(Executioner)
    _ -> Error(Nil)
  }
}

/// Pack the trip's map, visited marks and fog for the save — `goHome`
/// committing `World.state` back to `game.world`. A visited landmark's
/// letter carries a trailing `!`, the original's `markVisited`.
pub fn to_save(exp: Expedition) -> state.WorldSave {
  let side = seq(0, radius * 2 + 1)
  let rows = fn(cell: fn(Int, Int) -> a) {
    list.map(side, fn(y) { list.map(side, fn(x) { cell(x, y) }) })
  }
  state.WorldSave(
    map: rows(fn(x, y) {
      let letter = case dict.get(exp.map, #(x, y)) {
        Ok(t) -> tile_char(t)
        Error(_) -> "."
      }
      case set.contains(exp.visited, #(x, y)) {
        True -> letter <> "!"
        False -> letter
      }
    }),
    mask: rows(fn(x, y) { set.contains(exp.seen, #(x, y)) }),
  )
}

/// Resume the lasting world from the save: the map, the landmarks already
/// dealt with (their `!` marks), and the fog seen so far. A malformed save
/// is an `Error`, and the caller makes the world anew.
pub fn resume(ws: state.WorldSave, s: State) -> Result(Expedition, Nil) {
  use #(map, visited) <- result.try(parse_map(ws.map))
  let seen =
    list.index_fold(ws.mask, set.new(), fn(acc, row, y) {
      list.index_fold(row, acc, fn(acc, lit, x) {
        case lit {
          True -> set.insert(acc, #(x, y))
          False -> acc
        }
      })
    })
  let fresh = begin(map, s)
  Ok(Expedition(..fresh, seen: set.union(fresh.seen, seen), visited: visited))
}

fn parse_map(rows: List(List(String))) -> Result(#(Map, Set(#(Int, Int))), Nil) {
  list.index_fold(rows, Ok(#(dict.new(), set.new())), fn(acc, row, y) {
    list.index_fold(row, acc, fn(acc, letter, x) {
      use #(map, visited) <- result.try(acc)
      use tile <- result.try(char_tile(string.slice(letter, 0, 1)))
      let visited = case string.ends_with(letter, "!") {
        True -> set.insert(visited, #(x, y))
        False -> visited
      }
      Ok(#(dict.insert(map, #(x, y), tile), visited))
    })
  })
}

/// The setpiece registry key for a landmark tile, mirroring `World.LANDMARKS`.
/// Terrain, roads, the village and the executioner have no setpiece here.
pub fn setpiece_scene(tile: Tile) -> Result(String, Nil) {
  case tile {
    Outpost -> Ok("outpost")
    IronMine -> Ok("ironmine")
    CoalMine -> Ok("coalmine")
    SulphurMine -> Ok("sulphurmine")
    House -> Ok("house")
    Cave -> Ok("cave")
    Town -> Ok("town")
    City -> Ok("city")
    Ship -> Ok("ship")
    Borehole -> Ok("borehole")
    Battlefield -> Ok("battlefield")
    Swamp -> Ok("swamp")
    Cache -> Ok("cache")
    _ -> Error(Nil)
  }
}

/// Whether arriving here should launch a setpiece: a landmark not yet dealt with
/// this trip (`markVisited`), and — for an outpost — one not already used. This
/// is the `doSpace` landmark guard.
pub fn should_trigger_setpiece(exp: Expedition, tile: Tile) -> Bool {
  case setpiece_scene(tile) {
    Error(_) -> False
    Ok(_) ->
      !set.contains(exp.visited, exp.pos)
      && case tile {
        Outpost -> !set.contains(exp.used_outposts, exp.pos)
        _ -> True
      }
  }
}

/// Mark the landmark under the player visited, so it won't fire again this trip
/// (`World.markVisited`).
pub fn mark_visited(exp: Expedition) -> Expedition {
  Expedition(..exp, visited: set.insert(exp.visited, exp.pos))
}

/// Refill water to the brim (`World.setWater(getMaxWater())`).
pub fn refill_water(exp: Expedition, s: State) -> Expedition {
  Expedition(..exp, vitals: Vitals(..exp.vitals, water: max_water(s)))
}

/// Use the outpost under the player: refill water to the brim and note it spent,
/// so it won't refill again this trip (`World.useOutpost`).
pub fn use_outpost(exp: Expedition, s: State) -> Expedition {
  Expedition(
    ..refill_water(exp, s),
    used_outposts: set.insert(exp.used_outposts, exp.pos),
  )
}

/// Draw a road from the player's tile back to the network (`World.drawRoad`):
/// find the nearest road/outpost/village and pave an L-shaped path of road over
/// any terrain between here and there.
pub fn lay_road(exp: Expedition) -> Expedition {
  Expedition(..exp, map: draw_road(exp.map, exp.pos))
}

/// Clear the dungeon under the player into a friendly outpost and connect it to
/// the road network (`World.clearDungeon`).
pub fn clear_dungeon(exp: Expedition) -> Expedition {
  let map = dict.insert(exp.map, exp.pos, Outpost)
  Expedition(..exp, map: draw_road(map, exp.pos))
}

/// Clear the mine under the player: road it home, mark it dealt with, and flag
/// its `building` so `go_home` grants it on a safe return (`World.state.<mine>`).
pub fn clear_mine(exp: Expedition, building: String) -> Expedition {
  Expedition(
    ..mark_visited(lay_road(exp)),
    mines_cleared: set.insert(exp.mines_cleared, building),
  )
}

/// Pave an L-shaped road from `from` to the nearest existing road, mirroring
/// `World.drawRoad`: the road runs along one axis to an intersection, then the
/// other, overwriting only open terrain (never a landmark).
pub fn draw_road(map: Map, from: #(Int, Int)) -> Map {
  let closest = find_closest_road(map, from)
  let x_dist = from.0 - closest.0
  let y_dist = from.1 - closest.1
  let #(xi, yi) = case int.absolute_value(x_dist) > int.absolute_value(y_dist) {
    True -> #(closest.0, closest.1 + y_dist)
    False -> #(closest.0 + x_dist, closest.1)
  }
  let map =
    list.fold(seq(0, int.absolute_value(x_dist)), map, fn(m, x) {
      pave(m, #(closest.0 + sign(x_dist) * x, yi))
    })
  list.fold(seq(0, int.absolute_value(y_dist)), map, fn(m, y) {
    pave(m, #(xi, closest.1 + sign(y_dist) * y))
  })
}

/// Lay road over a tile only when it is open terrain.
fn pave(map: Map, p: #(Int, Int)) -> Map {
  case tile_at(map, p.0, p.1) {
    Ok(t) ->
      case is_terrain(t) {
        True -> dict.insert(map, p, Road)
        False -> map
      }
    Error(_) -> map
  }
}

/// The sign of an integer (0 for 0), for stepping toward the road.
fn sign(n: Int) -> Int {
  case n {
    0 -> 0
    _ -> n / int.absolute_value(n)
  }
}

/// Spiral out from `start` along Manhattan contours to the nearest tile that is
/// road, a connected outpost, or the village — the shortest road's anchor. Falls
/// back to the village if the bounded search finds nothing (`findClosestRoad`).
fn find_closest_road(map: Map, start: #(Int, Int)) -> #(Int, Int) {
  let reach = distance(start) + 2
  spiral_for_road(map, start, 0, reach * reach, 0, 0, 1, -1)
}

fn spiral_for_road(
  map: Map,
  start: #(Int, Int),
  i: Int,
  max_i: Int,
  x: Int,
  y: Int,
  dx: Int,
  dy: Int,
) -> #(Int, Int) {
  case i >= max_i {
    True -> #(radius, radius)
    False -> {
      let sx = start.0 + x
      let sy = start.1 + y
      let found = case 0 < sx && sx < radius * 2 && 0 < sy && sy < radius * 2 {
        True ->
          case tile_at(map, sx, sy) {
            Ok(Road) | Ok(Village) -> True
            // Outposts are connected to roads, but the start tile doesn't count.
            Ok(Outpost) -> !{ x == 0 && y == 0 }
            _ -> False
          }
        False -> False
      }
      case found {
        True -> #(sx, sy)
        False -> {
          // Turn the corner on an axis, then step along the contour.
          let #(dx, dy) = case x == 0 || y == 0 {
            True -> #(0 - dy, dx)
            False -> #(dx, dy)
          }
          let #(x, y) = case x == 0 && y <= 0 {
            True -> #(x + 1, y)
            False -> #(x + dx, y + dy)
          }
          spiral_for_road(map, start, i + 1, max_i, x, y, dx, dy)
        }
      }
    }
  }
}

/// Reveal the diamond of tiles within Manhattan distance `r` of `pos`.
fn uncover(seen: Set(#(Int, Int)), pos: #(Int, Int), r: Int) -> Set(#(Int, Int)) {
  let #(x, y) = pos
  list.fold(seq(-r, r + 1), seen, fn(seen, i) {
    let span = r - int.absolute_value(i)
    list.fold(seq(-span, span + 1), seen, fn(seen, j) {
      let p = #(x + i, y + j)
      case in_bounds(p) {
        True -> set.insert(seen, p)
        False -> seen
      }
    })
  })
}

fn in_bounds(p: #(Int, Int)) -> Bool {
  p.0 >= 0 && p.0 <= radius * 2 && p.1 >= 0 && p.1 <= radius * 2
}

/// Feed carried blueprints into the fabricator's data port on a safe return
/// (`World.redeemBlueprints`): each is spent from the pack — never reaching
/// the stores — and recorded under `character.blueprints.<item>`.
pub fn redeem_blueprints(s: State) -> #(State, List(String)) {
  let pairs = [
    #("hypo blueprint", "hypo"),
    #("kinetic armour blueprint", "kinetic armour"),
    #("disruptor blueprint", "disruptor"),
    #("plasma rifle blueprint", "plasma rifle"),
    #("stim blueprint", "stim"),
    #("glowstone blueprint", "glowstone"),
  ]
  let #(s, redeemed) =
    list.fold(pairs, #(s, False), fn(acc, pair) {
      let #(s, any) = acc
      case state.get_outfit(s, pair.0) > 0 {
        True -> #(
          s
            |> state.set_character("blueprints." <> pair.1, 1)
            |> state.set_outfit(pair.0, 0),
          True,
        )
        False -> #(s, any)
      }
    })
  case redeemed {
    True -> #(s, [
      "blueprints feed into the fabricator data port. possibilities grow.",
    ])
    False -> #(s, [])
  }
}

/// A scavenged surface map (`World.applyMap`): reveal the radius-5 diamond
/// around a random still-unseen spot. The JS rejection-samples coordinates
/// until it lands on an unseen one — a uniform pick over the unseen positions
/// is the same distribution in a single roll. With nothing left unseen,
/// nothing to reveal.
pub fn apply_map(exp: Expedition, roll: Float) -> Expedition {
  let unseen =
    list.flat_map(seq(0, radius * 2 + 1), fn(x) {
      list.filter_map(seq(0, radius * 2 + 1), fn(y) {
        case set.contains(exp.seen, #(x, y)) {
          True -> Error(Nil)
          False -> Ok(#(x, y))
        }
      })
    })
  let n = list.length(unseen)
  let idx = int.min(float.truncate(roll *. int.to_float(n)), n - 1)
  case unseen |> list.drop(idx) |> list.first {
    Ok(pos) -> Expedition(..exp, seen: uncover(exp.seen, pos, 5))
    Error(_) -> exp
  }
}

/// Take a step. At the edge of the world the step is refused; otherwise the
/// player moves, the newly-reached ground is lit, and a move's supplies are
/// spent (which may be fatal).
pub fn move(s: State, exp: Expedition, dir: Dir) -> Step {
  let #(dx, dy) = offset(dir)
  let pos = #(exp.pos.0 + dx, exp.pos.1 + dy)
  case in_bounds(pos) {
    False -> Step(s, exp, [], True)
    True -> {
      let moved =
        Expedition(..exp, pos:, seen: uncover(exp.seen, pos, sight(s)))
      // Crossing a terrain boundary is narrated first (`narrateMove`).
      let narration = case
        tile_at(exp.map, exp.pos.0, exp.pos.1),
        tile_at(exp.map, pos.0, pos.1)
      {
        Ok(old_tile), Ok(new_tile) -> narrate_move(old_tile, new_tile)
        _, _ -> []
      }
      // Stepping home to the village costs no supplies and never kills — the JS
      // `doSpace` runs `useSupplies` only off the village, so a safe return is
      // always genuinely safe (and so can't, e.g., wrongly forfeit mine credit).
      case tile_at(exp.map, pos.0, pos.1) {
        Ok(Village) -> Step(s, moved, narration, True)
        _ -> {
          let supplies = use_supplies(s, exp.vitals)
          Step(
            supplies.state,
            Expedition(..moved, vitals: supplies.vitals),
            list.append(narration, supplies.messages),
            supplies.alive,
          )
        }
      }
    }
  }
}

// --- map render -------------------------------------------------------------

/// The single-character glyph for a tile (the original's map codes).
pub fn tile_char(t: Tile) -> String {
  case t {
    Village -> "A"
    IronMine -> "I"
    CoalMine -> "C"
    SulphurMine -> "S"
    Forest -> ";"
    Field -> ","
    Barrens -> "."
    Road -> "#"
    House -> "H"
    Cave -> "V"
    Town -> "O"
    City -> "Y"
    Outpost -> "P"
    Ship -> "W"
    Borehole -> "B"
    Battlefield -> "F"
    Swamp -> "M"
    Cache -> "U"
    Executioner -> "X"
  }
}

/// Render the expedition's map as 61 rows of text: the wanderer marked `@`, seen
/// tiles shown by their glyph, and unseen ground left blank.
/// A landmark's hover label (`World.LANDMARKS[..].label`), non-breaking
/// spaces and all. Terrain and roads have none.
pub fn landmark_label(t: Tile) -> Result(String, Nil) {
  case t {
    Village -> Ok("The\u{00A0}Village")
    Outpost -> Ok("An\u{00A0}Outpost")
    IronMine -> Ok("Iron\u{00A0}Mine")
    CoalMine -> Ok("Coal\u{00A0}Mine")
    SulphurMine -> Ok("Sulphur\u{00A0}Mine")
    House -> Ok("An\u{00A0}Old\u{00A0}House")
    Cave -> Ok("A\u{00A0}Damp\u{00A0}Cave")
    Town -> Ok("An\u{00A0}Abandoned\u{00A0}Town")
    City -> Ok("A\u{00A0}Ruined\u{00A0}City")
    Ship -> Ok("A\u{00A0}Crashed\u{00A0}Starship")
    Borehole -> Ok("A\u{00A0}Borehole")
    Battlefield -> Ok("A\u{00A0}Battlefield")
    Swamp -> Ok("A\u{00A0}Murky\u{00A0}Swamp")
    Cache -> Ok("A\u{00A0}Destroyed\u{00A0}Village")
    Executioner -> Ok("A\u{00A0}Ravaged\u{00A0}Battleship")
    Forest | Field | Barrens | Road -> Error(Nil)
  }
}

/// One spot on the drawn map (`drawMap`'s cases): the wanderer, a labelled
/// landmark, plain ground, or the unseen dark.
pub type MapCell {
  /// The `@`, with its 'Wanderer' tooltip.
  Wanderer
  /// A lit landmark with its hover label — visited ones (and used outposts)
  /// fall back to plain ground, as the original's `H!` lookup misses.
  Labelled(char: String, label: String)
  /// Lit ground (or a delabelled landmark): just its letter.
  Ground(char: String)
  /// Not yet seen.
  Dark
}

/// Classify the spot at `(x, y)` for the structured map renderer.
pub fn map_cell(exp: Expedition, x: Int, y: Int) -> MapCell {
  case #(x, y) == exp.pos {
    True -> Wanderer
    False ->
      case set.contains(exp.seen, #(x, y)), dict.get(exp.map, #(x, y)) {
        True, Ok(t) -> {
          let delabelled =
            set.contains(exp.visited, #(x, y))
            || t == Outpost
            && set.contains(exp.used_outposts, #(x, y))
          case delabelled, landmark_label(t) {
            False, Ok(label) -> Labelled(char: tile_char(t), label: label)
            _, _ -> Ground(tile_char(t))
          }
        }
        True, Error(_) -> Ground(" ")
        False, _ -> Dark
      }
  }
}

pub fn render(exp: Expedition) -> List(String) {
  list.map(seq(0, radius * 2 + 1), fn(y) {
    seq(0, radius * 2 + 1)
    |> list.map(fn(x) { cell(exp, x, y) })
    |> string.concat
  })
}

fn cell(exp: Expedition, x: Int, y: Int) -> String {
  case #(x, y) == exp.pos {
    True -> "@"
    False ->
      case set.contains(exp.seen, #(x, y)), dict.get(exp.map, #(x, y)) {
        True, Ok(t) -> tile_char(t)
        _, _ -> " "
      }
  }
}
