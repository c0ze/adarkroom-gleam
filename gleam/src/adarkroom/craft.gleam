//// The Room's craftables: structures raised in the village and items crafted at
//// the workshop, with their costs, limits, and flavour. A faithful port of the
//// original `Room.Craftables` data table and its `build` logic.
////
//// Buildings are counted in `game` under a `building.` prefix; crafted items
//// (tools, weapons, upgrades) are counted in `stores`. Costs are always paid
//// from `stores`. Trade goods (bought at the trading post) live elsewhere.

import adarkroom/room
import adarkroom/state.{type State}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// What a craftable is, which decides where it is counted and whether it needs
/// the workshop.
pub type Kind {
  Building
  Tool
  Weapon
  Upgrade
}

/// A buildable structure or craftable item.
pub type Craftable {
  Craftable(
    name: String,
    kind: Kind,
    /// The most that can exist; `None` means unlimited (tools and weapons).
    maximum: Option(Int),
    /// The cost to build one, given the current state (some scale with count).
    cost: fn(State) -> List(#(String, Int)),
    /// Shown when the option first becomes available.
    available_msg: String,
    /// Shown when one is built.
    build_msg: String,
    /// Shown when the maximum is reached (empty when the original has none).
    max_msg: String,
  )
}

const building_prefix = "building."

/// The `game` key under which a building's count is stored.
pub fn building_key(name: String) -> String {
  building_prefix <> name
}

/// How many of a building have been raised.
pub fn building_count(s: State, name: String) -> Int {
  state.get_game(s, building_key(name))
}

/// Whether a craftable's type is made at the workshop (tools, weapons, upgrades).
pub fn needs_workshop(kind: Kind) -> Bool {
  case kind {
    Building -> False
    _ -> True
  }
}

/// How many of this craftable currently exist (buildings in `game`, items in
/// `stores`).
pub fn count(s: State, c: Craftable, name: String) -> Int {
  case c.kind {
    Building -> building_count(s, name)
    _ -> state.get_store(s, name)
  }
}

/// Whether a craftable has reached its maximum.
pub fn at_maximum(c: Craftable, n: Int) -> Bool {
  case c.maximum {
    Some(m) -> n >= m
    None -> False
  }
}

/// Look up a craftable by name.
pub fn get(name: String) -> Result(Craftable, Nil) {
  list.key_find(table(), name)
}

/// Every craftable, in display order.
pub fn all() -> List(#(String, Craftable)) {
  table()
}

// --- reveal gating ----------------------------------------------------------

/// Reveal any craftables whose conditions are now met, given the set already
/// revealed. Returns the updated set plus the availability messages to show
/// (only for craftables seen for the first time and not yet built). Faithful to
/// the original's `craftUnlocked`; the revealed set is runtime-only (not saved),
/// so a reloaded game re-derives it from the current resources.
pub fn reveal(s: State, revealed: Set(String)) -> #(Set(String), List(String)) {
  list.fold(table(), #(revealed, []), fn(acc, entry) {
    let #(name, c) = entry
    let #(seen, msgs) = acc
    case set.contains(seen, name) || !can_reveal(s, c, name) {
      True -> acc
      False -> {
        let announce = count(s, c, name) == 0 && c.available_msg != ""
        let msgs = case announce {
          True -> list.append(msgs, [c.available_msg])
          False -> msgs
        }
        #(set.insert(seen, name), msgs)
      }
    }
  })
}

/// Whether a craftable's button should now appear: the builder must be helping,
/// the workshop must exist for crafts, and it must be already built or both
/// half-affordable (in wood) and have every cost component on hand.
fn can_reveal(s: State, c: Craftable, name: String) -> Bool {
  let workshop_ok = !needs_workshop(c.kind) || building_count(s, "workshop") > 0
  case room.builder_helping(s) && workshop_ok {
    False -> False
    True ->
      count(s, c, name) > 0 || { half_wood_met(s, c) && components_seen(s, c) }
  }
}

/// Half the wood cost is on hand (or the craftable needs no wood).
fn half_wood_met(s: State, c: Craftable) -> Bool {
  case list.key_find(c.cost(s), "wood") {
    Ok(wood_cost) -> state.get_store(s, "wood") * 2 >= wood_cost
    Error(Nil) -> True
  }
}

/// Every cost component has been seen (a positive amount is on hand).
fn components_seen(s: State, c: Craftable) -> Bool {
  list.all(c.cost(s), fn(pair) { state.get_store(s, pair.0) > 0 })
}

