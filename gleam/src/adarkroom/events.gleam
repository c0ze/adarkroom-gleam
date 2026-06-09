//// The event/scene runtime, ported from `events.js`.
////
//// This module is the pure core: the typed scene schema and the logic that
//// drives it — event availability and random selection, entering a scene
//// (rewards + notifications), resolving a button click (cost → reward →
//// next scene), and the next-event timing. The modal UI and the tick-based
//// scheduler are wired on top in the app layer.

import adarkroom/combat
import adarkroom/craft
import adarkroom/state
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}

/// Where a button leads after its outcome is applied.
pub type NextScene {
  /// Close the event.
  End
  /// Stay on the current scene (a button with no `nextScene`, e.g. a repeatable
  /// trade).
  Stay
  /// Always load this scene.
  Goto(String)
  /// Pick the lowest-threshold scene whose threshold exceeds the roll, matching
  /// the JS `nextScene` probability map (`{ "0.5": a, "1": b }`).
  Branch(List(#(Float, String)))
}

/// A choice the player can make within a scene.
pub type SceneButton {
  SceneButton(
    text: String,
    cost: List(#(String, Int)),
    reward: List(#(String, Int)),
    notification: Option(String),
    /// When present, gates whether the button is offered (`available` in the JS).
    available: Option(fn(state.State) -> Bool),
    /// Arbitrary effect run when chosen (`onChoose`/`onClick`): a perk, a flag.
    /// Runs after the cost/reward, returning the new state and any messages.
    on_click: Option(fn(state.State) -> #(state.State, List(String))),
    next: NextScene,
  )
}

/// Whether a button should be offered: its `available` predicate, defaulting to
/// always-available when there is none.
pub fn button_available(button: SceneButton, s: state.State) -> Bool {
  case button.available {
    option.Some(p) -> p(s)
    option.None -> True
  }
}

/// A scene's `onLoad` side effect on the world expedition, beyond what `on_load`
/// can do to `State`. Setpieces mutate the live expedition — marking a landmark
/// dealt with, drinking an outpost dry — which the model applies. (`drawRoad` /
/// `clearDungeon` join this list with the mines.)
pub type WorldEffect {
  NoWorldEffect
  /// `World.markVisited` — the landmark won't fire again this trip.
  MarkVisited
  /// `World.useOutpost` — refill water to the brim, spend the outpost.
  UseOutpost
  /// The house well (`setWater` + `markVisited`) — refill water and mark the
  /// landmark dealt with, but it's no reusable outpost.
  RefillSupplies
  /// The crashed ship (`markVisited` + `drawRoad` + `state.ship`) — mark it
  /// dealt with, road it home, and record that a way off this rock was found.
  FoundShip
}

/// The extra machinery a setpiece scene carries on top of a plain event scene:
/// a loot table, a world-level `onLoad` effect, and — on a combat scene — the
/// inline enemy to fight on entry. The loot is granted on entry for a story
/// scene; for a combat scene it rides on the enemy and lands on the win.
pub type SetpieceExtra {
  SetpieceExtra(
    loot: List(combat.LootEntry),
    world_effect: WorldEffect,
    enemy: Option(combat.Enemy),
  )
}

/// One screen of an event: prose, an optional notification/reward on entry, and
/// the buttons (kept in order).
pub type Scene {
  Scene(
    text: List(String),
    notification: Option(String),
    reward: List(#(String, Int)),
    buttons: List(#(String, SceneButton)),
    combat: Bool,
    /// Arbitrary effect run on entry (`onLoad`): computed rewards, flags, perks.
    /// Returns the new state and any extra messages.
    on_load: Option(fn(state.State) -> #(state.State, List(String))),
    /// Present on setpiece scenes: loot and world-level `onLoad`. `None` on the
    /// random events, which touch only `State`.
    setpiece: Option(SetpieceExtra),
  )
}

/// A random event: a title, an availability predicate, and named scenes (one of
/// which must be `"start"`).
pub type Event {
  Event(
    title: String,
    is_available: fn(state.State) -> Bool,
    scenes: List(#(String, Scene)),
  )
}

/// The events from a pool that are currently available (`isAvailable`).
pub fn available_events(pool: List(Event), s: state.State) -> List(Event) {
  list.filter(pool, fn(e) { e.is_available(s) })
}

/// Apply a list of store deltas (`addM('stores', …)`).
fn apply_stores(s: state.State, deltas: List(#(String, Int))) -> state.State {
  list.fold(deltas, s, fn(acc, d) { state.add_store(acc, d.0, d.1) })
}

/// What a button (or scene transition) does to the running event.
pub type Step {
  LoadScene(String)
  EndEvent
  /// Remain on the current scene.
  StayOnScene
}

/// Resolve a `NextScene` into a concrete step, using `roll` for `Branch`. A
/// branch with no threshold above the roll ends the event (the JS error path).
pub fn resolve_next(next: NextScene, roll: Float) -> Step {
  case next {
    End -> EndEvent
    Stay -> StayOnScene
    Goto(name) -> LoadScene(name)
    Branch(branches) ->
      case
        branches
        |> list.filter(fn(b) { roll <. b.0 })
        |> list.sort(fn(a, b) { float.compare(a.0, b.0) })
        |> list.first
      {
        Ok(#(_, name)) -> LoadScene(name)
        Error(_) -> EndEvent
      }
  }
}

/// Enter a scene: grant its reward and surface its notification. Returns the
/// updated state and any messages to log.
pub fn enter_scene(scene: Scene, s: state.State) -> #(state.State, List(String)) {
  // onLoad runs first (it may compute a reward from current stores), then the
  // static reward, then the scene's notification.
  let #(s, load_messages) = case scene.on_load {
    option.Some(f) -> f(s)
    option.None -> #(s, [])
  }
  let s = apply_stores(s, scene.reward)
  #(s, list.append(load_messages, notification_messages(scene.notification)))
}

fn notification_messages(notification: Option(String)) -> List(String) {
  case notification {
    option.Some(n) -> [n]
    option.None -> []
  }
}

/// Whether the stores can cover a button's cost.
pub fn affordable(cost: List(#(String, Int)), s: state.State) -> Bool {
  list.all(cost, fn(c) { state.get_store(s, c.0) >= c.1 })
}

/// Resolve a button click. If the cost can't be met it's refused (`Error`),
/// mirroring the JS no-op. Otherwise the cost is paid, the reward granted, the
/// notification surfaced, and the next step resolved (using `roll` for a
/// `Branch`).
pub fn click_button(
  button: SceneButton,
  s: state.State,
  roll: Float,
) -> Result(#(state.State, List(String), Step), Nil) {
  case affordable(button.cost, s) {
    False -> Error(Nil)
    True -> {
      let s =
        s
        |> apply_stores(list.map(button.cost, fn(c) { #(c.0, -c.1) }))
        |> apply_stores(button.reward)
      let #(s, click_messages) = case button.on_click {
        option.Some(f) -> f(s)
        option.None -> #(s, [])
      }
      let messages =
        list.append(notification_messages(button.notification), click_messages)
      Ok(#(s, messages, resolve_next(button.next, roll)))
    }
  }
}

const event_time_min = 3

const event_time_max = 6

/// The delay until the next random event, in milliseconds. The JS draws
/// `floor(roll * (max - min)) + min` minutes from `EVENT_TIME_RANGE` ([3, 6]).
/// The upper bound is exclusive, so the draw is really 3–5 minutes (the JS
/// never reaches 6 either); the constants mirror the source range. `scale`
/// (e.g. `0.5` when no event was available) shortens the wait.
pub fn next_event_delay_ms(roll: Float, scale: Float) -> Int {
  let span = int.to_float(event_time_max - event_time_min)
  let minutes = float.truncate(roll *. span) + event_time_min
  float.round(int.to_float(minutes) *. scale *. 60_000.0)
}

/// Pick an item by a uniform `[0, 1)` roll, the way the JS does:
/// `items[floor(roll * length)]`. A full `1.0` roll is clamped to the last
/// item; an empty list is an error.
pub fn pick(items: List(a), roll: Float) -> Result(a, Nil) {
  case list.length(items) {
    0 -> Error(Nil)
    n -> {
      let idx = int.min(float.truncate(roll *. int.to_float(n)), n - 1)
      items |> list.drop(idx) |> list.first
    }
  }
}

// --- event content (the pools) ----------------------------------------------
// The JS splits its pool by where an event can fire (`Events.Global` / `Room` /
// `Outside`), each checking `activeModule` in `isAvailable`. We keep that split
// so availability stays a pure function of `State`. The full pools arrive in a
// follow-up; for now the Nomad seeds the Room pool.

/// Events available while in the Room.
pub fn room_events() -> List(Event) {
  [
    nomad(),
    noises_through_walls(),
    noises_in_store_room(),
    beggar(),
    shady_builder(),
    scout(),
    master(),
    sick_man(),
  ]
}

/// A plain choice button: just text and where it leads.
fn choice(text: String, next: NextScene) -> SceneButton {
  SceneButton(
    text:,
    cost: [],
    reward: [],
    notification: option.None,
    available: option.None,
    on_click: option.None,
    next:,
  )
}

/// A button that spends something on the way to its next scene.
fn give(
  text: String,
  cost: List(#(String, Int)),
  next: NextScene,
) -> SceneButton {
  SceneButton(
    text:,
    cost:,
    reward: [],
    notification: option.None,
    available: option.None,
    on_click: option.None,
    next:,
  )
}

/// A button that grants a perk (`onChoose: addPerk`) and then ends the event,
/// shown only while the player lacks the perk.
fn learn(text: String, cost: List(#(String, Int)), perk: String) -> SceneButton {
  SceneButton(
    text:,
    cost:,
    reward: [],
    notification: option.None,
    available: option.Some(fn(s) { !state.has_perk(s, perk) }),
    on_click: option.Some(fn(s) { #(state.add_perk(s, perk), []) }),
    next: End,
  )
}

/// Events available while Outside.
pub fn outside_events() -> List(Event) {
  []
}

/// Events available in any settled location (Room or Outside).
pub fn global_events() -> List(Event) {
  []
}

/// The Nomad — a wandering merchant who buys fur for scales, teeth, bait, and
/// (once) a compass.
fn nomad() -> Event {
  let start =
    Scene(
      text: [
        "a nomad shuffles into view, laden with makeshift bags bound with rough twine.",
        "won't say from where he came, but it's clear that he's not staying.",
      ],
      notification: option.Some("a nomad arrives, looking to trade"),
      reward: [],
      combat: False,
      setpiece: option.None,
      on_load: option.None,
      buttons: [
        #(
          "buyScales",
          SceneButton(
            text: "buy scales",
            cost: [#("fur", 100)],
            reward: [#("scales", 1)],
            notification: option.None,
            available: option.None,
            on_click: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyTeeth",
          SceneButton(
            text: "buy teeth",
            cost: [#("fur", 200)],
            reward: [#("teeth", 1)],
            notification: option.None,
            available: option.None,
            on_click: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyBait",
          SceneButton(
            text: "buy bait",
            cost: [#("fur", 5)],
            reward: [#("bait", 1)],
            notification: option.Some("traps are more effective with bait."),
            available: option.None,
            on_click: option.None,
            next: Stay,
          ),
        ),
        #(
          "buyCompass",
          SceneButton(
            text: "buy compass",
            cost: [#("fur", 300), #("scales", 15), #("teeth", 5)],
            reward: [#("compass", 1)],
            notification: option.Some(
              "the old compass is dented and dusty, but it looks to work.",
            ),
            available: option.Some(fn(s) { state.get_store(s, "compass") < 1 }),
            on_click: option.None,
            next: Stay,
          ),
        ),
        #(
          "goodbye",
          SceneButton(
            text: "say goodbye",
            cost: [],
            reward: [],
            notification: option.None,
            available: option.None,
            on_click: option.None,
            next: End,
          ),
        ),
      ],
    )
  Event(
    title: "The Nomad",
    is_available: fn(s) { state.get_store(s, "fur") > 0 },
    scenes: [#("start", start)],
  )
}

/// Noises through the walls — investigate to find a bundle of wood and fur, or
/// nothing at all.
fn noises_through_walls() -> Event {
  Event(
    title: "Noises",
    is_available: fn(s) { state.get_store(s, "wood") > 0 },
    scenes: [
      #(
        "start",
        Scene(
          text: [
            "through the walls, shuffling noises can be heard.",
            "can't tell what they're up to.",
          ],
          notification: option.Some(
            "strange noises can be heard through the walls",
          ),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [
            #(
              "investigate",
              choice(
                "investigate",
                Branch([#(0.3, "stuff"), #(1.0, "nothing")]),
              ),
            ),
            #("ignore", choice("ignore them", End)),
          ],
        ),
      ),
      #(
        "nothing",
        Scene(
          text: ["vague shapes move, just out of sight.", "the sounds stop."],
          notification: option.None,
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [#("backinside", choice("go back inside", End))],
        ),
      ),
      #(
        "stuff",
        Scene(
          text: [
            "a bundle of sticks lies just beyond the threshold, wrapped in coarse furs.",
            "the night is silent.",
          ],
          notification: option.None,
          reward: [#("wood", 100), #("fur", 10)],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [#("backinside", choice("go back inside", End))],
        ),
      ),
    ],
  )
}

/// Noises in the store room — something is trading wood for scales, teeth, or
/// cloth (a tenth of the wood becomes a fifth as much of the material).
fn noises_in_store_room() -> Event {
  Event(
    title: "Noises",
    is_available: fn(s) { state.get_store(s, "wood") > 0 },
    scenes: [
      #(
        "start",
        Scene(
          text: [
            "scratching noises can be heard from the store room.",
            "something's in there.",
          ],
          notification: option.Some("something's in the store room"),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [
            #(
              "investigate",
              choice(
                "investigate",
                Branch([#(0.5, "scales"), #(0.8, "teeth"), #(1.0, "cloth")]),
              ),
            ),
            #("ignore", choice("ignore them", End)),
          ],
        ),
      ),
      #("scales", scavenged_scene("small scales", "scales")),
      #("teeth", scavenged_scene("small teeth", "teeth")),
      #("cloth", scavenged_scene("scraps of cloth", "cloth")),
    ],
  )
}

/// A store-room reward scene: some wood vanishes and `material` is left behind.
fn scavenged_scene(litter: String, material: String) -> Scene {
  Scene(
    text: ["some wood is missing.", "the ground is littered with " <> litter],
    notification: option.None,
    reward: [],
    combat: False,
    setpiece: option.None,
    on_load: option.Some(scavenge(material)),
    buttons: [#("leave", choice("leave", End))],
  )
}

/// A tenth of the wood (min 1) becomes a fifth as much (min 1) of `material`.
fn scavenge(material: String) -> fn(state.State) -> #(state.State, List(String)) {
  fn(s) {
    let wood = int.max(1, state.get_store(s, "wood") / 10)
    let got = int.max(1, wood / 5)
    #(
      s
        |> state.add_store("wood", -wood)
        |> state.add_store(material, got),
      [],
    )
  }
}

/// The Beggar — give furs and he leaves a pile of scales, teeth, or cloth.
fn beggar() -> Event {
  Event(
    title: "The Beggar",
    is_available: fn(s) { state.get_store(s, "fur") > 0 },
    scenes: [
      #(
        "start",
        Scene(
          text: [
            "a beggar arrives.",
            "asks for any spare furs to keep him warm at night.",
          ],
          notification: option.Some("a beggar arrives"),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [
            #(
              "50furs",
              give(
                "give 50",
                [#("fur", 50)],
                Branch([#(0.5, "scales"), #(0.8, "teeth"), #(1.0, "cloth")]),
              ),
            ),
            #(
              "100furs",
              give(
                "give 100",
                [#("fur", 100)],
                Branch([#(0.5, "teeth"), #(0.8, "scales"), #(1.0, "cloth")]),
              ),
            ),
            #("deny", choice("turn him away", End)),
          ],
        ),
      ),
      #("scales", beggar_thanks("scales", "a pile of small scales")),
      #("teeth", beggar_thanks("teeth", "a pile of small teeth")),
      #("cloth", beggar_thanks("cloth", "some scraps of cloth")),
    ],
  )
}

/// A Beggar reward scene: 20 of `material` left behind.
fn beggar_thanks(material: String, litter: String) -> Scene {
  Scene(
    text: [
      "the beggar expresses his thanks.",
      "leaves " <> litter <> " behind.",
    ],
    notification: option.None,
    reward: [#(material, 20)],
    combat: False,
    setpiece: option.None,
    on_load: option.None,
    buttons: [#("leave", choice("say goodbye", End))],
  )
}

/// The Shady Builder — pay 300 wood, then he either makes off with it (60%) or
/// raises a hut. Stops by only once the village has 5–19 huts.
fn shady_builder() -> Event {
  Event(
    title: "The Shady Builder",
    is_available: fn(s) {
      let n = craft.building_count(s, "hut")
      n >= 5 && n < 20
    },
    scenes: [
      #(
        "start",
        Scene(
          text: [
            "a shady builder passes through",
            "says he can build you a hut for less wood",
          ],
          notification: option.Some("a shady builder passes through"),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [
            #(
              "build",
              give(
                "300 wood",
                [#("wood", 300)],
                Branch([#(0.6, "steal"), #(1.0, "build")]),
              ),
            ),
            #("deny", choice("say goodbye", End)),
          ],
        ),
      ),
      #(
        "steal",
        Scene(
          text: ["the shady builder has made off with your wood"],
          notification: option.Some(
            "the shady builder has made off with your wood",
          ),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [#("end", choice("go home", End))],
        ),
      ),
      #(
        "build",
        Scene(
          text: ["the shady builder builds a hut"],
          notification: option.Some("the shady builder builds a hut"),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.Some(raise_hut),
          buttons: [#("end", choice("go home", End))],
        ),
      ),
    ],
  )
}

/// Raise one hut, capped at 20 (the JS guard).
fn raise_hut(s: state.State) -> #(state.State, List(String)) {
  let n = craft.building_count(s, "hut")
  case n < 20 {
    True -> #(state.set_game(s, craft.building_key("hut"), n + 1), [])
    False -> #(s, [])
  }
}

/// Whether the player has reached the world (set on first embark) — gates the
/// well-travelled events.
fn world_reached(s: state.State) -> Bool {
  state.has_feature(s, "location.world")
}

/// The Scout — teaches scouting, for a hefty price. (Her map-selling option
/// awaits world-map persistence.)
fn scout() -> Event {
  Event(title: "The Scout", is_available: world_reached, scenes: [
    #(
      "start",
      Scene(
        text: [
          "the scout says she's been all over.",
          "willing to talk about it, for a price.",
        ],
        notification: option.Some("a scout stops for the night"),
        reward: [],
        combat: False,
        setpiece: option.None,
        on_load: option.None,
        buttons: [
          #(
            "learn",
            learn(
              "learn scouting",
              [#("fur", 1000), #("scales", 50), #("teeth", 20)],
              "scout",
            ),
          ),
          #("leave", choice("say goodbye", End)),
        ],
      ),
    ),
  ])
}

/// The Master — lodge him for the night and he teaches one of three combat
/// perks.
fn master() -> Event {
  Event(title: "The Master", is_available: world_reached, scenes: [
    #(
      "start",
      Scene(
        text: [
          "an old wanderer arrives.",
          "he smiles warmly and asks for lodgings for the night.",
        ],
        notification: option.Some("an old wanderer arrives"),
        reward: [],
        combat: False,
        setpiece: option.None,
        on_load: option.None,
        buttons: [
          #(
            "agree",
            give(
              "agree",
              [#("cured meat", 100), #("fur", 100), #("torch", 1)],
              Goto("agree"),
            ),
          ),
          #("deny", choice("turn him away", End)),
        ],
      ),
    ),
    #(
      "agree",
      Scene(
        text: ["in exchange, the wanderer offers his wisdom."],
        notification: option.None,
        reward: [],
        combat: False,
        setpiece: option.None,
        on_load: option.None,
        buttons: [
          #("evasion", learn("evasion", [], "evasive")),
          #("precision", learn("precision", [], "precise")),
          #("force", learn("force", [], "barbarian")),
          #("nothing", choice("nothing", End)),
        ],
      ),
    ),
  ])
}

/// The Sick Man — spare a medicine and he may leave a reward.
fn sick_man() -> Event {
  Event(
    title: "The Sick Man",
    is_available: fn(s) { state.get_store(s, "medicine") > 0 },
    scenes: [
      #(
        "start",
        Scene(
          text: ["a man hobbles up, coughing.", "he begs for medicine."],
          notification: option.Some("a sick man hobbles up"),
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [
            #(
              "help",
              SceneButton(
                text: "give 1 medicine",
                cost: [#("medicine", 1)],
                reward: [],
                notification: option.Some(
                  "the man swallows the medicine eagerly",
                ),
                available: option.None,
                on_click: option.None,
                next: Branch([
                  #(0.1, "alloy"),
                  #(0.3, "cells"),
                  #(0.5, "scales"),
                  #(1.0, "nothing"),
                ]),
              ),
            ),
            #("ignore", choice("tell him to leave", End)),
          ],
        ),
      ),
      #(
        "alloy",
        sick_reward(
          [
            "the man is thankful.",
            "he leaves a reward.",
            "some weird metal he picked up on his travels.",
          ],
          [#("alien alloy", 1)],
        ),
      ),
      #(
        "cells",
        sick_reward(
          [
            "the man is thankful.",
            "he leaves a reward.",
            "some weird glowing boxes he picked up on his travels.",
          ],
          [#("energy cell", 3)],
        ),
      ),
      #(
        "scales",
        sick_reward(
          [
            "the man is thankful.",
            "he leaves a reward.",
            "all he has are some scales.",
          ],
          [#("scales", 5)],
        ),
      ),
      #(
        "nothing",
        Scene(
          text: ["the man expresses his thanks and hobbles off."],
          notification: option.None,
          reward: [],
          combat: False,
          setpiece: option.None,
          on_load: option.None,
          buttons: [#("bye", choice("say goodbye", End))],
        ),
      ),
    ],
  )
}

/// A Sick Man reward scene: thanks plus the given stores.
fn sick_reward(text: List(String), reward: List(#(String, Int))) -> Scene {
  Scene(
    text:,
    notification: option.None,
    reward:,
    combat: False,
    setpiece: option.None,
    on_load: option.None,
    buttons: [#("bye", choice("say goodbye", End))],
  )
}
