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
    #("town", town()),
    #("city", city()),
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
      enemy("beast", "R", hp, 1, 0.8, 1.0, False, loot),
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
        enemy("cave lizard", "R", 6, 3, 0.8, 2.0, False, [
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
        enemy("beast", "R", 10, 3, 0.8, 2.0, False, [
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
        enemy("lizard", "T", 10, 4, 0.8, 2.0, False, [
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

/// A deserted town: a sprawling suburb of scorched houses, a schoolhouse and an
/// old clinic. Thugs, scavengers, beasts and a vigilante prowl its three forks;
/// clear it into an outpost for one of six caches.
fn town() -> Event {
  let thug_loot = [
    combat.LootEntry("cloth", 5, 10, 0.8),
    combat.LootEntry("leather", 5, 10, 0.8),
    combat.LootEntry("cured meat", 1, 5, 0.5),
  ]
  let beast_loot = [
    combat.LootEntry("teeth", 1, 5, 1.0),
    combat.LootEntry("fur", 5, 10, 1.0),
  ]
  let panic_loot = [
    combat.LootEntry("cured meat", 1, 5, 1.0),
    combat.LootEntry("leather", 5, 10, 0.8),
    combat.LootEntry("steel sword", 1, 1, 0.5),
  ]
  Event(title: "A Deserted Town", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "a small suburb lays ahead, empty houses scorched and peeling.",
          "broken streetlights stand, rusting. light hasn't graced this place in a long time.",
        ]),
        notification: Some("the town lies abandoned, its citizens long dead"),
        buttons: [
          #(
            "enter",
            branch("explore", [#(0.3, "a1"), #(0.7, "a3"), #(1.0, "a2")]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "a1",
      Scene(
        ..story([
          "where the windows of the schoolhouse aren't shattered, they're blackened with soot.",
          "the double doors creak endlessly in the wind.",
        ]),
        buttons: torch_into([#(0.5, "b1"), #(1.0, "b2")]),
      ),
    ),
    #(
      "a2",
      fight(
        "ambushed on the street.",
        NoWorldEffect,
        enemy("thug", "E", 30, 4, 0.8, 2.0, False, thug_loot),
        town_choice([#(0.5, "b3"), #(1.0, "b4")]),
      ),
    ),
    #(
      "a3",
      Scene(
        ..story([
          "a squat building up ahead.",
          "a green cross barely visible behind grimy windows.",
        ]),
        buttons: torch_into([#(0.5, "b5"), #(1.0, "end5")]),
      ),
    ),
    #(
      "b1",
      hoard(
        ["a small cache of supplies is tucked inside a rusting locker."],
        [
          combat.LootEntry("cured meat", 1, 5, 1.0),
          combat.LootEntry("torch", 1, 3, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.3),
          combat.LootEntry("medicine", 1, 3, 0.05),
        ],
        town_choice([#(0.5, "c1"), #(1.0, "c2")]),
      ),
    ),
    #(
      "b2",
      fight(
        "a scavenger waits just inside the door.",
        NoWorldEffect,
        enemy("scavenger", "E", 30, 4, 0.8, 2.0, False, thug_loot),
        town_choice([#(0.5, "c2"), #(1.0, "c3")]),
      ),
    ),
    #(
      "b3",
      fight(
        "a beast stands alone in an overgrown park.",
        NoWorldEffect,
        enemy("beast", "R", 25, 3, 0.8, 1.0, False, beast_loot),
        town_choice([#(0.5, "c4"), #(1.0, "c5")]),
      ),
    ),
    #(
      "b4",
      hoard(
        [
          "an overturned caravan is spread across the pockmarked street.",
          "it's been picked over by scavengers, but there's still some things worth taking.",
        ],
        [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("torch", 1, 3, 0.5),
          combat.LootEntry("bullets", 1, 5, 0.3),
          combat.LootEntry("medicine", 1, 3, 0.1),
        ],
        town_choice([#(0.5, "c5"), #(1.0, "c6")]),
      ),
    ),
    #(
      "b5",
      fight(
        "a madman attacks, screeching.",
        NoWorldEffect,
        enemy("madman", "E", 10, 6, 0.3, 1.0, False, [
          combat.LootEntry("cloth", 2, 4, 0.3),
          combat.LootEntry("cured meat", 1, 5, 0.9),
          combat.LootEntry("medicine", 1, 2, 0.4),
        ]),
        town_choice([#(0.3, "end5"), #(1.0, "end6")]),
      ),
    ),
    #(
      "c1",
      fight(
        "a thug moves out of the shadows.",
        NoWorldEffect,
        enemy("thug", "E", 30, 4, 0.8, 2.0, False, thug_loot),
        town_choice([#(1.0, "d1")]),
      ),
    ),
    #(
      "c2",
      fight(
        "a beast charges out of a ransacked classroom.",
        NoWorldEffect,
        enemy("beast", "R", 25, 3, 0.8, 1.0, False, beast_loot),
        town_choice([#(1.0, "d1")]),
      ),
    ),
    #(
      "c3",
      Scene(
        ..story([
          "through the large gymnasium doors, footsteps can be heard.",
          "the torchlight casts a flickering glow down the hallway.",
          "the footsteps stop.",
        ]),
        buttons: [
          #("continue", branch("enter", [#(1.0, "d1")])),
          #("leave", leave("leave town")),
        ],
      ),
    ),
    #(
      "c4",
      fight(
        "another beast, draw by the noise, leaps out of a copse of trees.",
        NoWorldEffect,
        enemy("beast", "R", 25, 4, 0.8, 1.0, False, beast_loot),
        town_choice([#(1.0, "d2")]),
      ),
    ),
    #(
      "c5",
      Scene(
        ..story([
          "something's causing a commotion a ways down the road.",
          "a fight, maybe.",
        ]),
        buttons: town_choice([#(1.0, "d2")]),
      ),
    ),
    #(
      "c6",
      hoard(
        [
          "a small basket of food is hidden under a park bench, with a note attached.",
          "can't read the words.",
        ],
        [combat.LootEntry("cured meat", 1, 5, 1.0)],
        town_choice([#(1.0, "d2")]),
      ),
    ),
    #(
      "d1",
      fight(
        "a panicked scavenger bursts through the door, screaming.",
        NoWorldEffect,
        enemy("scavenger", "E", 30, 5, 0.8, 2.0, False, panic_loot),
        town_choice([#(0.5, "end1"), #(1.0, "end2")]),
      ),
    ),
    #(
      "d2",
      fight(
        "a man stands over a dead wanderer. notices he's not alone.",
        NoWorldEffect,
        enemy("vigilante", "D", 30, 6, 0.8, 2.0, False, panic_loot),
        town_choice([#(0.5, "end3"), #(1.0, "end4")]),
      ),
    ),
    #(
      "end1",
      town_cleared(
        [
          "scavenger had a small camp in the school.",
          "collected scraps spread across the floor like they fell from heaven.",
        ],
        [
          combat.LootEntry("steel sword", 1, 1, 1.0),
          combat.LootEntry("steel", 5, 10, 1.0),
          combat.LootEntry("cured meat", 5, 10, 1.0),
          combat.LootEntry("bolas", 1, 5, 0.5),
          combat.LootEntry("medicine", 1, 2, 0.3),
        ],
      ),
    ),
    #(
      "end2",
      town_cleared(
        [
          "scavenger'd been looking for supplies in here, it seems.",
          "a shame to let what he'd found go to waste.",
        ],
        [
          combat.LootEntry("coal", 5, 10, 1.0),
          combat.LootEntry("cured meat", 5, 10, 1.0),
          combat.LootEntry("leather", 5, 10, 1.0),
        ],
      ),
    ),
    #(
      "end3",
      town_cleared(
        [
          "beneath the wanderer's rags, clutched in one of its many hands, a glint of steel.",
          "worth killing for, it seems.",
        ],
        [
          combat.LootEntry("rifle", 1, 1, 1.0),
          combat.LootEntry("bullets", 1, 5, 1.0),
        ],
      ),
    ),
    #(
      "end4",
      town_cleared(
        [
          "eye for an eye seems fair.",
          "always worked before, at least.",
          "picking the bones finds some useful trinkets.",
        ],
        [
          combat.LootEntry("cured meat", 5, 10, 1.0),
          combat.LootEntry("iron", 5, 10, 1.0),
          combat.LootEntry("torch", 1, 5, 1.0),
          combat.LootEntry("bolas", 1, 5, 0.5),
          combat.LootEntry("medicine", 1, 2, 0.1),
        ],
      ),
    ),
    #(
      "end5",
      town_cleared(["some medicine abandoned in the drawers."], [
        combat.LootEntry("medicine", 2, 5, 1.0),
      ]),
    ),
    #(
      "end6",
      town_cleared(
        ["the clinic has been ransacked.", "only dust and stains remain."],
        [],
      ),
    ),
  ])
}

/// The town's recurring continue/leave pair (`leave town`).
fn town_choice(next: List(#(Float, String))) -> List(#(String, SceneButton)) {
  [#("continue", branch("continue", next)), #("leave", leave("leave town"))]
}

/// A torch-lit door into one of two scenes, then a way out of the town.
fn torch_into(next: List(#(Float, String))) -> List(#(String, SceneButton)) {
  [
    #("enter", cost_branch("enter", [#("torch", 1)], next)),
    #("leave", leave("leave town")),
  ]
}

/// The back of the town: take the cache and clear the town into an outpost.
fn town_cleared(text: List(String), loot: List(combat.LootEntry)) -> Scene {
  Scene(..story(text), setpiece: extra(loot, ClearDungeon), buttons: [
    #("leave", leave("leave town")),
  ])
}

/// A city end scene's `onLoad`: record the city cleared (it gates a later
/// Outside event), on top of the `clearDungeon` world effect.
fn city_cleared(s: state.State) -> #(state.State, List(String)) {
  #(state.set_game(s, "cityCleared", 1), [])
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
        enemy("squatter", "E", 10, 3, 0.8, 2.0, False, house_loot()),
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
      enemy("soldier", "D", 50, 8, 0.8, 2.0, True, soldier_loot),
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
        enemy("veteran", "D", 65, 10, 0.8, 2.0, False, [
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
      enemy("man", "E", 10, 3, 0.8, 2.0, False, man_loot),
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
        enemy("chief", "D", 20, 5, 0.8, 2.0, False, [
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
        enemy("beastly matriarch", "T", 10, 4, 0.8, 2.0, False, [
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

/// A Ruined City — the largest setpiece (52 scenes). Generated from
/// the source by scripts/gen_city.mjs, then folded into the suite.
fn city() -> Event {
  Event(title: "A Ruined City", is_available: always, scenes: [
    #(
      "start",
      Scene(
        ..story([
          "a battered highway sign stands guard at the entrance to this once-great city.",
          "the towers that haven't crumbled jut from the landscape like the ribcage of some ancient beast.",
          "might be things worth having still inside.",
        ]),
        notification: Some("the towers of a decaying city dominate the skyline"),
        buttons: [
          #(
            "enter",
            branch("explore", [
              #(0.2, "a1"),
              #(0.5, "a2"),
              #(0.8, "a3"),
              #(1.0, "a4"),
            ]),
          ),
          #("leave", leave("leave")),
        ],
      ),
    ),
    #(
      "a1",
      Scene(
        ..story([
          "the streets are empty.",
          "the air is filled with dust, driven relentlessly by the hard winds.",
        ]),
        buttons: [
          #("continue", branch("continue", [#(0.5, "b1"), #(1.0, "b2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "a2",
      Scene(
        ..story([
          "orange traffic cones are set across the street, faded and cracked.",
          "lights flash through the alleys between buildings.",
        ]),
        buttons: [
          #("continue", branch("continue", [#(0.5, "b3"), #(1.0, "b4")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "a3",
      Scene(
        ..story([
          "a large shanty town sprawls across the streets.",
          "faces, darkened by soot and blood, stare out from crooked huts.",
        ]),
        buttons: [
          #("continue", branch("continue", [#(0.5, "b5"), #(1.0, "b6")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "a4",
      Scene(
        ..story([
          "the shell of an abandoned hospital looms ahead.",
        ]),
        buttons: [
          #(
            "enter",
            cost_branch("enter", [#("torch", 1)], [#(0.5, "b7"), #(1.0, "b8")]),
          ),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b1",
      Scene(
        ..story([
          "the old tower seems mostly intact.",
          "the shell of a burned out car blocks the entrance.",
          "most of the windows at ground level are busted anyway.",
        ]),
        buttons: [
          #("enter", branch("enter", [#(0.5, "c1"), #(1.0, "c2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b2",
      fight(
        "a huge lizard scrambles up out of the darkness of an old metro station.",
        NoWorldEffect,
        enemy("lizard", "R", 20, 5, 0.8, 2.0, False, [
          combat.LootEntry("scales", 5, 10, 0.8),
          combat.LootEntry("teeth", 5, 10, 0.5),
          combat.LootEntry("meat", 5, 10, 0.8),
        ]),
        [
          #("descend", branch("descend", [#(0.5, "c2"), #(1.0, "c3")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b3",
      fight(
        "the shot echoes in the empty street.",
        NoWorldEffect,
        enemy("sniper", "D", 30, 15, 0.8, 4.0, True, [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.5),
          combat.LootEntry("rifle", 1, 1, 0.2),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "c4"), #(1.0, "c5")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b4",
      fight(
        "the soldier steps out from between the buildings, rifle raised.",
        NoWorldEffect,
        enemy("soldier", "D", 50, 8, 0.8, 2.0, True, [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.5),
          combat.LootEntry("rifle", 1, 1, 0.2),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "c5"), #(1.0, "c6")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b5",
      fight(
        "a frail man stands defiantly, blocking the path.",
        NoWorldEffect,
        enemy("frail man", "E", 10, 1, 0.8, 2.0, False, [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("cloth", 1, 5, 0.5),
          combat.LootEntry("leather", 1, 1, 0.2),
          combat.LootEntry("medicine", 1, 3, 0.05),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "c7"), #(1.0, "c8")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b6",
      Scene(
        ..story([
          "nothing but downcast eyes.",
          "the people here were broken a long time ago.",
        ]),
        buttons: [
          #("continue", branch("continue", [#(0.5, "c8"), #(1.0, "c9")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b7",
      Scene(
        ..story([
          "empty corridors.",
          "the place has been swept clean by scavengers.",
        ]),
        buttons: [
          #(
            "continue",
            branch("continue", [#(0.3, "c12"), #(0.7, "c10"), #(1.0, "c11")]),
          ),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "b8",
      fight(
        "an old man bursts through a door, wielding a scalpel.",
        NoWorldEffect,
        enemy("old man", "E", 10, 3, 0.5, 2.0, False, [
          combat.LootEntry("cured meat", 1, 3, 0.5),
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("medicine", 1, 2, 0.5),
        ]),
        [
          #(
            "continue",
            branch("continue", [#(0.3, "c13"), #(0.7, "c11"), #(1.0, "end15")]),
          ),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c1",
      fight(
        "a thug is waiting on the other side of the wall.",
        NoWorldEffect,
        enemy("thug", "E", 30, 3, 0.8, 2.0, False, [
          combat.LootEntry("steel sword", 1, 1, 0.5),
          combat.LootEntry("cured meat", 1, 3, 0.5),
          combat.LootEntry("cloth", 1, 5, 0.8),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "d1"), #(1.0, "d2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c2",
      fight(
        "a snarling beast jumps out from behind a car.",
        NoWorldEffect,
        enemy("beast", "R", 30, 2, 0.8, 1.0, False, [
          combat.LootEntry("meat", 1, 5, 0.8),
          combat.LootEntry("fur", 1, 5, 0.8),
          combat.LootEntry("teeth", 1, 5, 0.5),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "d2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c3",
      Scene(
        ..story([
          "street above the subway platform is blown away.",
          "lets some light down into the dusty haze.",
          "a sound comes from the tunnel, just ahead.",
        ]),
        buttons: [
          #(
            "enter",
            cost_branch("investigate", [#("torch", 1)], [
              #(0.5, "d2"),
              #(1.0, "d3"),
            ]),
          ),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c4",
      Scene(
        ..story([
          "looks like a camp of sorts up ahead.",
          "rusted chainlink is pulled across an alleyway.",
          "fires burn in the courtyard beyond.",
        ]),
        buttons: [
          #("enter", branch("continue", [#(0.5, "d4"), #(1.0, "d5")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c5",
      Scene(
        ..story([
          "more voices can be heard ahead.",
          "they must be here for a reason.",
        ]),
        buttons: [
          #("enter", branch("continue", [#(1.0, "d5")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c6",
      Scene(
        ..story([
          "the sound of gunfire carries on the wind.",
          "the street ahead glows with firelight.",
        ]),
        buttons: [
          #("enter", branch("continue", [#(0.5, "d5"), #(1.0, "d6")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c7",
      Scene(
        ..story([
          "more squatters are crowding around now.",
          "someone throws a stone.",
        ]),
        buttons: [
          #("enter", branch("continue", [#(0.5, "d7"), #(1.0, "d8")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c8",
      Scene(
        ..story([
          "an improvised shop is set up on the sidewalk.",
          "the owner stands by, stoic.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("steel sword", 1, 1, 0.8),
            combat.LootEntry("rifle", 1, 1, 0.5),
            combat.LootEntry("bullets", 1, 8, 0.25),
            combat.LootEntry("alien alloy", 1, 1, 0.01),
            combat.LootEntry("medicine", 1, 4, 0.5),
          ],
          NoWorldEffect,
        ),
        buttons: [
          #("enter", branch("continue", [#(1.0, "d8")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c9",
      Scene(
        ..story([
          "strips of meat hang drying by the side of the street.",
          "the people back away, avoiding eye contact.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("cured meat", 5, 10, 1.0),
          ],
          NoWorldEffect,
        ),
        buttons: [
          #("enter", branch("continue", [#(0.5, "d8"), #(1.0, "d9")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c10",
      Scene(
        ..story([
          "someone has locked and barricaded the door to this operating theatre.",
        ]),
        buttons: [
          #(
            "enter",
            branch("continue", [#(0.2, "end12"), #(0.6, "d10"), #(1.0, "d11")]),
          ),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c11",
      fight(
        "a tribe of elderly squatters is camped out in this ward.",
        NoWorldEffect,
        enemy("squatters", "EEE", 40, 2, 0.7, 0.5, False, [
          combat.LootEntry("cured meat", 1, 3, 0.5),
          combat.LootEntry("cloth", 3, 8, 0.8),
          combat.LootEntry("medicine", 1, 3, 0.3),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end10")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c12",
      fight(
        "a pack of lizards rounds the corner.",
        NoWorldEffect,
        enemy("lizards", "RRR", 30, 4, 0.7, 0.7, False, [
          combat.LootEntry("meat", 3, 8, 1.0),
          combat.LootEntry("teeth", 2, 4, 1.0),
          combat.LootEntry("scales", 3, 5, 1.0),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end10")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "c13",
      Scene(
        ..story([
          "strips of meat are hung up to dry in this ward.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("cured meat", 3, 10, 1.0),
          ],
          NoWorldEffect,
        ),
        buttons: [
          #("continue", branch("continue", [#(0.5, "end10"), #(1.0, "end11")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d1",
      fight(
        "a large bird nests at the top of the stairs.",
        NoWorldEffect,
        enemy("bird", "R", 45, 5, 0.7, 1.0, False, [
          combat.LootEntry("meat", 5, 10, 0.8),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end1"), #(1.0, "end2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d2",
      Scene(
        ..story([
          "the debris is denser here.",
          "maybe some useful stuff in the rubble.",
        ]),
        setpiece: extra(
          [
            combat.LootEntry("bullets", 1, 5, 0.5),
            combat.LootEntry("steel", 1, 10, 0.8),
            combat.LootEntry("alien alloy", 1, 1, 0.01),
            combat.LootEntry("cloth", 1, 10, 1.0),
          ],
          NoWorldEffect,
        ),
        buttons: [
          #("continue", branch("continue", [#(1.0, "end2")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d3",
      fight(
        "a swarm of rats rushes up the tunnel.",
        NoWorldEffect,
        enemy("rats", "RRR", 60, 1, 0.8, 0.25, False, [
          combat.LootEntry("fur", 5, 10, 0.8),
          combat.LootEntry("teeth", 5, 10, 0.5),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end2"), #(1.0, "end3")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d4",
      fight(
        "a large man attacks, waving a bayonet.",
        NoWorldEffect,
        enemy("veteran", "D", 45, 6, 0.8, 2.0, False, [
          combat.LootEntry("bayonet", 1, 1, 0.5),
          combat.LootEntry("cured meat", 1, 5, 0.8),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end4"), #(1.0, "end5")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d5",
      fight(
        "a second soldier opens fire.",
        NoWorldEffect,
        enemy("soldier", "D", 50, 8, 0.8, 2.0, True, [
          combat.LootEntry("cured meat", 1, 5, 0.8),
          combat.LootEntry("bullets", 1, 5, 0.5),
          combat.LootEntry("rifle", 1, 1, 0.2),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end5")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d6",
      fight(
        "a masked soldier rounds the corner, gun drawn",
        NoWorldEffect,
        enemy("commando", "D", 55, 3, 0.9, 2.0, True, [
          combat.LootEntry("rifle", 1, 1, 0.5),
          combat.LootEntry("bullets", 1, 5, 0.8),
          combat.LootEntry("cured meat", 1, 5, 0.8),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end5"), #(1.0, "end6")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d7",
      fight(
        "the crowd surges forward.",
        NoWorldEffect,
        enemy("squatters", "EEE", 40, 2, 0.7, 0.5, False, [
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("teeth", 1, 5, 0.5),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end7"), #(1.0, "end8")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d8",
      fight(
        "a youth lashes out with a tree branch.",
        NoWorldEffect,
        enemy("youth", "E", 45, 2, 0.7, 1.0, False, [
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("teeth", 1, 5, 0.5),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end8")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d9",
      fight(
        "a squatter stands firmly in the doorway of a small hut.",
        NoWorldEffect,
        enemy("squatter", "E", 20, 3, 0.8, 2.0, False, [
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("teeth", 1, 5, 0.5),
        ]),
        [
          #("continue", branch("continue", [#(0.5, "end8"), #(1.0, "end9")])),
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "d10",
      fight(
        "behind the door, a deformed figure awakes and attacks.",
        NoWorldEffect,
        enemy("deformed", "T", 40, 8, 0.6, 2.0, False, [
          combat.LootEntry("cloth", 1, 5, 0.8),
          combat.LootEntry("teeth", 2, 2, 1.0),
          combat.LootEntry("steel", 1, 3, 0.6),
          combat.LootEntry("scales", 2, 3, 0.1),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end14")])),
        ],
      ),
    ),
    #(
      "d11",
      fight(
        "as soon as the door is open a little bit, hundreds of tentacles erupt.",
        NoWorldEffect,
        enemy("tentacles", "TTT", 60, 2, 0.6, 0.5, False, [
          combat.LootEntry("meat", 10, 20, 1.0),
        ]),
        [
          #("continue", branch("continue", [#(1.0, "end13")])),
        ],
      ),
    ),
    #(
      "end1",
      Scene(
        ..story([
          "bird must have liked shiney things.",
          "some good stuff woven into its nest.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("bullets", 5, 10, 0.8),
            combat.LootEntry("bolas", 1, 5, 0.5),
            combat.LootEntry("alien alloy", 1, 1, 0.5),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end2",
      Scene(
        ..story([
          "not much here.",
          "scavengers must have gotten to this place already.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("torch", 1, 5, 0.8),
            combat.LootEntry("cured meat", 1, 5, 0.5),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end3",
      Scene(
        ..story([
          "the tunnel opens up at another platform.",
          "the walls are scorched from an old battle.",
          "bodies and supplies from both sides litter the ground.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("rifle", 1, 1, 0.8),
            combat.LootEntry("bullets", 1, 5, 0.8),
            combat.LootEntry("laser rifle", 1, 1, 0.3),
            combat.LootEntry("energy cell", 1, 5, 0.3),
            combat.LootEntry("alien alloy", 1, 1, 0.3),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end4",
      Scene(
        ..story([
          "the small military outpost is well supplied.",
          "arms and munitions, relics from the war, are neatly arranged on the store-room floor.",
          "just as deadly now as they were then.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("rifle", 1, 1, 1.0),
            combat.LootEntry("bullets", 1, 10, 1.0),
            combat.LootEntry("grenade", 1, 5, 0.8),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end5",
      Scene(
        ..story([
          "searching the bodies yields a few supplies.",
          "more soldiers will be on their way.",
          "time to move on.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("rifle", 1, 1, 1.0),
            combat.LootEntry("bullets", 1, 10, 1.0),
            combat.LootEntry("cured meat", 1, 5, 0.8),
            combat.LootEntry("medicine", 1, 4, 0.1),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end6",
      Scene(
        ..story([
          "the small settlement has clearly been burning a while.",
          "the bodies of the wanderers that lived here are still visible in the flames.",
          "still time to rescue a few supplies.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("laser rifle", 1, 1, 0.5),
            combat.LootEntry("energy cell", 1, 5, 0.5),
            combat.LootEntry("cured meat", 1, 10, 1.0),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end7",
      Scene(
        ..story([
          "the remaining settlers flee from the violence, their belongings forgotten.",
          "there's not much, but some useful things can still be found.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("steel sword", 1, 1, 0.8),
            combat.LootEntry("energy cell", 1, 5, 0.5),
            combat.LootEntry("cured meat", 1, 10, 1.0),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end8",
      Scene(
        ..story([
          "the young settler was carrying a canvas sack.",
          "it contains travelling gear, and a few trinkets.",
          "there's nothing else here.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("steel sword", 1, 1, 0.8),
            combat.LootEntry("bolas", 1, 5, 0.5),
            combat.LootEntry("cured meat", 1, 10, 1.0),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end9",
      Scene(
        ..story([
          "inside the hut, a child cries.",
          "a few belongings rest against the walls.",
          "there's nothing else here.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("rifle", 1, 1, 0.8),
            combat.LootEntry("bullets", 1, 5, 0.8),
            combat.LootEntry("bolas", 1, 5, 0.5),
            combat.LootEntry("alien alloy", 1, 1, 0.2),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end10",
      Scene(
        ..story([
          "the stench of rot and death fills the operating theatres.",
          "a few items are scattered on the ground.",
          "there is nothing else here.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("energy cell", 1, 1, 0.3),
            combat.LootEntry("medicine", 1, 5, 0.3),
            combat.LootEntry("teeth", 3, 8, 1.0),
            combat.LootEntry("scales", 4, 7, 0.9),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end11",
      Scene(
        ..story([
          "a pristine medicine cabinet at the end of a hallway.",
          "the rest of the hospital is empty.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("energy cell", 1, 1, 0.2),
            combat.LootEntry("medicine", 3, 10, 1.0),
            combat.LootEntry("teeth", 1, 2, 0.2),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end12",
      Scene(
        ..story([
          "someone had been stockpiling loot here.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("energy cell", 1, 3, 0.2),
            combat.LootEntry("medicine", 3, 10, 0.5),
            combat.LootEntry("bullets", 2, 8, 1.0),
            combat.LootEntry("torch", 1, 3, 0.5),
            combat.LootEntry("grenade", 1, 1, 0.5),
            combat.LootEntry("alien alloy", 1, 2, 0.8),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end13",
      Scene(
        ..story([
          "the tentacular horror is defeated.",
          "inside, the remains of its victims are everywhere.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("steel sword", 1, 3, 0.5),
            combat.LootEntry("rifle", 1, 2, 0.3),
            combat.LootEntry("teeth", 2, 8, 1.0),
            combat.LootEntry("cloth", 3, 6, 0.5),
            combat.LootEntry("alien alloy", 1, 1, 0.1),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end14",
      Scene(
        ..story([
          "the warped man lies dead.",
          "the operating theatre has a lot of curious equipment.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("energy cell", 2, 5, 0.8),
            combat.LootEntry("medicine", 3, 12, 1.0),
            combat.LootEntry("cloth", 1, 3, 0.5),
            combat.LootEntry("steel", 2, 3, 0.3),
            combat.LootEntry("alien alloy", 1, 1, 0.3),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
      ),
    ),
    #(
      "end15",
      Scene(
        ..story([
          "the old man had a small cache of interesting items.",
        ]),
        on_load: Some(city_cleared),
        setpiece: extra(
          [
            combat.LootEntry("alien alloy", 1, 1, 0.8),
            combat.LootEntry("medicine", 1, 4, 1.0),
            combat.LootEntry("cured meat", 3, 7, 1.0),
            combat.LootEntry("bolas", 1, 3, 0.5),
            combat.LootEntry("fur", 1, 5, 0.8),
          ],
          ClearDungeon,
        ),
        buttons: [
          #("leave", leave("leave city")),
        ],
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
    on_load_rng: None,
    setpiece: None,
  )
}

/// A story scene's extras: a loot table (granted on entry) and a world `onLoad`
/// effect. No inline enemy.
fn extra(
  loot: List(combat.LootEntry),
  world_effect: events.WorldEffect,
) -> option.Option(SetpieceExtra) {
  Some(SetpieceExtra(
    loot: loot,
    world_effect: world_effect,
    enemy: None,
    specials: [],
    at_health: [],
    explosion: None,
  ))
}

/// A button that ends the setpiece.
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
  SceneButton(
    text: text,
    cost: [],
    reward: [],
    notification: None,
    available: None,
    link: None,
    effect: None,
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
    link: None,
    effect: None,
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
    link: None,
    effect: None,
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
    link: None,
    effect: None,
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
    on_load_rng: None,
    setpiece: Some(SetpieceExtra(
      loot: [],
      world_effect:,
      enemy: Some(foe),
      specials: [],
      at_health: [],
      explosion: None,
    )),
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
