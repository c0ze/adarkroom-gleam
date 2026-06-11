import adarkroom/storage
import gleam/option.{None, Some}
import gleeunit/should

pub fn set_then_get_test() {
  storage.set("greeting", "hello")
  storage.get("greeting")
  |> should.equal(Some("hello"))
  storage.remove("greeting")
}

pub fn missing_key_test() {
  storage.remove("nope")
  storage.get("nope")
  |> should.equal(None)
}

pub fn overwrite_test() {
  storage.set("counter", "one")
  storage.set("counter", "two")
  storage.get("counter")
  |> should.equal(Some("two"))
  storage.remove("counter")
}

pub fn remove_test() {
  storage.set("temp", "x")
  storage.remove("temp")
  storage.get("temp")
  |> should.equal(None)
}

// Empty-string values are stored values, not missing keys.
pub fn empty_string_test() {
  storage.set("empty", "")
  storage.get("empty")
  |> should.equal(Some(""))
  storage.remove("empty")
}
