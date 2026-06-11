//// A Dark Room — Gleam + Lustre port.
////
//// The Lustre application entry point: wires the MVU model/update with the
//// game-loop timers (tick, fire cooling, temperature) and renders the game
//// shell — location tabs, the current location panel, and the notification log.

import adarkroom/button
import adarkroom/clock
import adarkroom/combat
import adarkroom/craft.{type Craftable}
import adarkroom/events
import adarkroom/fabricator
import adarkroom/model.{
  type Model, type Msg, AdjustTemp, Build, BuilderProgress, Buy, CheckLiftoff,
  CheckTraps, ChooseEvent, CollectIncome, CoolCheck, DecreaseSupply,
  DecreaseWorker, Embark, Fabricate, GatherWood, Heal, IncreaseSupply,
  IncreaseWorker, LightFire, MoveEast, MoveNorth, MoveSouth, MoveWest, Navigate,
  ReinforceHull, StokeFire, StrikeEnemy, Tick, UpgradeEngine, UseShield, UseStim,
}
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/path
import adarkroom/room
import adarkroom/save
import adarkroom/ship
import adarkroom/space
import adarkroom/state
import adarkroom/timer
import adarkroom/trade.{type Good}
import adarkroom/world.{type Expedition}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event

const tick_interval_ms = 1000

const cool_check_ms = 1000

const temp_interval_ms = 30_000

const income_interval_ms = 10_000

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  // Resume a saved game if one exists; otherwise start fresh.
  let loaded = case save.load() {
    Some(saved) -> model.Model(..model.init(), state: saved)
    None -> model.init()
  }
  // The room's music starts with the app (sounding once the browser allows).
  let #(loaded, music) = model.startup_music(loaded)
  #(
    loaded,
    effect.batch([
      music,
      interval(tick_interval_ms, Tick),
      time_interval(cool_check_ms, CoolCheck),
      interval(temp_interval_ms, AdjustTemp),
      interval(income_interval_ms, CollectIncome),
      resume_builder(loaded),
      model.resume_population(loaded),
    ]),
  )
}

/// An effect that dispatches `msg` every `ms` milliseconds for the app's
/// lifetime.
fn interval(ms: Int, msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = timer.set_interval(fn() { dispatch(msg) }, ms)
    Nil
  })
}

/// A one-shot effect that dispatches `msg` after `ms` milliseconds.
fn delayed(ms: Int, msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = timer.set_timeout(fn() { dispatch(msg) }, ms)
    Nil
  })
}

/// A recurring effect that dispatches `to_msg(now)` every `ms` milliseconds,
/// where `now` is the current wall-clock time in milliseconds.
fn time_interval(ms: Int, to_msg: fn(Int) -> Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ =
      timer.set_interval(
        fn() { dispatch(to_msg(float.round(clock.now()))) },
        ms,
      )
    Nil
  })
}

/// Resume the builder's timer if a loaded game left it mid-progression.
fn resume_builder(m: Model) -> Effect(Msg) {
  case room.builder_arrived(m.state) && room.builder_up(m.state) == False {
    True -> delayed(room.builder_state_delay_ms, BuilderProgress)
    False -> effect.none()
  }
}

fn update(m: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let #(new, eff) = model.update(m, msg)
  // Persist whenever the saved state actually changes (not on UI-only messages
  // like Tick or Navigate).
  case new.state == m.state {
    True -> #(new, eff)
    False -> #(new, effect.batch([eff, save_effect(new.state)]))
  }
}

/// An effect that writes the state to localStorage.
fn save_effect(s: state.State) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    save.save(s)
    Nil
  })
}

fn view(m: Model) -> Element(Msg) {
  case m.ending {
    Some(ending) -> ending_view(ending)
    None -> game_view(m)
  }
}

/// The end of the game replaces everything: the beacon's outro paragraphs
/// fading in on their clocks, then the scores and the ways onward
/// (`showExpansionEnding` / `showEndingOptions`).
fn ending_view(ending: model.Ending) -> Element(Msg) {
  case ending {
    model.Outro(paragraphs: n, ..) -> {
      let texts = [
        [
          "the beacon pulses gently as the ship glides through space.",
          "coordinates are locked. nothing to do but wait.",
        ],
        [
          "the beacon glows a solid blue, and then goes dim. the ship slows.",
          "gradually, the vast wanderer homefleet comes into view.",
          "massive worldships drift unnaturally through clouds of debris, scarred and dead.",
        ],
        ["the air is running out."],
        ["the capsule is cold."],
      ]
      let shown =
        texts
        |> list.take(int.min(n, 4))
        |> list.map(fn(lines) {
          html.div(
            [attribute.class("outro"), attribute.style("opacity", "1")],
            list.map(lines, fn(line) { html.div([], [element.text(line)]) }),
          )
        })
      let wait = case n >= 5 {
        True -> [
          html.div(
            [
              attribute.id("wait-btn"),
              attribute.class("button"),
              event.on_click(model.EndingWait),
            ],
            [element.text("wait")],
          ),
        ]
        False -> []
      }
      html.div([attribute.class("outroContainer")], list.append(shown, wait))
    }
    model.EndOptions(this_score: this, total_score: total) ->
      html.div([attribute.class("centerCont")], [
        html.span(
          [attribute.class("endGame"), attribute.style("opacity", "1")],
          [
            element.text("score for this game: " <> int.to_string(this)),
          ],
        ),
        html.br([]),
        html.span(
          [attribute.class("endGame"), attribute.style("opacity", "1")],
          [
            element.text("total score: " <> int.to_string(total)),
          ],
        ),
        html.br([]),
        html.br([]),
        html.span(
          [
            attribute.class("endGame endGameOption"),
            attribute.style("opacity", "1"),
            event.on_click(model.RestartGame),
          ],
          [element.text("restart.")],
        ),
        html.br([]),
        html.br([]),
        html.span(
          [attribute.class("endGame"), attribute.style("opacity", "1")],
          [
            element.text(
              "expanded story. alternate ending. behind the scenes commentary. get the app.",
            ),
          ],
        ),
        html.br([]),
        html.br([]),
        html.span(
          [
            attribute.class("endGame endGameOption"),
            attribute.style("opacity", "1"),
            event.on_click(model.OpenStore(
              "https://itunes.apple.com/app/apple-store/id736683061?pt=2073437&ct=gameover&mt=8",
            )),
          ],
          [element.text("iOS.")],
        ),
        html.br([]),
        html.span(
          [
            attribute.class("endGame endGameOption"),
            attribute.style("opacity", "1"),
            event.on_click(model.OpenStore(
              "https://play.google.com/store/apps/details?id=com.yourcompany.adarkroom",
            )),
          ],
          [element.text("android.")],
        ),
      ])
  }
}

