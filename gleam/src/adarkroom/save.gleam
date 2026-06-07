//// Save / load: the typed `State` <-> JSON, persisted to `localStorage` under
//// `gameState`, plus base64 export/import. This is a fresh format — it does
//// not read the original JavaScript saves (per the port design).

import adarkroom/state.{type State}
import adarkroom/storage
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

const save_key = "gameState"

// --- encoding ---------------------------------------------------------------

fn int_dict(d: Dict(String, Int)) -> Json {
  json.object(list.map(dict.to_list(d), fn(kv) { #(kv.0, json.int(kv.1)) }))
}

fn bool_dict(d: Dict(String, Bool)) -> Json {
  json.object(list.map(dict.to_list(d), fn(kv) { #(kv.0, json.bool(kv.1)) }))
}

fn float_dict(d: Dict(String, Float)) -> Json {
  json.object(list.map(dict.to_list(d), fn(kv) { #(kv.0, json.float(kv.1)) }))
}

/// Encode a `State` to a JSON string.
pub fn encode(state: State) -> String {
  json.to_string(
    json.object([
      #("stores", int_dict(state.stores)),
      #("features", bool_dict(state.features)),
      #("character", int_dict(state.character)),
      #("game", int_dict(state.game)),
      #("income", int_dict(state.income)),
      #("timers", float_dict(state.timers)),
      #("play_stats", int_dict(state.play_stats)),
      #("previous", int_dict(state.previous)),
      #("outfit", int_dict(state.outfit)),
    ]),
  )
}

// --- decoding ---------------------------------------------------------------

fn ints() -> Decoder(Dict(String, Int)) {
  decode.dict(decode.string, decode.int)
}

fn state_decoder() -> Decoder(State) {
  use stores <- decode.field("stores", ints())
  use features <- decode.field(
    "features",
    decode.dict(decode.string, decode.bool),
  )
  use character <- decode.field("character", ints())
  use game <- decode.field("game", ints())
  use income <- decode.field("income", ints())
  use timers <- decode.field("timers", decode.dict(decode.string, decode.float))
  use play_stats <- decode.field("play_stats", ints())
  use previous <- decode.field("previous", ints())
  use outfit <- decode.field("outfit", ints())
  decode.success(state.State(
    stores:,
    features:,
    character:,
    game:,
    income:,
    timers:,
    play_stats:,
    previous:,
    outfit:,
  ))
}

/// Decode a JSON string into a `State`.
pub fn decode(json_string: String) -> Result(State, Nil) {
  case json.parse(json_string, state_decoder()) {
    Ok(state) -> Ok(state)
    Error(_) -> Error(Nil)
  }
}

// --- persistence ------------------------------------------------------------

/// Persist the state to localStorage.
pub fn save(state: State) -> Nil {
  storage.set(save_key, encode(state))
}

/// Load the persisted state, if any (and if it parses).
pub fn load() -> Option(State) {
  case storage.get(save_key) {
    Some(json_string) ->
      case decode(json_string) {
        Ok(state) -> Some(state)
        Error(_) -> None
      }
    None -> None
  }
}

// --- export / import (base64) -----------------------------------------------

/// A portable base64 string for backup / transfer.
pub fn export_save(state: State) -> String {
  bit_array.base64_encode(bit_array.from_string(encode(state)), True)
}

/// Restore from a base64 export string.
pub fn import_save(encoded: String) -> Result(State, Nil) {
  case bit_array.base64_decode(encoded) {
    Ok(bits) ->
      case bit_array.to_string(bits) {
        Ok(json_string) -> decode(json_string)
        Error(_) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}
