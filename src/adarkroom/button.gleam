//// A reusable button component, mirroring the original's `.button` with its
//// cost tooltip and cooldown bar. The cooldown/disabled *state* is supplied by
//// the caller (the Model drives it); this module only renders.
////
//// Rendered as a real `<button>` (the original used a div): focusable with
//// Tab, activatable with Enter/Space. The CSS strips the browser chrome so
//// it still looks exactly like the original's div.

import adarkroom/i18n
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
    /// The cooldown's full length, for the bar's animation clock. `0` for
    /// buttons that never cool.
    cooldown_ms: Int,
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
    cooldown_ms: 0,
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
  // A disabled button dispatches no message. It wears `aria-disabled` rather
  // than the native `disabled` attribute so it stays in the tab order and
  // keeps showing its cost tooltip on hover, as the original's div did.
  let click_attrs = case is_disabled {
    True -> [attribute.aria_disabled(True)]
    False -> [event.on_click(config.on_click)]
  }
  let attrs =
    list.flatten([
      [attribute.type_("button"), attribute.class(class)],
      id_attrs,
      click_attrs,
    ])

  let tooltip_children = case config.cost {
    [] -> []
    cost -> [tooltip(cost)]
  }
  let children =
    list.flatten([
      [
        // Labels are msgids; every button speaks the current language
        // (the original wraps each `Button` text in `_()`).
        element.text(i18n.t(config.text)),
        cooldown_bar(config.cooldown, config.cooldown_ms),
      ],
      tooltip_children,
    ])

  html.button(attrs, children)
}

/// The bar slides on a CSS animation clock rather than the model's 1s steps
/// (the original's jQuery animate): a negative delay starts it mid-way, so a
/// re-render lands exactly where the wall clock says.
fn cooldown_bar(fraction: Float, duration_ms: Int) -> Element(msg) {
  case fraction >. 0.0 && duration_ms > 0 {
    True -> {
      let elapsed =
        float.round(int.to_float(duration_ms) *. { 1.0 -. fraction })
      html.div(
        [
          attribute.class("cooldown"),
          // The bar is decoration; the disabled state already says it all.
          attribute.aria_hidden(True),
          attribute.style(
            "animation",
            "cooldownBar "
              <> int.to_string(duration_ms)
              <> "ms linear -"
              <> int.to_string(elapsed)
              <> "ms forwards",
          ),
        ],
        [],
      )
    }
    False ->
      html.div(
        [
          attribute.class("cooldown"),
          attribute.aria_hidden(True),
          attribute.style("width", percent(fraction)),
        ],
        [],
      )
  }
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
          html.div([attribute.class("row_key")], [element.text(i18n.t(name))]),
          html.div([attribute.class("row_val")], [
            element.text(int.to_string(amount)),
          ]),
        ]
      }),
    ),
  )
}