fn game_view(m: Model) -> Element(Msg) {
  html.div(
    [attribute.id("wrapper")],
    list.append(
      [
        html.div([attribute.id("content")], [
          html.div([attribute.id("outerSlider")], [
            html.div([attribute.id("main")], [
              header(m),
              location_slider(m),
            ]),
          ]),
        ]),
        notifications_view(m.notifications),
      ],
      // The event modal or, out in the world, the combat screen floats above
      // everything when active (at most one at a time).
      list.append(event_overlay(m), combat_overlay(m)),
    ),
  )
}

/// The combat screen, shown while a world fight is underway.
fn combat_overlay(m: Model) -> List(Element(Msg)) {
  case m.combat {
    None -> []
    // The fight is won: the looting phase (`winFight`) — the death message,
    // the loot rows, and the way onward.
    Some(cs) if cs.won -> [
      html.div([attribute.id("event"), attribute.class("eventPanel")], [
        html.div(
          [attribute.id("description")],
          list.append(
            case cs.enemy.death_message {
              "" -> []
              message -> [html.div([], [element.text(message)])]
            },
            loot_section(m),
          ),
        ),
        html.div([attribute.id("buttons")], [
          html.div([attribute.id("exitButtons")], loot_exit_buttons(m)),
          html.div([attribute.id("healButtons")], heal_buttons(m)),
        ]),
      ]),
    ]
    Some(cs) -> [
      html.div([attribute.id("event"), attribute.class("eventPanel")], [
        html.div([attribute.id("description")], [
          html.div([attribute.id("fight")], [
            fighter_div(
              "wanderer",
              "@",
              cs.player_hp,
              cs.player_max,
              cs.player_status,
            ),
            fighter_div(
              "enemy",
              cs.enemy.chara,
              cs.enemy_hp,
              cs.enemy.health,
              cs.enemy_status,
            ),
          ]),
        ]),
        html.div([attribute.id("buttons")], [
          html.div([attribute.id("attackButtons")], attack_buttons(m, cs)),
          html.div([attribute.id("healButtons")], heal_buttons(m)),
        ]),
      ]),
    ]
  }
}

/// The pending loot, as rows of take buttons with a take-everything tail
/// (`drawLoot`/`drawLootRow`). Empty when there's nothing to take.
fn loot_section(m: Model) -> List(Element(Msg)) {
  case m.loot {
    [] -> []
    rows -> [
      html.div(
        [
          attribute.id("lootButtons"),
          attribute.attribute("data-legend", "take:"),
        ],
        list.append(list.map(rows, loot_row(m, _)), [take_everything_row(m)]),
      ),
    ]
  }
}

/// One loot row: take one ("name [n]") and take-all ("take all" — or
/// "take N" when only N fit). A refused take opens the row's drop menu.
fn loot_row(m: Model, row: #(String, Int)) -> Element(Msg) {
  let #(name, num) = row
  let fits = case path.weight(name) >. 0.0 {
    True -> float.truncate(path.free_space(m.state) /. path.weight(name))
    False -> num
  }
  let can_take = int.min(fits, num)
  let take_all_label = case can_take < num {
    True -> "take " <> int.to_string(can_take)
    False -> "take all"
  }
  let take_all_class = case can_take > 0 {
    True -> "button lootTakeAll"
    False -> "button lootTakeAll disabled"
  }
  let drop = case m.drop_for == Some(name) {
    True -> [drop_menu(m, name)]
    False -> []
  }
  html.div([attribute.class("lootRow")], [
    html.div(
      [
        attribute.class("button lootTake"),
        event.on_click(model.TakeLoot(name)),
      ],
      list.append(
        [element.text(name <> " [" <> int.to_string(num) <> "]")],
        drop,
      ),
    ),
    html.div(
      [attribute.class(take_all_class), event.on_click(model.TakeAllLoot(name))],
      [element.text(take_all_label)],
    ),
  ])
}

