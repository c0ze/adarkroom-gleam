//// The setpieces, ported from `events/setpieces.js`.
////
//// Setpieces are the scripted multi-scene landmark events: an outpost, a swamp,
//// a battlefield, a borehole, and (in later work) the caves, mines, towns and
//// cities. Unlike the random events they are launched manually — the model
//// fires one when the expedition steps onto a landmark tile (`World.doSpace`).
////
//// They reuse the event/scene runtime wholesale; the setpiece-only machinery —
//// a loot table granted on entry and a world-level `onLoad` (marking a landmark
//// visited, draining an outpost) — rides on `events.Scene.setpiece`.

import adarkroom/combat
import adarkroom/events.{
  type Event, type Scene, type SceneButton, type SetpieceExtra, Branch,
  ClearDungeon, ClearMine, End, Event, FoundShip, MarkVisited, NoWorldEffect,
  RefillSupplies, Scene, SceneButton, SetpieceExtra, UseOutpost,
}
import adarkroom/state
import gleam/list
import gleam/option.{None, Some}

/// The setpiece for a landmark's registry key (`World.LANDMARKS[tile].scene`),
/// if it has been ported. The model looks it up on arrival.
pub fn setpiece(name: String) -> Result(Event, Nil) {
  list.key_find(setpieces(), name)
}

/// The ported setpieces, keyed by their `World.LANDMARKS` scene name. The combat
/// dungeons (cave, mines, town, city) and the ship/cache join this as they land.
fn setpieces() -> List(#(String, Event)) {
  [
    #("outpost", outpost()),
    #("swamp", swamp()),
    #("battlefield", battlefield()),
    #("borehole", borehole()),
    #("cave", cave()),
    #("house", house()),
    #("ship", ship()),
    #("sulphurmine", sulphurmine()),
    #("coalmine", coalmine()),
    #("ironmine", ironmine()),
  ]
}

// --- the setpieces ----------------------------------------------------------

/// A safe place in the wilds: refill water once, take a little cured meat, go.
fn outpost() -> Event {
  Event(title: "An Outpost", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story(["a safe place in the wilds."]),
        notification: Some("a safe place in the wilds."),
        setpiece: extra(
          [combat.LootEntry("cured meat", 5, 10, 1.0)],
          UseOutpost,
        ),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
  ])
}

/// A murky swamp: a charm buys the old wanderer's tale and the gastronome perk.
fn swamp() -> Event {
  Event(title: "A Murky Swamp", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "rotting reeds rise out of the swampy earth.",
          "a lone frog sits in the muck, silently.",
        ]),
        notification: Some("a swamp festers in the stagnant air."),
        buttons: [
          #("enter", to("enter", "cabin")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "cabin",
      Scene(
        ..story([
          "deep in the swamp is a moss-covered cabin.",
          "an old wanderer sits inside, in a seeming trance.",
        ]),
        buttons: [
          #("talk", spend("talk", [#("charm", 1)], "talk")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "talk",
      Scene(
        ..story([
          "the wanderer takes the charm and nods slowly.",
          "he speaks of once leading the great fleets to fresh worlds.",
          "unfathomable destruction to fuel wanderer hungers.",
          "his time here, now, is his penance.",
        ]),
        on_load: Some(fn(s) { #(state.add_perk(s, "gastronome"), []) }),
        setpiece: extra([], MarkVisited),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
  ])
}

/// A forgotten battlefield: pick the dormant tech off the blasted ground.
fn battlefield() -> Event {
  Event(title: "A Forgotten Battlefield", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "a battle was fought here, long ago.",
          "battered technology from both sides lays dormant on the blasted landscape.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("rifle", 1, 3, 0.5),
            combat.LootEntry("bullets", 5, 20, 0.8),
            combat.LootEntry("laser rifle", 1, 3, 0.3),
            combat.LootEntry("energy cell", 5, 10, 0.5),
            combat.LootEntry("grenade", 1, 5, 0.5),
            combat.LootEntry("alien alloy", 1, 1, 0.3),
          ],
          MarkVisited,
        ),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
  ])
}

