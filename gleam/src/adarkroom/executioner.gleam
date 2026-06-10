//// The Ravaged Battleship — the executioner event chain, ported from
//// `events/executioner.js`.
////
//// Six chained events ride the same scene runtime as the setpieces: the
//// first visit unseals the ship (the intro), after which the antechamber's
//// elevators reach three wings and — once all three are dealt with — the
//// command deck. The chain hops between events via `GotoEvent` (the JS
//// button `nextEvent` → `Events.switchEvent`), and its progress flags live
//// in the game state under `world.*`, as the JS keeps them on the persisted
//// world.

import adarkroom/combat
import adarkroom/events.{
  type Event, type Scene, type SceneButton, type SetpieceExtra, Branch, End,
  Event, Scene, SceneButton, SetpieceExtra,
}
import adarkroom/state
import gleam/option.{None, Some}

/// The event for a registry key (`Events.Executioner[...]`). The martial and
/// medical wings and the command deck arrive in later increments.
pub fn event(key: String) -> Result(Event, Nil) {
  case key {
    "executioner-intro" -> Ok(intro())
    "executioner-antechamber" -> Ok(antechamber())
    "executioner-engineering" -> Ok(engineering())
    _ -> Error(Nil)
  }
}

/// Deeper into a ravaged battleship: the elevator bank. Each wing's elevator
/// runs until that wing is dealt with; the command deck opens once all three
/// are.
fn antechamber() -> Event {
  Event(title: "A Ravaged Battleship", is_available: fn(_) { True }, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "a large hatch opens into a wide corridor.",
          "the corridor leads to a bank of elevators, which appear to be functional.",
        ]),
        buttons: [
          #("engineering", elevator("engineering")),
          #("medical", elevator("medical")),
          #("martial", elevator("martial")),
          #(
            "command",
            SceneButton(
              ..leave("command deck"),
              available: Some(fn(s) {
                state.get_game(s, "world.engineering") != 0
                && state.get_game(s, "world.medical") != 0
                && state.get_game(s, "world.martial") != 0
              }),
              next: events.GotoEvent("executioner-command"),
            ),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
  ])
}

/// A wing's elevator button: offered until the wing is dealt with
/// (`available: !World.state.<wing>`), riding `nextEvent` to it.
fn elevator(wing: String) -> SceneButton {
  SceneButton(
    ..leave(wing),
    available: Some(fn(s) { state.get_game(s, "world." <> wing) == 0 }),
    next: events.GotoEvent("executioner-" <> wing),
  )
}

