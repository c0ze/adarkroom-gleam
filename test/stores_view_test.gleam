import adarkroom
import gleam/list
import gleeunit/should

// --- the stores column's sections (updateStoresView) ------------------------------

pub fn weapons_get_their_own_box_test() {
  ["bone spear", "rifle", "bolas", "laser rifle", "energy blade"]
  |> list.each(fn(name) {
    adarkroom.store_section(name) |> should.equal(adarkroom.WeaponItems)
  })
}

pub fn upgrades_and_blueprints_never_show_test() {
  ["waterskin", "rucksack", "convoy", "s armour", "kinetic armour"]
  |> list.each(fn(name) {
    adarkroom.store_section(name) |> should.equal(adarkroom.HiddenItems)
  })
  adarkroom.store_section("plasma rifle blueprint")
  |> should.equal(adarkroom.HiddenItems)
}

pub fn the_compass_is_special_and_goods_are_resources_test() {
  adarkroom.store_section("compass") |> should.equal(adarkroom.SpecialItems)
  ["wood", "fur", "cured meat", "torch", "alien alloy", "hypo", "glowstone"]
  |> list.each(fn(name) {
    adarkroom.store_section(name) |> should.equal(adarkroom.Resources)
  })
}