/// Drop options for a take that didn't fit (`drawDrop`): each carried,
/// weighty item offers just enough of itself to make room.
fn drop_menu(m: Model, wanted: String) -> Element(Msg) {
  let shortfall = path.weight(wanted) -. path.free_space(m.state)
  let options =
    state.outfit_list(m.state)
    |> list.filter_map(fn(item) {
      let #(name, owned) = item
      let w = path.weight(name)
      case name != wanted && w >. 0.0 && owned > 0 {
        False -> Error(Nil)
        True -> {
          let to_drop =
            int.min(float.round(float.ceiling(shortfall /. w)), owned)
          case to_drop > 0 {
            True ->
              Ok(html.div(
                [
                  // The menu sits inside the take button; the click must
                  // not bubble into another take (`e.stopPropagation()`).
                  event.on_click(model.DropCarried(name, to_drop))
                  |> event.stop_propagation,
                ],
                [element.text(name <> " x" <> int.to_string(to_drop))],
              ))
            False -> Error(Nil)
          }
        }
      }
    })
  html.div(
    [attribute.id("dropMenu"), attribute.attribute("data-legend", "drop:")],
    list.append(options, [
      html.div(
        [
          attribute.id("no_drop"),
          event.on_click(model.CancelDrop) |> event.stop_propagation,
        ],
        [element.text("nothing")],
      ),
    ]),
  )
}

/// The take-everything tail: "take everything" when it all fits ("… and
/// leave" on a plain encounter), "take all you can" otherwise.
fn take_everything_row(m: Model) -> Element(Msg) {
  let fits = model.loot_fits_entirely(m)
  let label = case fits, m.active_event, m.combat {
    True, None, Some(_) -> "take everything and leave"
    True, _, _ -> "take everything"
    False, _, _ -> "take all you can"
  }
  html.div([attribute.class("takeETrow")], [
    button.button(button.Config(
      text: label,
      on_click: model.TakeEverything,
      cost: [],
      disabled: False,
      cooldown: model.cooldown_fraction(
        m,
        "loot_take_et",
        model.leave_cooldown_ms,
      ),
      cooldown_ms: model.leave_cooldown_ms,
      id: "loot_takeEverything",
    )),
  ])
}

/// The way out of a won fight: the scene's own buttons for a setpiece, a
/// plain cooling leave for an encounter.
fn loot_exit_buttons(m: Model) -> List(Element(Msg)) {
  case m.active_event {
    Some(active) ->
      case list.key_find(active.event.scenes, active.scene) {
        Ok(scene) -> list.map(scene.buttons, fn(pair) { event_button(m, pair) })
        Error(_) -> []
      }
    None -> [
      button.button(button.Config(
        text: "leave",
        on_click: model.LootDone,
        cost: [],
        disabled: False,
        cooldown: model.cooldown_fraction(
          m,
          "loot_leave",
          model.leave_cooldown_ms,
        ),
        cooldown_ms: model.leave_cooldown_ms,
        id: "loot_leave",
      )),
    ]
  }
}

/// Whether healing has any room to work — at full health every button in the
/// heal row sits disabled, save the shield (`setHeal`).
fn can_heal(m: Model) -> Bool {
  case m.combat {
    option.Some(cs) -> cs.player_hp < cs.player_max
    option.None -> False
  }
}

/// The heal buttons a fight offers — one per healing item carried, each on its
/// own cooldown after use. The loot screen's rebuilt buttons carry none
/// (`createEatMeatButton(0)`).
fn heal_buttons(m: Model) -> List(Element(Msg)) {
  let looting = case m.combat {
    Some(cs) -> cs.won
    None -> False
  }
  [
    #("cured meat", "eat meat", "eat", 5000),
    #("medicine", "use meds", "meds", 7000),
    #("hypo", "use hypo", "hypo", 7000),
  ]
  |> list.filter_map(fn(t) {
    let #(item, label, cooldown_id, cooldown_ms) = t
    let cooldown_ms = case looting {
      True -> 0
      False -> cooldown_ms
    }
    case state.get_outfit(m.state, item) > 0 {
      True ->
        Ok(
          button.button(button.Config(
            text: label,
            on_click: Heal(item),
            cost: [],
            disabled: !can_heal(m),
            cooldown: model.cooldown_fraction(m, cooldown_id, cooldown_ms),
            cooldown_ms: cooldown_ms,
            id: cooldown_id,
          )),
        )
      False -> Error(Nil)
    }
  })
  |> list.append(combat_aid_buttons(m))
}

/// The stim's boost (an outfit item) and the kinetic shield (owning the
/// armour suffices) ride at the end of the heal row, as the JS appends them —
/// only while the fight is live: `winFight` rebuilds the heal row with just
/// the healing items, so neither survives onto the loot screen.
fn combat_aid_buttons(m: Model) -> List(Element(Msg)) {
  case m.combat {
    Some(cs) if !cs.won -> live_aid_buttons(m)
    _ -> []
  }
}