/// The Engineering Wing: a blasted corridor forks past the assembly line, the
/// ruined engine room, or a live electrical fire, converging on the R&D lab,
/// its regenerative machine, and the unstable prototype.
fn engineering() -> Event {
  Event(title: "Engineering Wing", is_available: fn(_) { True }, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "elevator doors open to a blasted corridor. debris covers the floor, piled into makeshift defences.",
          "emergency lighting flickers.",
        ]),
        buttons: [
          #(
            "continue",
            branch("continue", [#(0.3, "1-1"), #(0.7, "1-2"), #(1.0, "1-3")]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    // The assembly line.
    #(
      "1-1",
      Scene(
        ..story([
          "an automated assembly line performs its empty routines, long since deprived of materials.",
          "its final works lie forgotten, covered by a thin layer of dust.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("energy cell", 1, 5, 0.8),
            combat.LootEntry("laser rifle", 1, 1, 0.2),
          ],
          events.NoWorldEffect,
        ),
        buttons: [
          #("continue", branch("continue", [#(0.5, "2-1a"), #(1.0, "2-1b")])),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "2-1a",
      guarded(
        "assembly arms spin wildly out of control.",
        enemy("unruly welder", "W", 50, 13, 0.8, 2.0, False, [
          combat.LootEntry("energy cell", 1, 5, 0.8),
          combat.LootEntry("alien alloy", 1, 1, 0.2),
        ]),
        "3-1",
      ),
    ),
    #(
      "2-1b",
      Scene(
        ..story([
          "assembly arms spark and jitter.",
          "a cacophony of decrepit machinery fills the room.",
        ]),
        buttons: continue_or_leave("3-1"),
      ),
    ),
    #("3-1", guard_post("4")),
    // The engine room.
    #("1-2", defence_turret("2-2")),
    #(
      "2-2",
      Scene(
        ..story([
          "must have been the engine room, once. the massive machines now stand inert, twisted and scorched by explosions.",
          "the destruction is uniform and precise.",
          "bits of them can be scavenged.",
        ]),
        setpiece: extra(
          [combat.LootEntry("alien alloy", 2, 5, 1.0)],
          events.NoWorldEffect,
        ),
        buttons: [
          #("continue", branch("continue", [#(0.5, "3-2a"), #(1.0, "3-2b")])),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #("3-2a", guard_post("4")),
    #(
      "3-2b",
      Scene(
        ..story([
          "none of the ship's engines escaped the destruction.",
          "it's no mystery why she no longer flies.",
        ]),
        buttons: continue_or_leave("4"),
      ),
    ),
    // The electrical fire — douse it with carried water, or run through.
    #(
      "1-3",
      Scene(
        ..story([
          "sparks cascade from a reactivated power junction, and catch.",
          "the flames fill the corridor.",
        ]),
        buttons: [
          #(
            "water",
            SceneButton(
              ..branch("extinguish", [#(0.5, "2-3a"), #(1.0, "2-3b")]),
              cost: [#("water", 5)],
            ),
          ),
          #(
            "run",
            SceneButton(
              ..branch("rush through", [#(0.5, "2-3a"), #(1.0, "2-3b")]),
              cost: [#("hp", 10)],
            ),
          ),
        ],
      ),
    ),
    #("2-3a", guard_post("3-3")),
    #(
      "2-3b",
      Scene(
        ..story([
          "rows of inert security robots hang suspended from the ceiling.",
          "wires run overhead, corroded and useless.",
        ]),
        buttons: continue_or_leave("3-3"),
      ),
    ),
    #(
      "3-3",
      passage(
        [
          "more signs of past combat down the hall. guard post is ransacked.",
          "still, some things can be found.",
        ],
        [
          combat.LootEntry("energy cell", 1, 5, 0.8),
          combat.LootEntry("laser rifle", 1, 1, 0.7),
          combat.LootEntry("grenade", 1, 3, 0.6),
          combat.LootEntry("plasma rifle", 1, 1, 0.2),
        ],
        "4",
      ),
    ),
    // Research and development.
    #(
      "4",
      Scene(
        ..story([
          "marks on the door read 'research and development.' everything seems mostly untouched, but dead.",
          "one machine thrums with power, and might still work.",
        ]),
        buttons: [
          #(
            "use",
            SceneButton(
              ..to("use machine", "4-heal"),
              cost: [#("alien alloy", 1)],
              effect: Some(events.HealToMax),
            ),
          ),
          #("continue", branch("continue", [#(0.5, "5-1"), #(1.0, "5-2")])),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "4-heal",
      Scene(
        ..story([
          "step inside, and the machine whirs. muscle and bone reknit. good as new.",
        ]),
        buttons: [
          #("continue", branch("continue", [#(0.5, "5-1"), #(1.0, "5-2")])),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #("5-1", defence_turret("6")),
    #(
      "5-2",
      Scene(
        ..story([
          "the machines here look unfinished, abandoned by their creator. wires and other scrap are scattered about the work benches.",
        ]),
        buttons: continue_or_leave("6"),
      ),
    ),
    #(
      "6",
      passage(
        [
          "experimental plans cover one wall, held by an unseen force.",
          "this one looks useful.",
        ],
        [combat.LootEntry("hypo blueprint", 1, 1, 1.0)],
        "7-intro",
      ),
    ),
    #(
      "7-intro",
      Scene(
        ..story(["clattering metal and old servos. something is coming..."]),
        buttons: [#("fight", to("fight", "7"))],
      ),
    ),
    #(
      "7",
      boss_fight(
        "an unfinished automaton whirs to life.",
        enemy("unstable prototype", "P", 150, 5, 0.8, 2.0, False, [
          combat.LootEntry("alien alloy", 1, 3, 1.0),
          combat.LootEntry("kinetic armour blueprint", 1, 1, 1.0),
        ]),
        [combat.SetStatusEvery(5.0, combat.Shield)],
        continue_or_leave("8"),
      ),
    ),
    #(
      "8",
      Scene(
        ..story([
          "at the back of the workshop, elevator doors twitch and buzz.",
          "looks like a way out of here.",
        ]),
        on_load: Some(fn(s) { #(state.set_game(s, "world.engineering", 1), []) }),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
  ])
}

// --- the shared garrison (Enemies.Executioner) ---------------------------------

/// `Enemies.Executioner.guard` — a mechanical guard scene, posted all over the
/// ship.
fn guard_post(next: String) -> Scene {
  guarded(
    "tripped a motion sensor.",
    enemy("mechanical guard", "G", 60, 10, 0.8, 2.0, True, [
      combat.LootEntry("energy cell", 1, 5, 0.8),
      combat.LootEntry("laser rifle", 1, 1, 0.8),
      combat.LootEntry("alien alloy", 1, 1, 0.2),
    ]),
    next,
  )
}

/// `Enemies.Executioner.turret` — a still-working defence turret scene.
fn defence_turret(next: String) -> Scene {
  guarded(
    "one of the defence turrets still works.",
    enemy("defence turret", "T", 50, 25, 0.8, 4.0, True, [
      combat.LootEntry("energy cell", 1, 5, 0.8),
      combat.LootEntry("alien alloy", 1, 1, 0.8),
      combat.LootEntry("laser rifle", 1, 1, 0.2),
    ]),
    next,
  )
}

/// Exploring a ravaged battleship: a torch-lit descent through one of three
/// infested corridors to the maintenance panel, the turret it wakes, and the
/// strange device beyond — taking it unseals the ship for good.
fn intro() -> Event {
  Event(title: "A Ravaged Battleship", is_available: fn(_) { True }, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "the remains of a massive battleship lie here, like a silent sealed city.",
          "it lists to the side in a deep crevasse, cut when it fell from the sky.",
          "the hatches are all sealed, but the hull is blown out just above the dirt, providing an entrance.",
        ]),
        notification: Some(
          "the remains of a huge ship are embedded in the earth.",
        ),
        buttons: [
          #("enter", spend("enter", [#("torch", 1)], "1")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "1",
      Scene(
        ..story([
          "the interior of the ship is cold and dark. what little light there is only accentuates its harsh angles.",
          "the walls hum faintly.",
        ]),
        buttons: [
          #(
            "continue",
            branch("continue", [
              #(0.4, "2-1"),
              #(0.8, "2-2"),
              #(1.0, "2-3"),
            ]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    // The webbed corridor.
    #(
      "2-1",
      passage(
        [
          "thick, sticky webbing covers the walls of the corridor.",
          "deeper into the ship, the darkness seems almost to writhe.",
          "a small knapsack hangs from a cluster of webs, a few feet from the floor.",
        ],
        [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.5),
          combat.LootEntry("energy cell", 1, 5, 0.2),
        ],
        "3-1",
      ),
    ),
    #(
      "3-1",
      guarded(
        "a huge arthropod lunges from the shadows, its mandibles thrashing.",
        enemy("chitinous horror", "H", 60, 1, 0.7, 0.25, False, [
          combat.LootEntry("meat", 5, 10, 0.8),
          combat.LootEntry("scales", 5, 10, 0.5),
        ]),
        "4-1",
      ),
    ),
    #(
      "4-1",
      guarded(
        "the webs part, and a grotesque insect lurches forward.",
        enemy("chitinous queen", "Q", 70, 1, 0.7, 0.25, False, [
          combat.LootEntry("meat", 8, 12, 0.8),
          combat.LootEntry("scales", 8, 12, 0.5),
        ]),
        "5",
      ),
    ),
    // The military corridor.
    #(
      "2-2",
      guarded(
        "an operative waits in ambush around the corner.",
        enemy("operative", "O", 60, 8, 0.8, 2.0, False, [
          combat.LootEntry("bayonet", 1, 1, 0.5),
          combat.LootEntry("bullets", 1, 5, 0.8),
          combat.LootEntry("cured meat", 1, 5, 0.8),
        ]),
        "3-2",
      ),
    ),
    #(
      "3-2",
      passage(
        [
          "the military has set up a small camp just inside the ship.",
          "crude attempts have been made to cut into the walls.",
          "scraps of copper wire litter the floor.",
          "two bedrolls are wedged into a corner.",
        ],
        [
          combat.LootEntry("cured meat", 1, 5, 1.0),
          combat.LootEntry("torch", 1, 3, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.5),
          combat.LootEntry("alien alloy", 1, 2, 0.2),
        ],
        "4-2",
      ),
    ),
    #(
      "4-2",
      guarded(
        "a dusty researcher clumsily hides in the shadows.",
        enemy("researcher", "R", 20, 1, 0.8, 2.0, False, [
          combat.LootEntry("torch", 1, 3, 0.8),
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("cured meat", 1, 5, 0.8),
        ]),
        "5",
      ),
    ),
    // The scorched corridor.
    #(
      "2-3",
      passage(
        [
          "debris is stacked in the corridor, forming a low barricade.",
          "the walls are scorched and melted.",
          "behind the barricade, a few weapons lay abandoned.",
        ],
        [
          combat.LootEntry("laser rifle", 1, 3, 1.0),
          combat.LootEntry("energy cell", 1, 5, 0.8),
          combat.LootEntry("plasma rifle", 1, 1, 0.2),
        ],
        "3-3",
      ),
    ),
    #(
      "3-3",
      passage(
        [
          "the partially devoured remains of several wanderers are piled before a dark corridor.",
          "shuffling noises can be heard from within.",
        ],
        [
          combat.LootEntry("energy cell", 1, 5, 0.5),
          combat.LootEntry("cloth", 1, 5, 0.8),
        ],
        "4-3",
      ),
    ),
    #(
      "4-3",
      guarded(
        "an ancient beast has made these ruins its home.",
        enemy("ancient beast", "A", 60, 6, 0.8, 1.0, False, [
          combat.LootEntry("fur", 5, 10, 1.0),
          combat.LootEntry("meat", 5, 10, 1.0),
          combat.LootEntry("teeth", 5, 10, 0.8),
        ]),
        "5",
      ),
    ),
    // The corridors converge on the maintenance panel.
    #(
      "5",
      Scene(
        ..story([
          "a maintenance panel is embedded in the wall next to a large sealed door.",
          "perhaps the ship’s systems are still operational.",
        ]),
        buttons: [
          #("power", to("power cycle", "6")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "6",
      guarded(
        "as the lights come online, so too do the defence systems.",
        enemy("automated turret", "T", 60, 10, 0.8, 2.5, True, [
          combat.LootEntry("energy cell", 1, 5, 0.8),
          combat.LootEntry("laser rifle", 1, 1, 0.2),
        ]),
        "7",
      ),
    ),
    #(
      "7",
      Scene(
        ..story([
          "beyond the bulkhead is a small antechamber, seemingly untouched by scavengers.",
          "a large hatch grinds open, and the wind rushes in.",
          "a strange device sits on the floor. looks important.",
        ]),
        setpiece: extra([], events.FoundExecutioner),
        buttons: [#("leave", leave("take device and leave"))],
      ),
    ),
  ])
}

