import adarkroom/notifications as notif
import gleam/int
import gleam/list
import gleeunit/should

pub fn new_is_empty_test() {
  notif.messages(notif.new()) |> should.equal([])
}

pub fn same_location_shows_immediately_test() {
  let notes =
    notif.new()
    |> notif.notify(current: "room", target: "room", text: "the fire is lit")
  notif.messages(notes) |> should.equal(["the fire is lit."])
}

pub fn adds_trailing_period_test() {
  let notes = notif.new() |> notif.notify_global("a noise outside")
  notif.messages(notes) |> should.equal(["a noise outside."])
}

pub fn keeps_existing_period_test() {
  let notes = notif.new() |> notif.notify_global("already done.")
  notif.messages(notes) |> should.equal(["already done."])
}

pub fn other_location_queues_not_shown_test() {
  let notes =
    notif.new()
    |> notif.notify(
      current: "room",
      target: "outside",
      text: "a stranger arrives",
    )
  notif.messages(notes) |> should.equal([])
}

pub fn flush_shows_queued_oldest_first_test() {
  let notes =
    notif.new()
    |> notif.notify(current: "room", target: "outside", text: "first")
    |> notif.notify(current: "room", target: "outside", text: "second")
    |> notif.flush("outside")
  // Displayed newest-first, so "second" ends up on top.
  notif.messages(notes) |> should.equal(["second.", "first."])
}

pub fn flush_unknown_location_is_noop_test() {
  notif.messages(notif.new() |> notif.flush("nowhere")) |> should.equal([])
}

pub fn log_is_newest_first_test() {
  let notes =
    notif.new()
    |> notif.notify_global("one")
    |> notif.notify_global("two")
  notif.messages(notes) |> should.equal(["two.", "one."])
}

pub fn the_log_forgets_what_has_long_faded_test() {
  let log =
    list.repeat(Nil, 100)
    |> list.index_fold(notif.new(), fn(acc, _, i) {
      notif.notify(
        acc,
        current: "room",
        target: "room",
        text: "line " <> int.to_string(i + 1),
      )
    })
  let shown = notif.messages(log)
  list.length(shown) |> should.equal(40)
  list.first(shown) |> should.equal(Ok("line 100."))
}