/// The revealed craftables, split into buildings and workshop crafts, each in
/// table order — ready for the build and craft button sections.
pub fn visible(
  revealed: Set(String),
) -> #(List(#(String, Craftable)), List(#(String, Craftable))) {
  let shown =
    list.filter(table(), fn(entry) { set.contains(revealed, entry.0) })
  list.partition(shown, fn(entry) {
    let #(_, c) = entry
    !needs_workshop(c.kind)
  })
}

/// Build one of `name`. Faithful to the original: the builder will not work in
/// the cold; reaching the maximum is a silent no-op; otherwise every cost
/// component must be affordable (the first shortfall is reported and nothing is
/// spent) before the cost is paid, the count rises, and the build message fires.
pub fn build(s: State, name: String) -> #(State, List(String)) {
  case get(name) {
    Error(Nil) -> #(s, [])
    Ok(c) -> {
      let too_cold =
        room.temp_to_int(room.temperature(s)) <= room.temp_to_int(room.Cold)
      case too_cold {
        True -> #(s, ["builder just shivers"])
        False ->
          case at_maximum(c, count(s, c, name)) {
            True -> #(s, [])
            False ->
              case try_afford(s, c.cost(s)) {
                Error(missing) -> #(s, ["not enough " <> missing])
                Ok(paid) -> #(increment(paid, c, name), [c.build_msg])
              }
          }
      }
    }
  }
}

