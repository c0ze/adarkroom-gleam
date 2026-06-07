//// A Dark Room — Gleam + Lustre port.
////
//// The Lustre application entry point: wires the MVU model/update with a
//// periodic game-loop tick (via the timer FFI) and renders the current
//// location into the existing game shell.

import adarkroom/model.{type Model, type Msg, Tick}
import adarkroom/timer
import gleam/int
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

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
          html.div([attribute.id("header")], [
            html.span([attribute.class("menuBtn")], [
              element.text("A Dark Room"),
            ]),
          ]),
          html.div([attribute.id("locationSlider")], [
            html.div([attribute.class("location")], [
              html.div([], [element.text("the fire is dead.")]),
              // Temporary loop indicator; replaced by the real HUD later.
              html.div([attribute.class("debug")], [
                element.text("tick " <> int.to_string(m.ticks)),
              ]),
            ]),
          ]),
        ]),
      ]),
    ]),
  ])
}
