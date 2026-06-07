//// A Dark Room — Gleam + Lustre port.
////
//// The Lustre application entry point: wires the MVU model/update with a
//// periodic game-loop tick (via the timer FFI) and renders the game shell —
//// location tabs, the current location panel, and the notification log.

import adarkroom/model.{type Model, type Msg, Navigate, Tick}
import adarkroom/notifications.{type Notifications}
import adarkroom/timer
import gleam/list
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const tick_interval_ms = 1000

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(model.init(), tick_effect())
}

/// Start the periodic game-loop tick; it runs for the lifetime of the app.
fn tick_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = timer.set_interval(fn() { dispatch(Tick) }, tick_interval_ms)
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

/// The current location's panel. Only the Room has content so far.
fn location_panel(m: Model) -> Element(Msg) {
  let body = case m.location {
    model.Room -> "the fire is dead."
    other -> model.location_title(other)
  }
  html.div([attribute.class("location")], [html.div([], [element.text(body)])])
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