fn live_aid_buttons(m: Model) -> List(Element(Msg)) {
  let stim = case state.get_outfit(m.state, "stim") > 0 {
    True -> [
      button.button(button.Config(
        text: "boost",
        on_click: UseStim,
        cost: [],
        disabled: !can_heal(m),
        cooldown: model.cooldown_fraction(
          m,
          "use-stim",
          combat.stim_cooldown_ms,
        ),
        cooldown_ms: combat.stim_cooldown_ms,
        id: "use-stim",
      )),
    ]
    False -> []
  }
  let shield = case state.get_store(m.state, "kinetic armour") > 0 {
    True -> [
      button.button(button.Config(
        text: "shield",
        on_click: UseShield,
        cost: [],
        disabled: False,
        cooldown: model.cooldown_fraction(m, "shld", combat.shield_cooldown_ms),
        cooldown_ms: combat.shield_cooldown_ms,
        id: "shld",
      )),
    ]
    False -> []
  }
  list.append(stim, shield)
}

/// One fighter: a glyph and its HP, as `createFighterDiv` builds.
fn fighter_div(
  id: String,
  label: String,
  hp: Int,
  max: Int,
  status: combat.Status,
) -> Element(Msg) {
  // An active status rides as a class on the fighter, the way the JS
  // updateFighterDiv styles it (`fighter shield` etc.).
  let class = case status {
    combat.NoStatus -> "fighter"
    combat.Shield -> "fighter shield"
    combat.Enraged -> "fighter enraged"
    combat.Meditation -> "fighter meditation"
    combat.Venomous -> "fighter venomous"
    combat.Energised -> "fighter energised"
    combat.Boost -> "fighter boost"
  }
  html.div([attribute.id(id), attribute.class(class)], [
    html.div([attribute.class("label")], [element.text(label)]),
    html.div([attribute.class("hp")], [
      element.text(int.to_string(hp) <> "/" <> int.to_string(max)),
    ]),
  ])
}

/// The attack buttons a fight offers — one per usable weapon, disabled when its
/// ammo has run dry and showing a cooldown bar between swings.
fn attack_buttons(m: Model, _cs: combat.CombatState) -> List(Element(Msg)) {
  list.filter_map(combat.attack_options(m.state), fn(name) {
    case combat.get_weapon(name) {
      Ok(weapon) -> Ok(attack_button(m, name, weapon))
      Error(_) -> Error(Nil)
    }
  })
}

fn attack_button(m: Model, name: String, weapon: combat.Weapon) -> Element(Msg) {
  // A stim's boost halves the recovery, bars included.
  let cooldown_ms = model.strike_cooldown_ms(m, name)
  button.button(button.Config(
    text: name,
    on_click: StrikeEnemy(name),
    cost: [],
    disabled: !combat.can_attack_with(weapon, m.state),
    cooldown: model.cooldown_fraction(m, "attack_" <> name, cooldown_ms),
    cooldown_ms: cooldown_ms,
    id: "attack_" <> name,
  ))
}

/// The event modal, present only while an event is on screen.
fn event_overlay(m: Model) -> List(Element(Msg)) {
  case m.active_event, m.combat {
    // While a setpiece fight is on, the combat screen takes the stage; the
    // scene's buttons return once it is won.
    _, Some(_) -> []
    None, None -> []
    Some(active), None ->
      case list.key_find(active.event.scenes, active.scene) {
        Error(_) -> []
        Ok(scene) -> [
          html.div([attribute.id("event"), attribute.class("eventPanel")], [
            html.div([attribute.class("eventTitle")], [
              element.text(active.event.title),
            ]),
            html.div(
              [attribute.id("description")],
              list.map(scene.text, fn(line) {
                html.div([], [element.text(line)])
              }),
            ),
            html.div([], loot_section(m)),
            html.div(
              [attribute.id("buttons")],
              list.map(scene.buttons, fn(pair) { event_button(m, pair) }),
            ),
          ]),
        ]
      }
  }
}

/// One event button — disabled when gated out or unaffordable, as the JS does.
fn event_button(m: Model, pair: #(String, events.SceneButton)) -> Element(Msg) {
  let #(id, btn) = pair
  let enabled =
    events.button_available(btn, m.state)
    && events.affordable(btn.cost, m.state, model.event_purse(m))
  case enabled {
    True ->
      html.div([attribute.class("button"), event.on_click(ChooseEvent(id))], [
        element.text(btn.text),
      ])
    False ->
      html.div([attribute.class("button disabled")], [element.text(btn.text)])
  }
}

/// The location tabs — one per unlocked location, with the current one marked.
fn header(m: Model) -> Element(Msg) {
  html.div(
    [attribute.id("header")],
    list.map(model.unlocked_locations(m), fn(loc) {
      let class = case loc == m.location {
        True -> "headerButton selected"
        False -> "headerButton"
      }
      // The Outside's name grows with the village.
      let title = case loc {
        model.Outside -> outside.title(m.state)
        _ -> model.location_title(loc)
      }
      html.div([attribute.class(class), event.on_click(Navigate(to: loc))], [
        element.text(title),
      ])
    }),
  )
}

/// The village panels the slider holds, in their unlock order. The world and
/// the ascent live a layer out (the original's outer slider) and replace the
/// slider wholesale.
fn slider_locations(m: Model) -> List(model.Location) {
  model.unlocked_locations(m)
  |> list.filter(fn(loc) {
    case loc {
      model.Room | model.Outside | model.Path | model.Ship | model.Fabricator ->
        True
      model.World | model.Space -> False
    }
  })
}

fn slider_index(locations: List(model.Location), loc: model.Location) -> Int {
  locations
  |> list.take_while(fn(l) { l != loc })
  |> list.length
}

