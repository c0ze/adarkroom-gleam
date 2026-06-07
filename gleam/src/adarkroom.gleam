//// A Dark Room — Gleam + Lustre port.
////
//// The Lustre application entry point: wires the MVU model/update with the
//// game-loop timers (tick, fire cooling, temperature) and renders the game
//// shell — location tabs, the current location panel, and the notification log.

import adarkroom/button
import adarkroom/model.{
  type Model, type Msg, AdjustTemp, CoolFire, LightFire, Navigate, StokeFire,
  Tick,
}
import adarkroom/notifications.{type Notifications}
import adarkroom/room
import adarkroom/state
import adarkroom/timer
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const tick_interval_ms = 1000

const cool_interval_ms = 300_000

const temp_interval_ms = 30_000

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    model.init(),
    effect.batch([
      interval(tick_interval_ms, Tick),
      interval(cool_interval_ms, CoolFire),
      interval(temp_interval_ms, AdjustTemp),
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

fn update(m: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  #(model.update(m, msg), effect.none())
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
    other ->
      html.div([attribute.class("location")], [
        html.div([], [element.text(model.location_title(other))]),
      ])
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
  html.div([attribute.class("location")], [
    html.div([attribute.id("fireButtons")], [fire_button]),
    stores_view(m.state),
  ])
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
