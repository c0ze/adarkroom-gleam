//// A reusable button component, mirroring the original's `.button` with its
//// cost tooltip and cooldown bar. The cooldown/disabled *state* is supplied by
//// the caller (the Model drives it); this module only renders.

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Button configuration. `cooldown` is the remaining cooldown as a fraction
/// (1.0 = just clicked, 0.0 = ready), rendered as the cooldown-bar width. A
/// button that is on cooldown is treated as disabled.
pub type Config(msg) {
  Config(
    text: String,
    on_click: msg,
    cost: List(#(String, Int)),
    disabled: Bool,
    cooldown: Float,
    id: String,
  )
}

/// A ready, enabled button with no cost or cooldown.
pub fn new(text text: String, on_click on_click: msg) -> Config(msg) {
  Config(
    text: text,
    on_click: on_click,
    cost: [],
    disabled: False,
    cooldown: 0.0,
    id: "",
  )
}

/// Render the button to a Lustre element.
pub fn button(config: Config(msg)) -> Element(msg) {
  let is_disabled = config.disabled || config.cooldown >. 0.0
  let class = case is_disabled {
    True -> "button disabled"
    False -> "button"
  }
  let id_attrs = case config.id {
    "" -> []
    id -> [attribute.id(id)]
  }
  // A disabled button dispatches no message.
  let click_attrs = case is_disabled {
    True -> []
    False -> [event.on_click(config.on_click)]
  }
  let attrs = list.flatten([[attribute.class(class)], id_attrs, click_attrs])

  let tooltip_children = case config.cost {
    [] -> []
    cost -> [tooltip(cost)]
  }
  let children =
    list.flatten([
      [element.text(config.text), cooldown_bar(config.cooldown)],
      tooltip_children,
    ])

  html.div(attrs, children)
}

fn cooldown_bar(fraction: Float) -> Element(msg) {
  html.div(
    [
      attribute.class("cooldown"),
      attribute.style("width", percent(fraction)),
    ],
    [],
  )
}

fn percent(fraction: Float) -> String {
  let clamped = float.clamp(fraction, 0.0, 1.0)
  int.to_string(float.round(clamped *. 100.0)) <> "%"
}

fn tooltip(cost: List(#(String, Int))) -> Element(msg) {
  html.div(
    [attribute.class("tooltip bottom right")],
    list.flatten(
      list.map(cost, fn(pair) {
        let #(name, amount) = pair
        [
          html.div([attribute.class("row_key")], [element.text(name)]),
          html.div([attribute.class("row_val")], [
            element.text(int.to_string(amount)),
          ]),
        ]
      }),
    ),
  )
}
