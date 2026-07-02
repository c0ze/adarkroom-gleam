//// The .po pipeline's artifacts, held against the originals: every language
//// in the menu has a loadable catalog under public/lang/, and every literal
//// the port catalogued is a genuine msgid from adarkroom-js/lang/adarkroom.pot
//// — so the port's strings can never drift from the reference catalog.

import adarkroom/i18n
import adarkroom/i18n/catalog
import adarkroom/i18n/languages
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/set
import gleeunit/should

@external(javascript, "./i18n_pipeline_ffi.mjs", "readFile")
fn read_file(path: String) -> String

/// The original template's msgids (public/lang/msgids.json, from the .pot).
fn original_msgids() -> set.Set(String) {
  let assert Ok(msgids) =
    json.parse(read_file("public/lang/msgids.json"), decode.list(decode.string))
  set.from_list(msgids)
}

pub fn the_pot_yields_the_full_catalog_test() {
  let msgids = original_msgids()
  should.be_true(set.size(msgids) > 700)
  // A few known residents, template holes included.
  should.be_true(set.contains(msgids, "gather wood"))
  should.be_true(set.contains(msgids, "the room is {0}"))
  should.be_true(set.contains(msgids, "the compass points east"))
}

/// The drift guard: anything wrapped in `t("…")` that upstream never had is
/// either a typo or a port invention, and fails here by name.
pub fn every_catalogued_literal_is_an_original_msgid_test() {
  let msgids = original_msgids()
  catalog.msgids
  |> list.filter(fn(msgid) { !set.contains(msgids, msgid) })
  |> should.equal([])
}

pub fn the_menu_matches_the_original_languages_test() {
  list.length(languages.languages) |> should.equal(26)
  list.key_find(languages.languages, "en") |> should.equal(Ok("english"))
  list.key_find(languages.languages, "tr") |> should.equal(Ok("türkçe"))
  list.key_find(languages.languages, "zh_cn") |> should.equal(Ok("简体中文"))
}

pub fn every_language_has_a_loadable_catalog_test() {
  languages.languages
  |> list.filter(fn(lang) { lang.0 != "en" })
  |> list.each(fn(lang) {
    let assert Ok(table) =
      json.parse(
        read_file("public/lang/" <> lang.0 <> "/strings.json"),
        decode.dict(decode.string, decode.string),
      )
    // Every catalog carries a real body of translations.
    should.be_true(dict.size(table) > 300)
  })
}

pub fn a_generated_catalog_loads_and_translates_test() {
  i18n.load(read_file("public/lang/tr/strings.json"))
  i18n.t("wood") |> should.equal("odun")
  i18n.t("bait") |> should.equal("yem")
  i18n.t1("the room is {0}", i18n.t("mild")) |> should.equal("oda ılık")
  i18n.clear()
  i18n.t("wood") |> should.equal("wood")
}
