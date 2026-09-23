//// The corner menu's settings and dialogs (`Engine.init`'s menu): sound,
//// lights, save export/import and restart. The settings live in the save's
//// `game` category, as the original keeps them under `config.*` — a restart
//// wipes them with everything else.

import adarkroom/state.{type State}

/// A menu dialog on screen. They borrow the event panel's look but not the
/// event machinery: the export needs a text box, and none of them is a
/// happening in the world.
pub type Dialog {
  /// `notifyAboutSound`: the first boot asks whether to turn the sound on.
  SoundPrompt
  /// `confirmDelete`: restart the game?
  RestartPrompt
  /// `exportImport`'s first scene: export, import or cancel.
  SaveStart
  /// The save as a code to copy out (`inputExport`).
  SaveExport(code: String)
  /// The warning before an import (`confirm`).
  SaveConfirm
  /// The box to paste a code into (`inputImport`); `rejected` once a paste
  /// failed to read.
  SaveImport(draft: String, rejected: Bool)
}

const sound_key = "config.soundOn"

const lights_key = "config.lightsOff"

const sound_asked_key = "config.audioAlertShown"

/// Whether the sound is on. The original starts silent until the player opts
/// in (`toggleVolume(Boolean($SM.get('config.soundOn')))`).
pub fn sound_on(s: State) -> Bool {
  state.get_game(s, sound_key) == 1
}

pub fn set_sound(s: State, on: Bool) -> State {
  state.set_game(s, sound_key, flag(on))
}

/// Whether the lights are off (the dark stylesheet).
pub fn lights_off(s: State) -> Bool {
  state.get_game(s, lights_key) == 1
}

pub fn set_lights_off(s: State, off: Bool) -> State {
  state.set_game(s, lights_key, flag(off))
}

/// Whether the sound prompt has yet to be shown (`playStats.audioAlertShown`).
pub fn sound_prompt_due(s: State) -> Bool {
  state.get_game(s, sound_asked_key) == 0
}

pub fn mark_sound_prompted(s: State) -> State {
  state.set_game(s, sound_asked_key, 1)
}

/// The master volume the sound setting calls for.
pub fn volume(s: State) -> Float {
  case sound_on(s) {
    True -> 1.0
    False -> 0.0
  }
}

fn flag(on: Bool) -> Int {
  case on {
    True -> 1
    False -> 0
  }
}
