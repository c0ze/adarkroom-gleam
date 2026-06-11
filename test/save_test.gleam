import adarkroom/rng
import adarkroom/save
import adarkroom/state
import adarkroom/world
import gleam/option.{Some}
import gleeunit/should

fn sample() -> state.State {
  state.new()
  |> state.set_store("wood", 10)
  |> state.set_store("fur", 3)
  |> state.set_feature("fire", True)
}

pub fn encode_decode_roundtrip_test() {
  let s = sample()
  let assert Ok(decoded) = save.decode(save.encode(s))
  decoded |> should.equal(s)
}

pub fn decode_invalid_json_is_error_test() {
  save.decode("not valid json") |> should.be_error
}

pub fn decode_missing_field_is_error_test() {
  save.decode("{\"stores\":{}}") |> should.be_error
}

pub fn export_import_roundtrip_test() {
  let s = sample()
  let assert Ok(imported) = save.import_save(save.export_save(s))
  imported |> should.equal(s)
}

pub fn import_invalid_is_error_test() {
  save.import_save("!!! not base64 !!!") |> should.be_error
}

pub fn save_then_load_test() {
  let s = sample()
  save.save(s)
  let assert Some(loaded) = save.load()
  state.get_store(loaded, "wood") |> should.equal(10)
  state.has_feature(loaded, "fire") |> should.equal(True)
}

pub fn the_world_rides_the_save_test() {
  let map = world.generate_map(rng.seed(3))
  let exp = world.begin(map, state.new())
  let s = state.State(..state.new(), world: option.Some(world.to_save(exp)))
  let assert Ok(loaded) = save.decode(save.encode(s))
  loaded.world |> should.equal(s.world)
}

pub fn an_elder_save_has_no_world_yet_test() {
  // Saves written before the world persisted lack the field entirely.
  let assert Ok(loaded) =
    save.decode(
      "{\"stores\":{},\"features\":{},\"character\":{},\"game\":{},"
      <> "\"income\":{},\"timers\":{},\"play_stats\":{},\"previous\":{},"
      <> "\"outfit\":{}}",
    )
  loaded.world |> should.equal(option.None)
}