/// A huge borehole: castoff alien alloy lies at the edge of the precipice.
fn borehole() -> Event {
  Event(title: "A Huge Borehole", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "a huge hole is cut deep into the earth, evidence of the past harvest.",
          "they took what they came for, and left.",
          "castoff from the mammoth drills can still be found by the edges of the precipice.",
        ]),
        setpiece: extra(
          [combat.LootEntry("alien alloy", 1, 3, 1.0)],
          MarkVisited,
        ),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
  ])
}

/// A damp cave: the deepest of the wild dungeons. Spend a torch to delve, fight
/// through beasts and lizards, and clear it into an outpost for one of three
/// hoards at the back.
fn cave() -> Event {
  let beast = fn(hp, loot, next) {
    fight(
      "a startled beast defends its home",
      NoWorldEffect,
      enemy("beast", "R", hp, 1, 0.8, 1, False, loot),
      continue_or_leave(next),
    )
  }
  Event(title: "A Damp Cave", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "the mouth of the cave is wide and dark.",
          "can't see what's inside.",
        ]),
        notification: Some(
          "the earth here is split, as if bearing an ancient wound",
        ),
        buttons: [
          #(
            "enter",
            cost_branch("go inside", [#("torch", 1)], [
              #(0.3, "a1"),
              #(0.6, "a2"),
              #(1.0, "a3"),
            ]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "a1",
      beast(
        5,
        [
          combat.LootEntry("fur", 1, 10, 1.0),
          combat.LootEntry("teeth", 1, 5, 0.8),
        ],
        [#(0.5, "b1"), #(1.0, "b2")],
      ),
    ),
    #(
      "a2",
      Scene(
        ..story([
          "the cave narrows a few feet in.",
          "the walls are moist and moss-covered",
        ]),
        buttons: continue_or_leave([#(0.5, "b2"), #(1.0, "b3")]),
      ),
    ),
    #(
      "a3",
      hoard(
        [
          "the remains of an old camp sits just inside the cave.",
          "bedrolls, torn and blackened, lay beneath a thin layer of dust.",
        ],
        [
          combat.LootEntry("cured meat", 1, 5, 1.0),
          combat.LootEntry("torch", 1, 5, 0.5),
          combat.LootEntry("leather", 1, 5, 0.3),
        ],
        continue_or_leave([#(0.5, "b3"), #(1.0, "b4")]),
      ),
    ),
    #(
      "b1",
      hoard(
        [
          "the body of a wanderer lies in a small cavern.",
          "rot's been to work on it, and some of the pieces are missing.",
          "can't tell what left it here.",
        ],
        [
          combat.LootEntry("iron sword", 1, 1, 1.0),
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("torch", 1, 3, 0.5),
          combat.LootEntry("medicine", 1, 2, 0.1),
        ],
        continue_or_leave([#(1.0, "c1")]),
      ),
    ),
    #(
      "b2",
      Scene(
        ..story([
          "the torch sputters and dies in the damp air",
          "the darkness is absolute",
        ]),
        notification: Some("the torch goes out"),
        buttons: [
          #("continue", spend("continue", [#("torch", 1)], "c1")),
          #("leave", leave("leave cave")),
        ],
      ),
    ),
    #(
      "b3",
      beast(
        5,
        [
          combat.LootEntry("fur", 1, 3, 1.0),
          combat.LootEntry("teeth", 1, 2, 0.8),
        ],
        [#(1.0, "c2")],
      ),
    ),
    #(
      "b4",
      fight(
        "a cave lizard attacks",
        NoWorldEffect,
        enemy("cave lizard", "R", 6, 3, 0.8, 2, False, [
          combat.LootEntry("scales", 1, 3, 1.0),
          combat.LootEntry("teeth", 1, 2, 0.8),
        ]),
        continue_or_leave([#(1.0, "c2")]),
      ),
    ),
    #(
      "c1",
      fight(
        "a large beast charges out of the dark",
        NoWorldEffect,
        enemy("beast", "R", 10, 3, 0.8, 2, False, [
          combat.LootEntry("fur", 1, 3, 1.0),
          combat.LootEntry("teeth", 1, 3, 1.0),
        ]),
        continue_or_leave([#(0.5, "end1"), #(1.0, "end2")]),
      ),
    ),
    #(
      "c2",
      fight(
        "a giant lizard shambles forward",
        NoWorldEffect,
        enemy("lizard", "T", 10, 4, 0.8, 2, False, [
          combat.LootEntry("scales", 1, 3, 1.0),
          combat.LootEntry("teeth", 1, 3, 1.0),
        ]),
        continue_or_leave([#(0.7, "end2"), #(1.0, "end3")]),
      ),
    ),
    #(
      "end1",
      cleared_cave(
        ["the nest of a large animal lies at the back of the cave."],
        [
          combat.LootEntry("meat", 5, 10, 1.0),
          combat.LootEntry("fur", 5, 10, 1.0),
          combat.LootEntry("scales", 5, 10, 1.0),
          combat.LootEntry("teeth", 5, 10, 1.0),
          combat.LootEntry("cloth", 5, 10, 0.5),
        ],
      ),
    ),
    #(
      "end2",
      cleared_cave(["a small supply cache is hidden at the back of the cave."], [
        combat.LootEntry("cloth", 5, 10, 1.0),
        combat.LootEntry("leather", 5, 10, 1.0),
        combat.LootEntry("iron", 5, 10, 1.0),
        combat.LootEntry("cured meat", 5, 10, 1.0),
        combat.LootEntry("steel", 5, 10, 0.5),
        combat.LootEntry("bolas", 1, 3, 0.3),
        combat.LootEntry("medicine", 1, 4, 0.15),
      ]),
    ),
    #(
      "end3",
      cleared_cave(
        [
          "an old case is wedged behind a rock, covered in a thick layer of dust.",
        ],
        [
          combat.LootEntry("steel sword", 1, 1, 1.0),
          combat.LootEntry("bolas", 1, 3, 0.5),
          combat.LootEntry("medicine", 1, 3, 0.3),
        ],
      ),
    ),
  ])
}

/// A cave room with loot taken on entry, then a continue/leave choice.
fn hoard(
  text: List(String),
  loot: List(combat.LootEntry),
  buttons: List(#(String, SceneButton)),
) -> Scene {
  Scene(..story(text), setpiece: extra(loot, NoWorldEffect), buttons:)
}

/// The back of the cave: take the hoard and clear the cave into an outpost.
fn cleared_cave(text: List(String), loot: List(combat.LootEntry)) -> Scene {
  Scene(..story(text), setpiece: extra(loot, ClearDungeon), buttons: [
    #("leave", leave("leave cave")),
  ])
}

/// The cave's recurring pair of buttons: press on (by probability) or leave.
fn continue_or_leave(
  next: List(#(Float, String)),
) -> List(#(String, SceneButton)) {
  [#("continue", branch("continue", next)), #("leave", leave("leave cave"))]
}

/// A crashed wanderer ship: road it home and note the way off this rock. The
/// salvage itself (the spaceship) waits for the endgame.
fn ship() -> Event {
  Event(title: "A Crashed Ship", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "the familiar curves of a wanderer vessel rise up out of the dust and ash.",
          "lucky that the natives can't work the mechanisms.",
          "with a little effort, it might fly again.",
        ]),
        setpiece: extra([], FoundShip),
        buttons: [#("leave", leave("salvage"))],
      ),
    ),
  ])
}

