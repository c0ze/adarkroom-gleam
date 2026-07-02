//// The translation lookup: identity without a catalog, msgstr with one,
//// msgid fallback on a miss, and `{0}`/`{1}` template filling — the
//// behaviours of the original `lib/translate.js`.

import adarkroom/i18n
import gleeunit/should

/// A small Turkish-flavoured catalog for the tests.
fn with_catalog(run: fn() -> a) -> a {
  i18n.load(
    "{\"wood\": \"odun\","
    <> " \"the room is {0}\": \"oda {0}\","
    <> " \"free {0}/{1}\": \"boş {0}/{1}\","
    <> " \"empty\": \"\"}",
  )
  let result = run()
  i18n.clear()
  result
}

pub fn no_catalog_is_identity_test() {
  i18n.clear()
  i18n.t("gather wood") |> should.equal("gather wood")
}

pub fn lookup_hits_the_catalog_test() {
  use <- with_catalog()
  i18n.t("wood") |> should.equal("odun")
}

pub fn miss_falls_back_to_the_msgid_test() {
  use <- with_catalog()
  i18n.t("charcoal") |> should.equal("charcoal")
}

pub fn empty_msgstr_falls_back_test() {
  use <- with_catalog()
  i18n.t("empty") |> should.equal("empty")
}

pub fn object_prototype_keys_are_not_translations_test() {
  use <- with_catalog()
  i18n.t("constructor") |> should.equal("constructor")
}

pub fn t1_translates_then_fills_the_hole_test() {
  use <- with_catalog()
  i18n.t1("the room is {0}", "serin") |> should.equal("oda serin")
}

pub fn t1_falls_back_and_still_fills_test() {
  i18n.clear()
  i18n.t1("the fire is {0}", "roaring") |> should.equal("the fire is roaring")
}

pub fn t2_fills_both_holes_test() {
  use <- with_catalog()
  i18n.t2("free {0}/{1}", "8", "10") |> should.equal("boş 8/10")
}

pub fn clear_restores_identity_test() {
  i18n.load("{\"wood\": \"odun\"}")
  i18n.clear()
  i18n.t("wood") |> should.equal("wood")
}
