import adarkroom/button
import gleam/string
import gleeunit/should
import lustre/element

type Msg {
  Clicked
}

fn render(config: button.Config(Msg)) -> String {
  element.to_string(button.button(config))
}

pub fn renders_text_and_class_test() {
  let html = render(button.new("light fire", Clicked))
  string.contains(html, "light fire") |> should.be_true
  string.contains(html, "button") |> should.be_true
}

pub fn enabled_is_not_disabled_test() {
  render(button.new("gather wood", Clicked))
  |> string.contains("disabled")
  |> should.be_false
}

pub fn disabled_has_class_test() {
  render(button.Config(..button.new("x", Clicked), disabled: True))
  |> string.contains("disabled")
  |> should.be_true
}

pub fn cost_renders_tooltip_test() {
  let html =
    render(
      button.Config(..button.new("build hut", Clicked), cost: [#("wood", 10)]),
    )
  string.contains(html, "tooltip") |> should.be_true
  string.contains(html, "wood") |> should.be_true
  string.contains(html, "10") |> should.be_true
}

pub fn cooldown_sets_bar_width_test() {
  render(button.Config(..button.new("x", Clicked), cooldown: 0.5))
  |> string.contains("50%")
  |> should.be_true
}

pub fn cooldown_disables_test() {
  render(button.Config(..button.new("x", Clicked), cooldown: 0.5))
  |> string.contains("disabled")
  |> should.be_true
}

pub fn cooldown_clamps_to_full_test() {
  render(button.Config(..button.new("x", Clicked), cooldown: 2.0))
  |> string.contains("100%")
  |> should.be_true
}

// --- The accessibility pass: a real <button>, spoken states ---

pub fn renders_a_native_button_test() {
  let html = render(button.new("light fire", Clicked))
  string.contains(html, "<button") |> should.be_true
  string.contains(html, "type=\"button\"") |> should.be_true
}

pub fn disabled_wears_aria_disabled_test() {
  render(button.Config(..button.new("x", Clicked), disabled: True))
  |> string.contains("aria-disabled=\"true\"")
  |> should.be_true
}

pub fn cooldown_wears_aria_disabled_test() {
  render(button.Config(..button.new("x", Clicked), cooldown: 0.5))
  |> string.contains("aria-disabled=\"true\"")
  |> should.be_true
}

pub fn enabled_carries_no_aria_disabled_test() {
  render(button.new("gather wood", Clicked))
  |> string.contains("aria-disabled")
  |> should.be_false
}