/// All unlocked village panels side by side, slid to the current one — the
/// transition runs 300ms per panel crossed (`travelTo`'s `300 * diff`).
/// Out in the world or aloft, that location's panel takes the stage alone.
fn location_slider(m: Model) -> Element(Msg) {
  case m.location {
    model.Space -> html.div([attribute.id("locationSlider")], [space_panel(m)])
    model.World ->
      html.div([attribute.id("locationSlider")], [
        case m.expedition {
          Some(exp) -> world_panel(exp)
          None -> html.div([attribute.class("location")], [])
        },
      ])
    _ -> {
      let locations = slider_locations(m)
      let index = slider_index(locations, m.location)
      let transition = case
        list.contains(locations, m.prev_location)
        && m.prev_location != m.location
      {
        True -> {
          let diff =
            int.absolute_value(index - slider_index(locations, m.prev_location))
          "left " <> int.to_string(300 * diff) <> "ms ease-in-out"
        }
        // Coming home from the world there's nothing to slide across.
        False -> "none"
      }
      html.div(
        [
          attribute.id("locationSlider"),
          attribute.style(
            "width",
            int.to_string(list.length(locations) * 700) <> "px",
          ),
          attribute.style("left", "-" <> int.to_string(index * 700) <> "px"),
          attribute.style("transition", transition),
        ],
        list.map(locations, fn(loc) {
          case loc {
            model.Room -> room_panel(m)
            model.Outside -> outside_panel(m)
            model.Path -> path_panel(m)
            model.Ship -> ship_panel(m)
            model.Fabricator -> fabricator_panel(m)
            model.World | model.Space ->
              html.div([attribute.class("location")], [])
          }
        }),
      )
    }
  }
}

/// The Outside panel: gather wood and (once traps stand) check them, each on a
/// cooldown, with the stores alongside.
fn outside_panel(m: Model) -> Element(Msg) {
  let gather =
    button.button(button.Config(
      text: "gather wood",
      on_click: GatherWood,
      cost: [],
      disabled: model.on_cooldown(m, "gather"),
      cooldown: model.cooldown_fraction(m, "gather", outside.gather_cooldown_ms),
      cooldown_ms: outside.gather_cooldown_ms,
      id: "gatherButton",
    ))
  let traps = case craft.building_count(m.state, "trap") > 0 {
    False -> element.none()
    True ->
      button.button(button.Config(
        text: "check traps",
        on_click: CheckTraps,
        cost: [],
        disabled: model.on_cooldown(m, "traps"),
        cooldown: model.cooldown_fraction(m, "traps", outside.traps_cooldown_ms),
        cooldown_ms: outside.traps_cooldown_ms,
        id: "trapsButton",
      ))
  }
  html.div([attribute.class("location"), attribute.id("outsidePanel")], [
    workers_view(m.state),
    gather,
    traps,
    // The village box and the stores flow in one right-hand column, the
    // stores sliding below however tall the village grows — the layout
    // Engine.moveStoresView measures into place.
    html.div([attribute.id("storesColumn")], [
      village_view(m.state),
      stores_view(m.state, False),
    ]),
  ])
}

/// The worker-assignment panel: a gatherer tally plus a row per unlocked role
/// with buttons to move villagers in (±1/±10). Hidden until a role unlocks.
fn workers_view(s: state.State) -> Element(Msg) {
  case outside.unlocked_roles(s) {
    [] -> element.none()
    roles -> {
      let no_free = outside.num_gatherers(s) <= 0
      let gatherer = worker_row("gatherer", outside.num_gatherers(s), [])
      let rows =
        list.map(roles, fn(role) {
          let count = outside.worker_count(s, role)
          worker_row(role, count, [
            arrow_btn("upBtn", IncreaseWorker(role, 1), no_free),
            arrow_btn("dnBtn", DecreaseWorker(role, 1), count <= 0),
            arrow_btn("upManyBtn", IncreaseWorker(role, 10), no_free),
            arrow_btn("dnManyBtn", DecreaseWorker(role, 10), count <= 0),
          ])
        })
      html.div(
        [attribute.id("workers"), attribute.attribute("data-legend", "workers")],
        [gatherer, ..rows],
      )
    }
  }
}

fn worker_row(
  name: String,
  count: Int,
  buttons: List(Element(Msg)),
) -> Element(Msg) {
  html.div([attribute.class("workerRow")], [
    html.div([attribute.class("row_key")], [element.text(name)]),
    html.div([attribute.class("row_val")], [
      html.span([], [element.text(int.to_string(count))]),
      ..buttons
    ]),
  ])
}

/// A small ±step arrow button (workers and supplies), inert when disabled.
fn arrow_btn(class: String, msg: Msg, disabled: Bool) -> Element(Msg) {
  case disabled {
    True -> html.div([attribute.class(class <> " disabled")], [])
    False -> html.div([attribute.class(class), event.on_click(msg)], [])
  }
}

