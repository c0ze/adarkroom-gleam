//// A Dark Room — Gleam + Lustre port.
////
//// M0 scaffold: a minimal MVU app that renders the empty game shell so the
//// existing stylesheet applies. Real state/logic arrives in M1+.

import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(title: String)
}

fn init(_flags) -> Model {
  Model(title: "A Dark Room")
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  NoOp
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    NoOp -> model
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.id("wrapper")], [
    html.div([attribute.id("content")], [
      html.div([attribute.id("outerSlider")], [
        html.div([attribute.id("main")], [
          html.div([attribute.id("header")], [
            html.span([attribute.class("menuBtn")], [element.text(model.title)]),
          ]),
          html.div([attribute.id("locationSlider")], [
            html.div([attribute.class("location")], [
              html.div([], [element.text("the fire is dead.")]),
            ]),
          ]),
        ]),
      ]),
    ]),
  ])
}