/// An old house: water in the well, medicine under the floorboards, or a
/// squatter with a rusty blade — the first combat setpiece.
fn house() -> Event {
  Event(title: "An Old House", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "an old house remains here, once white siding yellowed and peeling.",
          "the door hangs open.",
        ]),
        notification: Some(
          "the remains of an old house stand as a monument to simpler times",
        ),
        buttons: [
          #(
            "enter",
            branch("go inside", [
              #(0.25, "medicine"),
              #(0.5, "supplies"),
              #(1.0, "occupied"),
            ]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "supplies",
      Scene(
        ..story([
          "the house is abandoned, but not yet picked over.",
          "still a few drops of water in the old well.",
        ]),
        setpiece: extra(house_loot(), RefillSupplies),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
    #(
      "medicine",
      Scene(
        ..story([
          "the house has been ransacked.",
          "but there is a cache of medicine under the floorboards.",
        ]),
        setpiece: extra([combat.LootEntry("medicine", 2, 5, 1.0)], MarkVisited),
        buttons: [#("leave", leave("leave"))],
      ),
    ),
    #(
      "occupied",
      fight(
        "a man charges down the hall, a rusty blade in his hand",
        MarkVisited,
        enemy("squatter", "E", 10, 3, 0.8, 2, False, house_loot()),
        [#("leave", leave("leave"))],
      ),
    ),
  ])
}