/// The Dusty Path panel: pack supplies (bounded by bag space) and embark.
fn path_panel(m: Model) -> Element(Msg) {
  let s = m.state
  let bagspace =
    html.div([attribute.id("bagspace")], [
      element.text(
        "free "
        <> int.to_string(float.truncate(path.free_space(s)))
        <> "/"
        <> int.to_string(path.capacity(s)),
      ),
    ])
  let armour =
    html.div([attribute.class("outfitRow")], [
      html.div([attribute.class("row_key")], [element.text("armour")]),
      html.div([attribute.class("row_val")], [element.text(path.armour(s))]),
    ])
  let supplies =
    list.map(path.carryable(s), fn(entry) { outfit_row(s, entry.0) })
  let embark =
    button.button(button.Config(
      text: "embark",
      on_click: Embark,
      cost: [],
      disabled: state.get_outfit(s, "cured meat") <= 0,
      cooldown: 0.0,
      cooldown_ms: 0,
      id: "embarkButton",
    ))
  html.div([attribute.class("location"), attribute.id("pathPanel")], [
    html.div(
      [
        attribute.id("outfitting"),
        attribute.attribute("data-legend", "supplies"),
      ],
      [armour, bagspace, ..supplies],
    ),
    embark,
    html.div([attribute.id("storesContainer")], [stores_view(s, True)]),
  ])
}

/// One supply row: how many are packed, with buttons to pack/unpack ±1/±10.
fn outfit_row(s: state.State, item: String) -> Element(Msg) {
  let packed = state.get_outfit(s, item)
  let full =
    packed >= state.get_store(s, item)
    || path.free_space(s) <. path.weight(item)
  html.div([attribute.class("outfitRow")], [
    html.div([attribute.class("row_key")], [element.text(item)]),
    html.div([attribute.class("row_val")], [
      html.span([], [element.text(int.to_string(packed))]),
      arrow_btn("upBtn", IncreaseSupply(item, 1), full),
      arrow_btn("dnBtn", DecreaseSupply(item, 1), packed <= 0),
      arrow_btn("upManyBtn", IncreaseSupply(item, 10), full),
      arrow_btn("dnManyBtn", DecreaseSupply(item, 10), packed <= 0),
    ]),
  ])
}

/// The village: the buildings raised and the current population. Shown as a
/// "forest" until the first hut makes it a "village". Hidden until something
/// stands.
/// The original's float-clearing spacer, appended after floated rows.
fn clear_div() -> Element(Msg) {
  html.div([attribute.class("clear")], [])
}

fn village_view(s: state.State) -> Element(Msg) {
  case craft.built(s) {
    [] -> element.none()
    buildings -> {
      let legend = case craft.building_count(s, "hut") > 0 {
        True -> "village"
        False -> "forest"
      }
      let village_row = fn(name, count) {
        html.div([attribute.class("storeRow")], [
          html.div([attribute.class("row_key")], [element.text(name)]),
          html.div([attribute.class("row_val")], [
            element.text(int.to_string(count)),
          ]),
          clear_div(),
        ])
      }
      let rows =
        list.map(buildings, fn(entry) { village_row(entry.0, entry.1) })
      // Bait in the stores arms that many traps (`updateVillage`'s
      // 'baited trap' row, capped at the traps standing).
      let baited =
        int.min(state.get_store(s, "bait"), craft.building_count(s, "trap"))
      let rows = case baited > 0 {
        True -> list.append(rows, [village_row("baited trap", baited)])
        False -> rows
      }
      let population =
        html.div([attribute.id("population")], [
          element.text(
            "pop "
            <> int.to_string(outside.population(s))
            <> "/"
            <> int.to_string(outside.max_population(s)),
          ),
        ])
      html.div(
        [attribute.id("village"), attribute.attribute("data-legend", legend)],
        list.append(rows, [population]),
      )
    }
  }
}

/// The Room panel. For now: the fire control (light when dead, otherwise stoke).
fn room_panel(m: Model) -> Element(Msg) {
  let fire_button = case room.fire(m.state) {
    room.Dead ->
      button.button(
        button.Config(..button.new("light fire", LightFire), id: "lightButton"),
      )
    _ ->
      button.button(
        button.Config(..button.new("stoke fire", StokeFire), id: "stokeButton"),
      )
  }
  let #(builds, crafts) = craft.visible(m.revealed)
  html.div([attribute.class("location")], [
    html.div([attribute.id("fireButtons")], [fire_button]),
    build_section("buildBtns", "build:", m.state, builds),
    build_section("craftBtns", "craft:", m.state, crafts),
    buy_section(m.state, trade.visible(m.state)),
    html.div([attribute.id("storesContainer")], [stores_view(m.state, True)]),
  ])
}

