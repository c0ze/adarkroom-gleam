import adarkroom/audio
import gleeunit/should

pub fn footsteps_paths_test() {
  audio.footsteps(1) |> should.equal("audio/footsteps-1.flac")
  audio.footsteps(5) |> should.equal("audio/footsteps-5.flac")
}

pub fn asteroid_hit_paths_test() {
  audio.asteroid_hit(1) |> should.equal("audio/asteroid-hit-1.flac")
  audio.asteroid_hit(7) |> should.equal("audio/asteroid-hit-7.flac")
}

pub fn weapon_sound_paths_test() {
  audio.weapon_sound("unarmed", 1)
  |> should.equal("audio/weapon-unarmed-1.flac")
  audio.weapon_sound("ranged", 2) |> should.equal("audio/weapon-ranged-2.flac")
}