/// Pay a cost from `stores` if every component is affordable; otherwise report
/// the first component that falls short and spend nothing.
fn try_afford(s: State, cost: List(#(String, Int))) -> Result(State, String) {
  case list.find(cost, fn(pair) { state.get_store(s, pair.0) < pair.1 }) {
    Ok(#(missing, _)) -> Error(missing)
    Error(Nil) ->
      Ok(
        list.fold(cost, s, fn(acc, pair) {
          state.add_store(acc, pair.0, -pair.1)
        }),
      )
  }
}

/// Record one more of a craftable (a building in `game`, anything else in
/// `stores`).
fn increment(s: State, c: Craftable, name: String) -> State {
  case c.kind {
    Building ->
      state.set_game(s, building_key(name), building_count(s, name) + 1)
    _ -> state.add_store(s, name, 1)
  }
}

/// A cost that does not depend on the current state.
fn fixed(items: List(#(String, Int))) -> fn(State) -> List(#(String, Int)) {
  fn(_s) { items }
}

/// The full craftables table, ported from `Room.Craftables`.
fn table() -> List(#(String, Craftable)) {
  [
    // --- buildings ---------------------------------------------------------
    #(
      "trap",
      Craftable(
        "trap",
        Building,
        Some(10),
        fn(s) { [#("wood", 10 + building_count(s, "trap") * 10)] },
        "builder says she can make traps to catch any creatures might still be alive out there",
        "more traps to catch more creatures",
        "more traps won't help now",
      ),
    ),
    #(
      "cart",
      Craftable(
        "cart",
        Building,
        Some(1),
        fixed([#("wood", 30)]),
        "builder says she can make a cart for carrying wood",
        "the rickety cart will carry more wood from the forest",
        "",
      ),
    ),
    #(
      "hut",
      Craftable(
        "hut",
        Building,
        Some(20),
        fn(s) { [#("wood", 100 + building_count(s, "hut") * 50)] },
        "builder says there are more wanderers. says they'll work, too.",
        "builder puts up a hut, out in the forest. says word will get around.",
        "no more room for huts.",
      ),
    ),
    #(
      "lodge",
      Craftable(
        "lodge",
        Building,
        Some(1),
        fixed([#("wood", 200), #("fur", 10), #("meat", 5)]),
        "villagers could help hunt, given the means",
        "the hunting lodge stands in the forest, a ways out of town",
        "",
      ),
    ),
    #(
      "trading post",
      Craftable(
        "trading post",
        Building,
        Some(1),
        fixed([#("wood", 400), #("fur", 100)]),
        "a trading post would make commerce easier",
        "now the nomads have a place to set up shop, they might stick around a while",
        "",
      ),
    ),
    #(
      "tannery",
      Craftable(
        "tannery",
        Building,
        Some(1),
        fixed([#("wood", 500), #("fur", 50)]),
        "builder says leather could be useful. says the villagers could make it.",
        "tannery goes up quick, on the edge of the village",
        "",
      ),
    ),
    #(
      "smokehouse",
      Craftable(
        "smokehouse",
        Building,
        Some(1),
        fixed([#("wood", 600), #("meat", 50)]),
        "should cure the meat, or it'll spoil. builder says she can fix something up.",
        "builder finishes the smokehouse. she looks hungry.",
        "",
      ),
    ),
    #(
      "workshop",
      Craftable(
        "workshop",
        Building,
        Some(1),
        fixed([#("wood", 800), #("leather", 100), #("scales", 10)]),
        "builder says she could make finer things, if she had the tools",
        "workshop's finally ready. builder's excited to get to it",
        "",
      ),
    ),
    #(
      "steelworks",
      Craftable(
        "steelworks",
        Building,
        Some(1),
        fixed([#("wood", 1500), #("iron", 100), #("coal", 100)]),
        "builder says the villagers could make steel, given the tools",
        "a haze falls over the village as the steelworks fires up",
        "",
      ),
    ),
    #(
      "armoury",
      Craftable(
        "armoury",
        Building,
        Some(1),
        fixed([#("wood", 3000), #("steel", 100), #("sulphur", 50)]),
        "builder says it'd be useful to have a steady source of bullets",
        "armoury's done, welcoming back the weapons of the past.",
        "",
      ),
    ),
    // --- workshop crafts ---------------------------------------------------
    #(
      "torch",
      Craftable(
        "torch",
        Tool,
        None,
        fixed([#("wood", 1), #("cloth", 1)]),
        "",
        "a torch to keep the dark away",
        "",
      ),
    ),
    #(
      "waterskin",
      Craftable(
        "waterskin",
        Upgrade,
        Some(1),
        fixed([#("leather", 50)]),
        "",
        "this waterskin'll hold a bit of water, at least",
        "",
      ),
    ),
    #(
      "cask",
      Craftable(
        "cask",
        Upgrade,
        Some(1),
        fixed([#("leather", 100), #("iron", 20)]),
        "",
        "the cask holds enough water for longer expeditions",
        "",
      ),
    ),
    #(
      "water tank",
      Craftable(
        "water tank",
        Upgrade,
        Some(1),
        fixed([#("iron", 100), #("steel", 50)]),
        "",
        "never go thirsty again",
        "",
      ),
    ),
    #(
      "bone spear",
      Craftable(
        "bone spear",
        Weapon,
        None,
        fixed([#("wood", 100), #("teeth", 5)]),
        "",
        "this spear's not elegant, but it's pretty good at stabbing",
        "",
      ),
    ),
    #(
      "rucksack",
      Craftable(
        "rucksack",
        Upgrade,
        Some(1),
        fixed([#("leather", 200)]),
        "",
        "carrying more means longer expeditions to the wilds",
        "",
      ),
    ),
    #(
      "wagon",
      Craftable(
        "wagon",
        Upgrade,
        Some(1),
        fixed([#("wood", 500), #("iron", 100)]),
        "",
        "the wagon can carry a lot of supplies",
        "",
      ),
    ),
    #(
      "convoy",
      Craftable(
        "convoy",
        Upgrade,
        Some(1),
        fixed([#("wood", 1000), #("iron", 200), #("steel", 100)]),
        "",
        "the convoy can haul mostly everything",
        "",
      ),
    ),
    #(
      "l armour",
      Craftable(
        "l armour",
        Upgrade,
        Some(1),
        fixed([#("leather", 200), #("scales", 20)]),
        "",
        "leather's not strong. better than rags, though.",
        "",
      ),
    ),
    #(
      "i armour",
      Craftable(
        "i armour",
        Upgrade,
        Some(1),
        fixed([#("leather", 200), #("iron", 100)]),
        "",
        "iron's stronger than leather",
        "",
      ),
    ),
    #(
      "s armour",
      Craftable(
        "s armour",
        Upgrade,
        Some(1),
        fixed([#("leather", 200), #("steel", 100)]),
        "",
        "steel's stronger than iron",
        "",
      ),
    ),
    #(
      "iron sword",
      Craftable(
        "iron sword",
        Weapon,
        None,
        fixed([#("wood", 200), #("leather", 50), #("iron", 20)]),
        "",
        "sword is sharp. good protection out in the wilds.",
        "",
      ),
    ),
    #(
      "steel sword",
      Craftable(
        "steel sword",
        Weapon,
        None,
        fixed([#("wood", 500), #("leather", 100), #("steel", 20)]),
        "",
        "the steel is strong, and the blade true.",
        "",
      ),
    ),
    #(
      "rifle",
      Craftable(
        "rifle",
        Weapon,
        None,
        fixed([#("wood", 200), #("steel", 50), #("sulphur", 50)]),
        "",
        "black powder and bullets, like the old days.",
        "",
      ),
    ),
  ]
}
