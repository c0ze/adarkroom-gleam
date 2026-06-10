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
import gleam/option.{None, Some}

/// The event for a registry key (`Events.Executioner[...]`). The antechamber,
/// wings and command deck arrive in later increments.
pub fn event(key: String) -> Result(Event, Nil) {
  case key {
    "executioner-intro" -> Ok(intro())
    _ -> Error(Nil)
  }
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
