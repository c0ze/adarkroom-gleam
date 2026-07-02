//// The notification system: a running message log plus per-location queues.
////
//// Mirrors the original: a message targeted at a location the player isn't
//// currently viewing is queued, then flushed (oldest-first) when they arrive.
//// Messages are stored newest-first for display and gain a trailing period.

import adarkroom/i18n
import adarkroom/journal
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub type Notifications {
  Notifications(
    /// The displayed log, newest message first.
    messages: List(String),
    /// Pending messages per location key, flushed on arrival (oldest first).
    queues: Dict(String, List(String)),
  )
}

pub fn new() -> Notifications {
  Notifications(messages: [], queues: dict.new())
}

/// The displayed log, newest first.
pub fn messages(notifications: Notifications) -> List(String) {
  notifications.messages
}

/// Translate, then punctuate — the original translates at the `_()` call site
/// and `Notifications.notify` appends the period afterwards, so msgids carry
/// no trailing period unless they end a literal sentence. Messages composed
/// from parts (`"not enough " <> stuff`) resolve here too, whenever the
/// composed whole is itself a msgid.
fn normalize(text: String) -> String {
  let text = i18n.t(text)
  case string.ends_with(text, ".") {
    True -> text
    False -> text <> "."
  }
}

fn show(notifications: Notifications, text: String) -> Notifications {
  Notifications(..notifications, messages: [text, ..notifications.messages])
}

/// Show a message immediately, regardless of location.
pub fn notify_global(
  notifications: Notifications,
  text: String,
) -> Notifications {
  let text = normalize(text)
  journal.record("global", text)
  show(notifications, text)
}

/// Notify with a target location. If the player is at `current` the message
/// shows immediately; otherwise it is queued for `target`.
pub fn notify(
  notifications: Notifications,
  current current: String,
  target target: String,
  text text: String,
) -> Notifications {
  let text = normalize(text)
  // Every message lands in the playthrough journal as it is born, whether
  // shown now or queued for later.
  journal.record(target, text)
  case current == target {
    True -> show(notifications, text)
    False -> {
      let pending = dict.get(notifications.queues, target) |> result.unwrap([])
      Notifications(
        ..notifications,
        queues: dict.insert(
          notifications.queues,
          target,
          list.append(pending, [
            text,
          ]),
        ),
      )
    }
  }
}

/// Flush a location's queued messages into the log (oldest first), clearing the
/// queue.
pub fn flush(notifications: Notifications, location: String) -> Notifications {
  case dict.get(notifications.queues, location) {
    Ok(pending) -> {
      let flushed = list.fold(pending, notifications, show)
      Notifications(..flushed, queues: dict.delete(flushed.queues, location))
    }
    Error(_) -> notifications
  }
}
