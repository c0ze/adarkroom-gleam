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
  Event, MarkVisited, Scene, SceneButton, SetpieceExtra, UseOutpost,
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

/// The setpiece extras: a loot table and a world `onLoad` effect.
fn extra(
  loot: List(combat.LootEntry),
  world_effect: events.WorldEffect,
) -> option.Option(SetpieceExtra) {
  Some(SetpieceExtra(loot: loot, world_effect: world_effect))
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
