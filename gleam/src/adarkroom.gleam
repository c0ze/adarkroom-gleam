//// A Dark Room — Gleam + Lustre port.
////
//// The Lustre application entry point: wires the MVU model/update with the
//// game-loop timers (tick, fire cooling, temperature) and renders the game
//// shell — location tabs, the current location panel, and the notification log.

import adarkroom/button
import adarkroom/clock
import adarkroom/craft.{type Craftable}
import adarkroom/model.{
  type Model, type Msg, AdjustTemp, Build, BuilderProgress, Buy, CoolCheck,
  GatherWood, LightFire, Navigate, StokeFire, Tick,
}
import adarkroom/notifications.{type Notifications}
import adarkroom/outside
import adarkroom/room
import adarkroom/save
import adarkroom/state
import adarkroom/timer
import adarkroom/trade.{type Good}
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
      resume_builder(loaded),
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
  html.div([attribute.id("wrapper")], [
    html.div([attribute.id("content")], [
      html.div([attribute.id("outerSlider")], [
        html.div([attribute.id("main")], [
          header(m),
          html.div([attribute.id("locationSlider")], [location_panel(m)]),
        ]),
      ]),
    ]),
    notifications_view(m.notifications),
  ])
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
      html.div([attribute.class(class), event.on_click(Navigate(to: loc))], [
        element.text(model.location_title(loc)),
      ])
    }),
  )
}

fn location_panel(m: Model) -> Element(Msg) {
  case m.location {
    model.Room -> room_panel(m)
    model.Outside -> outside_panel(m)
    other ->
      html.div([attribute.class("location")], [
        html.div([], [element.text(model.location_title(other))]),
      ])
  }
}

/// The Outside panel: gather wood (on a cooldown), with the stores alongside.
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
  html.div([attribute.class("location"), attribute.id("outsidePanel")], [
    gather,
    stores_view(m.state),
  ])
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
