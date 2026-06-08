//// The World: the procedurally generated overworld. This module ports the
//// original's map generation — a 61×61 grid spiralling out from the village at
//// its centre, each tile chosen from terrain probabilities that "stick" to
//// their neighbours. Generation is seeded (a `rng.Seed` is threaded through),
//// so a given seed always yields the same map. Landmarks are layered on next.

import adarkroom/rng.{type Seed}
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