/// The drops shared by the house's well and its squatter.
fn house_loot() -> List(combat.LootEntry) {
  [
    combat.LootEntry("cured meat", 1, 10, 0.8),
    combat.LootEntry("leather", 1, 10, 0.2),
    combat.LootEntry("cloth", 1, 10, 0.5),
  ]
}

// --- the mines --------------------------------------------------------------

/// The sulphur mine: a military perimeter — two soldiers and a veteran stand
/// between you and the deposit.
fn sulphurmine() -> Event {
  let soldier_loot = [
    combat.LootEntry("cured meat", 1, 5, 0.8),
    combat.LootEntry("bullets", 1, 5, 0.5),
    combat.LootEntry("rifle", 1, 1, 0.2),
  ]
  let soldier = fn(notification, next) {
    fight(
      notification,
      NoWorldEffect,
      enemy("soldier", "D", 50, 8, 0.8, 2, True, soldier_loot),
      [#("continue", to("continue", next)), #("run", leave("run"))],
    )
  }
  Event(title: "The Sulphur Mine", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "the military is already set up at the mine's entrance.",
          "soldiers patrol the perimeter, rifles slung over their shoulders.",
        ]),
        notification: Some("a military perimeter is set up around the mine."),
        buttons: [
          #("attack", to("attack", "a1")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #("a1", soldier("a soldier, alerted, opens fire.", "a2")),
    #("a2", soldier("a second soldier joins the fight.", "a3")),
    #(
      "a3",
      fight(
        "a grizzled soldier attacks, waving a bayonet.",
        NoWorldEffect,
        enemy("veteran", "D", 65, 10, 0.8, 2, False, [
          combat.LootEntry("bayonet", 1, 1, 0.5),
          combat.LootEntry("cured meat", 1, 5, 0.8),
        ]),
        [#("continue", to("continue", "cleared"))],
      ),
    ),
    #(
      "cleared",
      cleared(
        [
          "the military presence has been cleared.",
          "the mine is now safe for workers.",
        ],
        "the sulphur mine is clear of dangers",
        "sulphur mine",
      ),
    ),
  ])
}

/// The coal mine: a camp of armed men, led by their chief.
fn coalmine() -> Event {
  let man_loot = [
    combat.LootEntry("cured meat", 1, 5, 0.8),
    combat.LootEntry("cloth", 1, 5, 0.8),
  ]
  let man = fn(next) {
    fight(
      "a man joins the fight",
      NoWorldEffect,
      enemy("man", "E", 10, 3, 0.8, 2, False, man_loot),
      [#("continue", to("continue", next)), #("run", leave("run"))],
    )
  }
  Event(title: "The Coal Mine", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "camp fires burn by the entrance to the mine.",
          "men mill about, weapons at the ready.",
        ]),
        notification: Some("this old mine is not abandoned"),
        buttons: [
          #("attack", to("attack", "a1")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #("a1", man("a2")),
    #("a2", man("a3")),
    #(
      "a3",
      fight(
        "only the chief remains.",
        NoWorldEffect,
        enemy("chief", "D", 20, 5, 0.8, 2, False, [
          combat.LootEntry("cured meat", 5, 10, 1.0),
          combat.LootEntry("cloth", 5, 10, 0.8),
          combat.LootEntry("iron", 1, 5, 0.8),
        ]),
        [#("continue", to("continue", "cleared"))],
      ),
    ),
    #(
      "cleared",
      cleared(
        [
          "the camp is still, save for the crackling of the fires.",
          "the mine is now safe for workers.",
        ],
        "the coal mine is clear of dangers",
        "coal mine",
      ),
    ),
  ])
}

/// The iron mine: a single feral beast lairs in the dark — bring a torch.
fn ironmine() -> Event {
  Event(title: "The Iron Mine", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "an old iron mine sits here, tools abandoned and left to rust.",
          "bleached bones are strewn about the entrance. many, deeply scored with jagged grooves.",
          "feral howls echo out of the darkness.",
        ]),
        notification: Some("the path leads to an abandoned mine"),
        buttons: [
          #("enter", spend("go inside", [#("torch", 1)], "enter")),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "enter",
      fight(
        "a large creature lunges, muscles rippling in the torchlight",
        NoWorldEffect,
        enemy("beastly matriarch", "T", 10, 4, 0.8, 2, False, [
          combat.LootEntry("teeth", 5, 10, 1.0),
          combat.LootEntry("scales", 5, 10, 0.8),
          combat.LootEntry("cloth", 5, 10, 0.5),
        ]),
        [#("leave", to("leave", "cleared"))],
      ),
    ),
    #(
      "cleared",
      cleared(
        ["the beast is dead.", "the mine is now safe for workers."],
        "the iron mine is clear of dangers",
        "iron mine",
      ),
    ),
  ])
}

