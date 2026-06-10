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
import adarkroom/model.{
  type Model, type Msg, AdjustTemp, Build, BuilderProgress, Buy, CheckTraps,
  ChooseEvent, CollectIncome, CoolCheck, DecreaseSupply, DecreaseWorker, Embark,
  GatherWood, Heal, IncreaseSupply, IncreaseWorker, LightFire, MoveEast,
  MoveNorth, MoveSouth, MoveWest, Navigate, StokeFire, StrikeEnemy, Tick,
}
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/path
import adarkroom/room
import adarkroom/save
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
  #(
    loaded,
    effect.batch([
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
  html.div(
    [attribute.id("wrapper")],
    list.append(
      [
        html.div([attribute.id("content")], [
          html.div([attribute.id("outerSlider")], [
            html.div([attribute.id("main")], [
              header(m),
              html.div([attribute.id("locationSlider")], [location_panel(m)]),
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
    Some(cs) -> [
      html.div([attribute.id("event"), attribute.class("eventPanel")], [
        html.div([attribute.id("description")], [
          html.div([attribute.id("fight")], [
            fighter_div("wanderer", "@", cs.player_hp, cs.player_max),
            fighter_div("enemy", cs.enemy.chara, cs.enemy_hp, cs.enemy.health),
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

/// The heal buttons a fight offers — one per healing item carried, each on its
/// own cooldown after use.
fn heal_buttons(m: Model) -> List(Element(Msg)) {
  [
    #("cured meat", "eat meat", "eat", 5000),
    #("medicine", "use meds", "meds", 7000),
    #("hypo", "use hypo", "hypo", 7000),
  ]
  |> list.filter_map(fn(t) {
    let #(item, label, cooldown_id, cooldown_ms) = t
    case state.get_outfit(m.state, item) > 0 {
      True ->
        Ok(
          button.button(button.Config(
            text: label,
            on_click: Heal(item),
            cost: [],
            disabled: False,
            cooldown: model.cooldown_fraction(m, cooldown_id, cooldown_ms),
            id: cooldown_id,
          )),
        )
      False -> Error(Nil)
    }
  })
}

/// One fighter: a glyph and its HP, as `createFighterDiv` builds.
fn fighter_div(id: String, label: String, hp: Int, max: Int) -> Element(Msg) {
  html.div([attribute.id(id), attribute.class("fighter")], [
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
  button.button(button.Config(
    text: name,
    on_click: StrikeEnemy(name),
    cost: [],
    disabled: !combat.can_attack_with(weapon, m.state),
    cooldown: model.cooldown_fraction(
      m,
      "attack_" <> name,
      weapon.cooldown * 1000,
    ),
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

fn location_panel(m: Model) -> Element(Msg) {
  case m.location {
    model.Room -> room_panel(m)
    model.Outside -> outside_panel(m)
    model.Path -> path_panel(m)
    model.World ->
      case m.expedition {
        Some(exp) -> world_panel(exp)
        None -> html.div([attribute.class("location")], [])
      }
    other ->
      html.div([attribute.class("location")], [
        html.div([], [element.text(model.location_title(other))]),
      ])
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
        id: "trapsButton",
      ))
  }
  html.div([attribute.class("location"), attribute.id("outsidePanel")], [
    village_view(m.state),
    workers_view(m.state),
    gather,
    traps,
    stores_view(m.state),
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
    stores_view(s),
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
fn village_view(s: state.State) -> Element(Msg) {
  case craft.built(s) {
    [] -> element.none()
    buildings -> {
      let legend = case craft.building_count(s, "hut") > 0 {
        True -> "village"
        False -> "forest"
      }
      let rows =
        list.map(buildings, fn(entry) {
          let #(name, count) = entry
          html.div([attribute.class("storeRow")], [
            html.div([attribute.class("row_key")], [element.text(name)]),
            html.div([attribute.class("row_val")], [
              element.text(int.to_string(count)),
            ]),
          ])
        })
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
    build_section("buildBtns", "build", m.state, builds),
    build_section("craftBtns", "craft", m.state, crafts),
    buy_section(m.state, trade.visible(m.state)),
    stores_view(m.state),
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
    id: "build_" <> string.replace(name, " ", "-"),
  ))
}

/// The trading post's buy section, hidden until something is on offer.
fn buy_section(s: state.State, goods: List(#(String, Good))) -> Element(Msg) {
  case goods {
    [] -> element.none()
    _ ->
      html.div(
        [attribute.id("buyBtns"), attribute.attribute("data-legend", "buy")],
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
    id: "buy_" <> string.replace(name, " ", "-"),
  ))
}

/// The world map: the explored ground (the wanderer at its centre), the vitals,
/// and directional controls.
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
    id: "dir_" <> label,
  ))
}

/// The stores panel — resources and their counts. Hidden until non-empty.
fn stores_view(s: state.State) -> Element(Msg) {
  case state.stores_list(s) {
    [] -> element.none()
    stores ->
      html.div(
        [attribute.id("stores"), attribute.attribute("data-legend", "stores")],
        [
          html.div(
            [attribute.id("resources")],
            list.map(stores, fn(entry) {
              let #(name, count) = entry
              html.div([attribute.class("storeRow")], [
                html.div([attribute.class("row_key")], [element.text(name)]),
                html.div([attribute.class("row_val")], [
                  element.text(int.to_string(count)),
                ]),
              ])
            }),
          ),
        ],
      )
  }
}

/// The running message log, newest first.
fn notifications_view(n: Notifications) -> Element(Msg) {
  html.div(
    [attribute.id("notifications")],
    list.map(notifications.messages(n), fn(msg) {
      html.div([attribute.class("notification")], [element.text(msg)])
    }),
  )
}
