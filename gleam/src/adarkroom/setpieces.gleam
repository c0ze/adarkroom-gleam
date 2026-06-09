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
  type Event, type Scene, type SceneButton, type SetpieceExtra, Branch, End,
  Event, FoundShip, MarkVisited, RefillSupplies, Scene, SceneButton,
  SetpieceExtra, UseOutpost,
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
    #("house", house()),
    #("ship", ship()),
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