// --- builders (the setpieces' local idiom) ------------------------------------

/// A bare story scene to extend with `..story(text)`.
fn story(text: List(String)) -> Scene {
  Scene(
    text: text,
    notification: None,
    reward: [],
    buttons: [],
    combat: False,
    on_load: None,
    on_load_rng: None,
    setpiece: None,
  )
}

/// A story scene with loot to scavenge on entry, a way deeper and a way out.
fn passage(
  text: List(String),
  loot: List(combat.LootEntry),
  next: String,
) -> Scene {
  Scene(..story(text), setpiece: extra(loot, events.NoWorldEffect), buttons: [
    #("continue", to("continue", next)),
    #("leave", leave("leave")),
  ])
}

/// A combat scene: the fight begins on entry; once won, the way deeper and the
/// way out appear.
fn guarded(notification: String, foe: combat.Enemy, next: String) -> Scene {
  Scene(
    text: [],
    notification: Some(notification),
    reward: [],
    buttons: [#("continue", to("continue", next)), #("leave", leave("leave"))],
    combat: True,
    on_load: None,
    on_load_rng: None,
    setpiece: Some(
      SetpieceExtra(
        loot: [],
        world_effect: events.NoWorldEffect,
        enemy: Some(foe),
        specials: [],
        at_health: [],
      ),
    ),
  )
}

/// A wing boss: a combat scene whose enemy fights with recurring specials.
fn boss_fight(
  notification: String,
  foe: combat.Enemy,
  specials: List(combat.Special),
  buttons: List(#(String, SceneButton)),
) -> Scene {
  Scene(
    text: [],
    notification: Some(notification),
    reward: [],
    buttons: buttons,
    combat: True,
    on_load: None,
    on_load_rng: None,
    setpiece: Some(
      SetpieceExtra(
        loot: [],
        world_effect: events.NoWorldEffect,
        enemy: Some(foe),
        specials: specials,
        at_health: [],
      ),
    ),
  )
}

/// The plain way deeper and the way out.
fn continue_or_leave(next: String) -> List(#(String, SceneButton)) {
  [#("continue", to("continue", next)), #("leave", leave("leave"))]
}

/// A story scene's extras: loot granted on entry plus a world `onLoad` effect.
fn extra(
  loot: List(combat.LootEntry),
  world_effect: events.WorldEffect,
) -> option.Option(SetpieceExtra) {
  Some(
    SetpieceExtra(
      loot: loot,
      world_effect: world_effect,
      enemy: None,
      specials: [],
      at_health: [],
    ),
  )
}

/// An inline enemy. No death message — the scene's buttons take over on the win.
fn enemy(
  name: String,
  chara: String,
  health: Int,
  damage: Int,
  hit: Float,
  attack_delay: Float,
  ranged: Bool,
  loot: List(combat.LootEntry),
) -> combat.Enemy {
  combat.Enemy(
    name: name,
    chara: chara,
    health: health,
    damage: damage,
    hit: hit,
    attack_delay: attack_delay,
    ranged: ranged,
    death_message: "",
    loot: loot,
  )
}

/// A button that ends the event.
fn leave(text: String) -> SceneButton {
  SceneButton(
    text: text,
    cost: [],
    reward: [],
    notification: None,
    available: None,
    link: None,
    effect: None,
    on_click: None,
    next: End,
  )
}

/// A button that always moves to another scene (the `{1: scene}` map).
fn to(text: String, scene: String) -> SceneButton {
  SceneButton(..leave(text), next: Branch([#(1.0, scene)]))
}

/// A button that spends a cost on the way to another scene.
fn spend(text: String, cost: List(#(String, Int)), scene: String) -> SceneButton {
  SceneButton(..to(text, scene), cost: cost)
}

/// A button that branches to one of several scenes by probability.
fn branch(text: String, targets: List(#(Float, String))) -> SceneButton {
  SceneButton(..leave(text), next: Branch(targets))
}