/// A mine's final scene: road it home, flag the building for the trip home to
/// grant, and mark the landmark dealt with.
fn cleared(text: List(String), notification: String, mine: String) -> Scene {
  Scene(
    ..story(text),
    notification: Some(notification),
    setpiece: extra([], ClearMine(mine)),
    buttons: [#("leave", leave("leave"))],
  )
}

// --- builders ---------------------------------------------------------------

/// Setpieces are launched by the world on arrival, never by the event
/// scheduler, so their availability is moot — always offered.
fn always(_s: state.State) -> Bool {
  True
}

/// A bare prose scene with sensible empty defaults; the callers override the
/// fields they need with record-update syntax.
fn story(text: List(String)) -> Scene {
  Scene(
    text: text,
    notification: None,
    reward: [],
    buttons: [],
    combat: False,
    on_load: None,
    setpiece: None,
  )
}

/// A story scene's extras: a loot table (granted on entry) and a world `onLoad`
/// effect. No inline enemy.
fn extra(
  loot: List(combat.LootEntry),
  world_effect: events.WorldEffect,
) -> option.Option(SetpieceExtra) {
  Some(SetpieceExtra(loot: loot, world_effect: world_effect, enemy: None))
}

/// A button that ends the setpiece.
fn leave(text: String) -> SceneButton {
  SceneButton(
    text: text,
    cost: [],
    reward: [],
    notification: None,
    available: None,
    on_click: None,
    next: End,
  )
}

/// A button that always moves to another scene (the `{1: scene}` map).
fn to(text: String, scene: String) -> SceneButton {
  SceneButton(
    text: text,
    cost: [],
    reward: [],
    notification: None,
    available: None,
    on_click: None,
    next: Branch([#(1.0, scene)]),
  )
}

/// A button that spends a cost on the way to another scene.
fn spend(text: String, cost: List(#(String, Int)), scene: String) -> SceneButton {
  SceneButton(
    text: text,
    cost: cost,
    reward: [],
    notification: None,
    available: None,
    on_click: None,
    next: Branch([#(1.0, scene)]),
  )
}

/// A button that branches to one of several scenes by probability (the JS
/// `nextScene` map, e.g. `{0.25: a, 0.5: b, 1: c}`).
fn branch(text: String, targets: List(#(Float, String))) -> SceneButton {
  SceneButton(
    text: text,
    cost: [],
    reward: [],
    notification: None,
    available: None,
    on_click: None,
    next: Branch(targets),
  )
}

/// A button that spends a cost on the way to one of several scenes by
/// probability (the cave's torch-lit descent).
fn cost_branch(
  text: String,
  cost: List(#(String, Int)),
  targets: List(#(Float, String)),
) -> SceneButton {
  SceneButton(
    text: text,
    cost: cost,
    reward: [],
    notification: None,
    available: None,
    on_click: None,
    next: Branch(targets),
  )
}

/// A combat scene: entering it begins a fight with `enemy` (whose loot lands on
/// the win); its world `onLoad` still runs, and the buttons appear once the
/// fight is won.
fn fight(
  notification: String,
  world_effect: events.WorldEffect,
  foe: combat.Enemy,
  buttons: List(#(String, SceneButton)),
) -> Scene {
  Scene(
    text: [],
    notification: Some(notification),
    reward: [],
    buttons: buttons,
    combat: True,
    on_load: None,
    setpiece: Some(SetpieceExtra(loot: [], world_effect:, enemy: Some(foe))),
  )
}

/// An inline setpiece enemy. No death message — the scene's buttons take over
/// once the fight is won.
fn enemy(
  name: String,
  chara: String,
  health: Int,
  damage: Int,
  hit: Float,
  attack_delay: Int,
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
