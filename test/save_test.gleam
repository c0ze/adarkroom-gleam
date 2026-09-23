import adarkroom/rng
import adarkroom/save
import adarkroom/state
import adarkroom/storage
import adarkroom/world
import gleam/option.{None, Some}
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

pub fn decode_tolerates_a_missing_category_test() {
  // A save from before a category existed still loads, that category empty.
  let assert Ok(s) = save.decode("{\"stores\":{\"wood\":7}}")
  state.get_store(s, "wood") |> should.equal(7)
}

pub fn decode_rejects_the_original_games_save_test() {
  // The JS game nests its categories; it is not ours to read.
  save.decode(
    "{\"version\":1.3,\"stores\":{\"wood\":5},\"features\":{\"location\":{\"room\":true}}}",
  )
  |> should.be_error
}

pub fn an_unreadable_save_is_set_aside_not_lost_test() {
  storage.set("gameState", "{not json")
  save.load() |> should.equal(None)
  storage.get(save.unreadable_key) |> should.equal(Some("{not json"))
  storage.get("gameState") |> should.equal(None)
  storage.remove(save.unreadable_key)
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
