//// The audio engine and library, ported from `audio.js` and
//// `audioLibrary.js`. The engine itself is browser machinery and lives in
//// the FFI; this module names every track and sound, file paths verbatim.

import gleam/int

/// Loop a background track, crossfading from whatever played before
/// (`playBackgroundMusic`, one-second fade).
@external(javascript, "./audio_ffi.mjs", "playBackgroundMusic")
pub fn play_background_music(src: String) -> Nil

/// Loop an event's music over the background, ducking it to 0.2
/// (`playEventMusic`, two-second fade).
@external(javascript, "./audio_ffi.mjs", "playEventMusic")
pub fn play_event_music(src: String) -> Nil

/// Fade the event music out and the background back up (`stopEventMusic`).
@external(javascript, "./audio_ffi.mjs", "stopEventMusic")
pub fn stop_event_music() -> Nil

/// One-shot sound; the same effect never overlaps itself (`playSound`).
@external(javascript, "./audio_ffi.mjs", "playSound")
pub fn play_sound(src: String) -> Nil

/// Ramp the background music's volume (the ascent's thinning air).
@external(javascript, "./audio_ffi.mjs", "setBackgroundMusicVolume")
pub fn set_background_volume(volume: Float, seconds: Float) -> Nil

/// Ramp the master volume.
@external(javascript, "./audio_ffi.mjs", "setMasterVolume")
pub fn set_master_volume(volume: Float, seconds: Float) -> Nil

// --- the library (`AudioLibrary`) -----------------------------------------------

pub const music_dusty_path = "audio/dusty-path.flac"

pub const music_silent_forest = "audio/silent-forest.flac"

pub const music_lonely_hut = "audio/lonely-hut.flac"

pub const music_tiny_village = "audio/tiny-village.flac"

pub const music_modest_village = "audio/modest-village.flac"

pub const music_large_village = "audio/large-village.flac"

pub const music_raucous_village = "audio/raucous-village.flac"

pub const music_fire_dead = "audio/fire-dead.flac"

pub const music_fire_smoldering = "audio/fire-smoldering.flac"

pub const music_fire_flickering = "audio/fire-flickering.flac"

pub const music_fire_burning = "audio/fire-burning.flac"

pub const music_fire_roaring = "audio/fire-roaring.flac"

pub const music_world = "audio/world.flac"

pub const music_space = "audio/space.flac"

pub const music_ending = "audio/ending.flac"

pub const music_ship = "audio/ship.flac"

pub const event_nomad = "audio/event-nomad.flac"

pub const event_noises_outside = "audio/event-noises-outside.flac"

pub const event_noises_inside = "audio/event-noises-inside.flac"

pub const event_beggar = "audio/event-beggar.flac"

pub const event_shady_builder = "audio/event-shady-builder.flac"

pub const event_mysterious_wanderer = "audio/event-mysterious-wanderer.flac"

pub const event_scout = "audio/event-scout.flac"

pub const event_wandering_master = "audio/event-wandering-master.flac"

pub const event_sick_man = "audio/event-sick-man.flac"

pub const event_ruined_trap = "audio/event-ruined-trap.flac"

pub const event_hut_fire = "audio/event-hut-fire.flac"

pub const event_sickness = "audio/event-sickness.flac"

pub const event_plague = "audio/event-plague.flac"

pub const event_beast_attack = "audio/event-beast-attack.flac"

pub const event_soldier_attack = "audio/event-soldier-attack.flac"

pub const event_thief = "audio/event-thief.flac"

pub const landmark_friendly_outpost = "audio/landmark-friendly-outpost.flac"

pub const landmark_swamp = "audio/landmark-swamp.flac"

pub const landmark_cave = "audio/landmark-cave.flac"

pub const landmark_town = "audio/landmark-town.flac"

pub const landmark_city = "audio/landmark-city.flac"

pub const landmark_house = "audio/landmark-house.flac"

pub const landmark_battlefield = "audio/landmark-battlefield.flac"

pub const landmark_borehole = "audio/landmark-borehole.flac"

pub const landmark_crashed_ship = "audio/landmark-crashed-ship.flac"

pub const landmark_sulphur_mine = "audio/landmark-sulphurmine.flac"

pub const landmark_coal_mine = "audio/landmark-coalmine.flac"

pub const landmark_iron_mine = "audio/landmark-ironmine.flac"

pub const landmark_destroyed_village = "audio/landmark-destroyed-village.flac"

pub const encounter_tier_1 = "audio/encounter-tier-1.flac"

pub const encounter_tier_2 = "audio/encounter-tier-2.flac"

pub const encounter_tier_3 = "audio/encounter-tier-3.flac"

pub const light_fire = "audio/light-fire.flac"

pub const stoke_fire = "audio/stoke-fire.flac"

pub const build = "audio/build.flac"

pub const craft = "audio/craft.flac"

pub const buy = "audio/buy.flac"

pub const gather_wood = "audio/gather-wood.flac"

pub const check_traps = "audio/check-traps.flac"

pub const embark = "audio/embark.flac"

/// `FOOTSTEPS_1..6` — one per world step, at random.
pub fn footsteps(index: Int) -> String {
  "audio/footsteps-" <> int.to_string(index) <> ".flac"
}

pub const eat_meat = "audio/eat-meat.flac"

pub const use_meds = "audio/use-meds.flac"

/// `WEAPON_<TYPE>_<n>` — the swing variations. The original rolls
/// `floor(random * 2) + 1`, so variant 3 exists on disk but never plays.
pub fn weapon_sound(kind: String, index: Int) -> String {
  "audio/weapon-" <> kind <> "-" <> int.to_string(index) <> ".flac"
}

pub const death = "audio/death.flac"

pub const reinforce_hull = "audio/reinforce-hull.flac"

pub const upgrade_engine = "audio/upgrade-engine.flac"

pub const lift_off = "audio/lift-off.flac"

/// `ASTEROID_HIT_1..8` — pitched by altitude. The original's rolls only ever
/// reach 1-2, 4-5 and 6-7; variants 3 and 8 exist on disk but never play.
pub fn asteroid_hit(index: Int) -> String {
  "audio/asteroid-hit-" <> int.to_string(index) <> ".flac"
}

pub const crash = "audio/crash.flac"
