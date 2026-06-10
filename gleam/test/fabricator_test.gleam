import adarkroom/fabricator
import adarkroom/state
import gleam/list
import gleeunit/should

pub fn the_free_bench_needs_no_blueprints_test() {
  // A fresh fabricator offers only the blueprint-free recipes.
  fabricator.bench(state.new())
  |> list.map(fn(c) { c.key })
  |> should.equal(["energy blade", "fluid recycler", "cargo drone"])
}

pub fn a_redeemed_blueprint_joins_the_bench_test() {
  let s = state.set_character(state.new(), "blueprints.hypo", 1)
  fabricator.bench(s)
  |> list.map(fn(c) { c.key })
  |> list.contains("hypo")
  |> should.be_true
  fabricator.redeemed_blueprints(s) |> should.equal(["hypo"])
}

pub fn fabricating_pays_alloy_into_the_stores_test() {
  let s = state.set_store(state.new(), "alien alloy", 3)
  let #(after, msgs) = fabricator.fabricate(s, "fluid recycler")
  state.get_store(after, "alien alloy") |> should.equal(1)
  state.get_store(after, "fluid recycler") |> should.equal(1)
  msgs |> should.equal(["water out, water in. waste not, want not."])
}

pub fn hypos_come_five_to_a_batch_test() {
  let s = state.set_store(state.new(), "alien alloy", 1)
  let #(after, _) = fabricator.fabricate(s, "hypo")
  state.get_store(after, "hypo") |> should.equal(5)
}

pub fn an_empty_store_fabricates_nothing_test() {
  let #(after, msgs) = fabricator.fabricate(state.new(), "energy blade")
  state.get_store(after, "energy blade") |> should.equal(0)
  msgs |> should.equal(["not enough alien alloy"])
}

pub fn upgrades_stop_at_their_maximum_test() {
  let one = state.set_store(state.new(), "cargo drone", 1)
  let assert Ok(drone) =
    list.find(fabricator.craftables(), fn(c) { c.key == "cargo drone" })
  fabricator.at_maximum(state.new(), drone) |> should.be_false
  fabricator.at_maximum(one, drone) |> should.be_true
}

pub fn the_glowstone_displays_as_two_words_test() {
  let assert Ok(stone) =
    list.find(fabricator.craftables(), fn(c) { c.key == "glowstone" })
  stone.name |> should.equal("glow stone")
}

pub fn the_machinery_hums_once_test() {
  let #(s, msgs) = fabricator.see_fabricator(state.new())
  msgs
  |> should.equal([
    "the familiar hum of wanderer machinery coming to life. finally, real tools.",
  ])
  let #(_, again) = fabricator.see_fabricator(s)
  again |> should.equal([])
}