/// A fieldset of build/craft buttons, hidden until it has something to show.
fn build_section(
  id: String,
  legend: String,
  s: state.State,
  items: List(#(String, Craftable)),
) -> Element(Msg) {
  case items {
    [] -> element.none()
    _ ->
      html.div(
        [attribute.id(id), attribute.attribute("data-legend", legend)],
        list.map(items, fn(entry) {
          let #(name, c) = entry
          build_button(s, name, c)
        }),
      )
  }
}

/// One build/craft button: its cost tooltip, disabled once at its maximum.
fn build_button(s: state.State, name: String, c: Craftable) -> Element(Msg) {
  button.button(button.Config(
    text: name,
    on_click: Build(name),
    cost: c.cost(s),
    disabled: craft.at_maximum(c, craft.count(s, c, name)),
    cooldown: 0.0,
    cooldown_ms: 0,
    id: "build_" <> string.replace(name, " ", "-"),
  ))
}

/// The trading post's buy section, hidden until something is on offer.
fn buy_section(s: state.State, goods: List(#(String, Good))) -> Element(Msg) {
  case goods {
    [] -> element.none()
    _ ->
      html.div(
        [attribute.id("buyBtns"), attribute.attribute("data-legend", "buy:")],
        list.map(goods, fn(entry) {
          let #(name, g) = entry
          buy_button(s, name, g)
        }),
      )
  }
}

/// One buy button: its cost tooltip, disabled once at its maximum (the compass).
fn buy_button(s: state.State, name: String, g: Good) -> Element(Msg) {
  button.button(button.Config(
    text: name,
    on_click: Buy(name),
    cost: g.cost,
    disabled: trade.at_maximum(g, state.get_store(s, name)),
    cooldown: 0.0,
    cooldown_ms: 0,
    id: "buy_" <> string.replace(name, " ", "-"),
  ))
}

/// The world map: the explored ground (the wanderer at its centre), the vitals,
/// and directional controls.
/// An Old Starship: the hull and engine, their alloy-fed upgrades, and the
/// lift-off button — disabled until there's any hull at all (`ship.js`).
fn ship_panel(m: Model) -> Element(Msg) {
  html.div([attribute.id("shipPanel"), attribute.class("location")], [
    html.div([attribute.id("hullRow"), attribute.class("storeRow")], [
      html.div([attribute.class("row_key")], [element.text("hull:")]),
      html.div([attribute.class("row_val")], [
        element.text(int.to_string(ship.hull(m.state))),
      ]),
    ]),
    html.div([attribute.id("engineRow"), attribute.class("storeRow")], [
      html.div([attribute.class("row_key")], [element.text("engine:")]),
      html.div([attribute.class("row_val")], [
        element.text(int.to_string(ship.thrusters(m.state))),
      ]),
    ]),
    button.button(button.Config(
      text: "reinforce hull",
      on_click: ReinforceHull,
      cost: [#("alien alloy", ship.alloy_per_hull)],
      disabled: False,
      cooldown: 0.0,
      cooldown_ms: 0,
      id: "reinforceButton",
    )),
    button.button(button.Config(
      text: "upgrade engine",
      on_click: UpgradeEngine,
      cost: [#("alien alloy", ship.alloy_per_thruster)],
      disabled: False,
      cooldown: 0.0,
      cooldown_ms: 0,
      id: "engineButton",
    )),
    button.button(button.Config(
      text: "lift off",
      on_click: CheckLiftoff,
      cost: [],
      disabled: ship.hull(m.state) <= 0,
      cooldown: model.cooldown_fraction(m, "liftoff", ship.liftoff_cooldown_ms),
      cooldown_ms: ship.liftoff_cooldown_ms,
      id: "liftoffButton",
    )),
    html.div([attribute.id("storesContainer")], [stores_view(m.state, False)]),
  ])
}

/// A Whirring Fabricator: the redeemed blueprints, then the bench — every
/// recipe whose blueprint (if any) has fed the data port, disabled at its
/// maximum (`fabricator.js`).
fn fabricator_panel(m: Model) -> Element(Msg) {
  let blueprints = case fabricator.redeemed_blueprints(m.state) {
    [] -> []
    redeemed -> [
      html.div(
        [
          attribute.id("blueprints"),
          attribute.attribute("data-legend", "blueprints"),
        ],
        list.map(redeemed, fn(name) {
          html.div([attribute.class("blueprintRow")], [
            html.div([attribute.class("row_key")], [element.text(name)]),
          ])
        }),
      ),
    ]
  }
  let bench =
    html.div(
      [
        attribute.id("fabricateButtons"),
        attribute.attribute("data-legend", "fabricate:"),
      ],
      list.map(fabricator.bench(m.state), fn(c) {
        let label = case c.quantity > 1 {
          True -> c.name <> " (x" <> int.to_string(c.quantity) <> ")"
          False -> c.name
        }
        button.button(button.Config(
          text: label,
          on_click: Fabricate(c.key),
          cost: [#("alien alloy", c.alloy)],
          disabled: fabricator.at_maximum(m.state, c),
          cooldown: 0.0,
          cooldown_ms: 0,
          id: "fabricate_" <> c.key,
        ))
      }),
    )
  html.div(
    [attribute.id("fabricatorPanel"), attribute.class("location")],
    list.append(blueprints, [
      bench,
      html.div([attribute.id("storesContainer")], [stores_view(m.state, True)]),
    ]),
  )
}

/// The ascent (`space.js`): the ship at its clamped coordinates, the rocks at
/// their clock-derived heights, and the hull readout. The original space.css
/// does the styling.
fn space_panel(m: Model) -> Element(Msg) {
  case m.space {
    Some(flight) -> {
      let px = fn(v: Float) { float.to_string(v) <> "px" }
      let rocks =
        list.map(flight.asteroids, fn(a) {
          html.div(
            [
              attribute.class("asteroid"),
              attribute.style("left", px(a.x)),
              attribute.style(
                "top",
                px(space.asteroid_y(a, m.flight_last_move)),
              ),
            ],
            [element.text(a.chara)],
          )
        })
      html.div(
        [attribute.id("spacePanel"), attribute.class("location")],
        list.flatten([
          [
            html.div(
              [
                attribute.id("ship"),
                attribute.style("left", px(flight.x)),
                attribute.style("top", px(flight.y)),
              ],
              [element.text("@")],
            ),
          ],
          rocks,
          [
            html.div([attribute.id("hullRemaining")], [
              html.div([attribute.class("row_key")], [element.text("hull: ")]),
              html.div([attribute.class("row_val")], [
                element.text(
                  int.to_string(flight.hull)
                  <> "/"
                  <> int.to_string(ship.hull(m.state)),
                ),
              ]),
            ]),
          ],
        ]),
      )
    }
    None ->
      html.div([attribute.id("spacePanel"), attribute.class("location")], [])
  }
}

fn world_panel(exp: Expedition) -> Element(Msg) {
  let map =
    html.div(
      [
        attribute.id("map"),
        attribute.style("white-space", "pre"),
        attribute.style("font-family", "monospace"),
        attribute.style("line-height", "1"),
      ],
      list.map(world.render(exp), fn(row) { html.div([], [element.text(row)]) }),
    )
  let vitals =
    html.div([attribute.id("worldVitals")], [
      element.text(
        "hp "
        <> int.to_string(exp.vitals.health)
        <> "   water "
        <> int.to_string(exp.vitals.water),
      ),
    ])
  let controls =
    html.div([attribute.id("dirs")], [
      dir_button("north", MoveNorth),
      dir_button("west", MoveWest),
      dir_button("east", MoveEast),
      dir_button("south", MoveSouth),
    ])
  html.div([attribute.class("location"), attribute.id("worldOuter")], [
    vitals,
    map,
    controls,
  ])
}

fn dir_button(label: String, msg: Msg) -> Element(Msg) {
  button.button(button.Config(
    text: label,
    on_click: msg,
    cost: [],
    disabled: False,
    cooldown: 0.0,
    cooldown_ms: 0,
    id: "dir_" <> label,
  ))
}

/// The stores panel — resources and their counts. Hidden until non-empty.
/// Where a store row lives in the column (`updateStoresView`'s type switch).
pub type StoreSection {
  /// The plain goods, in the stores box.
  Resources
  /// The compass, in its own little section under the resources.
  SpecialItems
  /// The armory, in a box of its own — faded out away from home's workbenches.
  WeaponItems
  /// Upgrades, and anything ending in "blueprint", never show.
  HiddenItems
}

/// Classify a store by the original's lookup chain (Room.Craftables →
/// TradeGoods → MiscItems → Fabricator.Craftables); the tables' `type`
/// fields are mirrored here since the port's own tables don't carry them.
pub fn store_section(name: String) -> StoreSection {
  case string.contains(name, "blueprint") {
    True -> HiddenItems
    False ->
      case name {
        "bone spear"
        | "iron sword"
        | "steel sword"
        | "rifle"
        | "bolas"
        | "grenade"
        | "bayonet"
        | "laser rifle"
        | "energy blade"
        | "disruptor"
        | "plasma rifle" -> WeaponItems
        "waterskin"
        | "cask"
        | "water tank"
        | "rucksack"
        | "wagon"
        | "convoy"
        | "l armour"
        | "i armour"
        | "s armour"
        | "fluid recycler"
        | "cargo drone"
        | "kinetic armour" -> HiddenItems
        "compass" -> SpecialItems
        _ -> Resources
      }
  }
}

fn store_rows(stores: List(#(String, Int))) -> List(Element(Msg)) {
  list.map(stores, fn(entry) {
    let #(name, count) = entry
    html.div([attribute.class("storeRow")], [
      html.div([attribute.class("row_key")], [element.text(name)]),
      html.div([attribute.class("row_val")], [
        element.text(int.to_string(count)),
      ]),
      clear_div(),
    ])
  })
}

/// The stores column: the goods (with the compass in its own section) and,
/// at home's workbenches, the armory below them. Upgrades never show.
fn stores_view(s: state.State, show_weapons: Bool) -> Element(Msg) {
  let visible = state.stores_list(s)
  let resources =
    list.filter(visible, fn(e) { store_section(e.0) == Resources })
  let special =
    list.filter(visible, fn(e) { store_section(e.0) == SpecialItems })
  let weapons =
    list.filter(visible, fn(e) { store_section(e.0) == WeaponItems })
  let sections = case resources, special {
    [], [] -> []
    _, _ -> [
      html.div(
        [attribute.id("stores"), attribute.attribute("data-legend", "stores")],
        list.append(
          case resources {
            [] -> []
            _ -> [html.div([attribute.id("resources")], store_rows(resources))]
          },
          case special {
            [] -> []
            _ -> [html.div([attribute.id("special")], store_rows(special))]
          },
        ),
      ),
    ]
  }
  let armory = case show_weapons, weapons {
    True, [_, ..] -> [
      html.div(
        [attribute.id("weapons"), attribute.attribute("data-legend", "weapons")],
        store_rows(weapons),
      ),
    ]
    _, _ -> []
  }
  element.fragment(list.append(sections, armory))
}

/// The running message log, newest first, fading toward the bottom under the
/// gradient. Keyed by each message's sequence number so only a freshly-printed
/// one runs the fade-in (`printMessage`'s 500ms opacity animate).
fn notifications_view(n: Notifications) -> Element(Msg) {
  let messages = notifications.messages(n)
  let total = list.length(messages)
  keyed.div(
    [attribute.id("notifications")],
    list.append(
      [#("gradient", html.div([attribute.id("notifyGradient")], []))],
      list.index_map(messages, fn(msg, index) {
        #(
          int.to_string(total - index),
          html.div([attribute.class("notification")], [element.text(msg)]),
        )
      }),
    ),
  )
}
