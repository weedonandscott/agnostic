// IMPORTS ---------------------------------------------------------------------

import agnostic
import agnostic/effect
import agnostic/element/html
import agnostic/event
import agnostic/platform
import agnostic/runtime/headless
import agnostic/runtime/transport
import agnostic/server_component
import agnostic/vdom/patch
import agnostic/vdom/path
import gleam/dynamic
import gleam/int
import gleam/json
import lustre_test

@target(erlang)
import agnostic/internals/mutable_map
@target(erlang)
import agnostic/platform/dom
@target(erlang)
import gleam/dict
@target(erlang)
import gleam/erlang/process

@target(javascript)
import argv
@target(javascript)
import booklet
@target(javascript)
import gleam/list

// CLIENT INTERACTION TESTS ----------------------------------------------------

@target(erlang)
pub fn client_connect_test() {
  use <- lustre_test.test_filter("client_connect_test")
  use client, _ <- with_erlang_runtime

  assert process.receive_forever(client)
    == transport.mount(
      True,
      True,
      [],
      [],
      [],
      dict.new(),
      view(0),
      mutable_map.new(),
    )
}

@target(erlang)
pub fn client_send_event_test() {
  use <- lustre_test.test_filter("client_send_event_test")
  use client, runtime <- with_erlang_runtime

  // Discard the `Mount` message
  let _ = process.receive_forever(client)

  let click = transport.event_fired(incr, "click", dynamic.nil())

  headless.ClientDispatchedMessage(click) |> agnostic.send(to: runtime)

  let patch =
    patch.new(0, 0, [patch.replace_text("1")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  assert process.receive_forever(client)
    == transport.reconcile(patch, mutable_map.new())
}

@target(erlang)
pub fn client_send_multiple_events_test() {
  use <- lustre_test.test_filter("client_send_multiple_events_test")
  use client, runtime <- with_erlang_runtime

  // Discard the `Mount` message
  let _ = process.receive_forever(client)

  let click = transport.event_fired(incr, "click", dynamic.nil())

  headless.ClientDispatchedMessage(click) |> agnostic.send(to: runtime)
  headless.ClientDispatchedMessage(click) |> agnostic.send(to: runtime)

  // Discard the first `Reconcile` message
  let _ = process.receive_forever(client)

  let patch =
    patch.new(0, 0, [patch.replace_text("2")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  assert process.receive_forever(client)
    == transport.reconcile(patch, mutable_map.new())
}

@target(erlang)
/// A `Batch` is folded over: every nested message updates the model the next
/// one sees, and every nested message's effect is performed. `Reset` first, so
/// a runtime that discarded the nested updates would produce an empty patch
/// instead of one that replaces the count with `2`.
///
pub fn client_send_batch_test() {
  use <- lustre_test.test_filter("client_send_batch_test")
  use client, runtime <- with_erlang_runtime

  // Discard the `Mount` message
  let _ = process.receive_forever(client)

  let click = transport.event_fired(incr, "click", dynamic.nil())
  let reset_click = transport.event_fired(reset, "click", dynamic.nil())

  transport.batch([reset_click, click, click])
  |> headless.ClientDispatchedMessage
  |> agnostic.send(to: runtime)

  let patch =
    patch.new(0, 0, [patch.replace_text("2")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  assert process.receive_forever(client)
    == transport.reconcile(patch, mutable_map.new())

  // `Reset`'s effect is dispatched back to the runtime, so its `Emit` arrives
  // after the reconcile.
  assert process.receive_forever(client) == transport.emit("reset", json.null())
}

@target(erlang)
/// A batch whose last nested message fails to resolve a handler. The fold
/// threads state, so the earlier successful message's vdom must survive: a
/// failing message returns what the previous one produced.
///
pub fn batch_partial_failure_test() {
  use <- lustre_test.test_filter("batch_partial_failure_test")
  use client, runtime <- with_erlang_runtime

  let _ = process.receive_forever(client)

  let click = transport.event_fired(incr, "click", dynamic.nil())
  let bogus = transport.event_fired(bogus, "click", dynamic.nil())

  transport.batch([click, bogus])
  |> headless.ClientDispatchedMessage
  |> agnostic.send(to: runtime)

  let patch =
    patch.new(0, 0, [patch.replace_text("1")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  assert process.receive_forever(client)
    == transport.reconcile(patch, mutable_map.new())
}

// EFFECT MESSAGE TESTS --------------------------------------------------------

@target(erlang)
pub fn effect_send_event_test() {
  use <- lustre_test.test_filter("effect_send_event_test")
  use client, runtime <- with_erlang_runtime

  // Discard the `Mount` message
  let _ = process.receive_forever(client)

  headless.EffectDispatchedMessage(Incr)
  |> agnostic.send(to: runtime)

  let patch =
    patch.new(0, 0, [patch.replace_text("1")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  assert process.receive_forever(client)
    == transport.reconcile(patch, mutable_map.new())
}

// SERVER MESSAGE TESTS --------------------------------------------------------

@target(erlang)
pub fn server_emit_event_test() {
  use <- lustre_test.test_filter("server_emit_event_test")
  use client, runtime <- with_erlang_runtime

  // Discard the `Mount` message
  let _ = process.receive_forever(client)

  let click = transport.event_fired(reset, "click", dynamic.nil())

  headless.ClientDispatchedMessage(click) |> agnostic.send(to: runtime)

  // Discard the first `Reconcile` message
  let _ = process.receive_forever(client)

  let emit = transport.emit("reset", json.null())

  assert process.receive_forever(client) == emit
}

// DEFERRED EFFECT TESTS -------------------------------------------------------

@target(erlang)
pub fn headless_drops_deferred_effects_test() {
  use <- lustre_test.test_filter("headless_drops_deferred_effects_test")

  // The synchronous effect dispatches Incr; the deferred effect would dispatch
  // Decr, but headless platforms declare no phases so it must never run.
  let init = fn(count) {
    #(
      count,
      effect.batch([
        effect.from(fn(dispatch) { dispatch(Incr) }),
        dom.before_paint(fn(dispatch, _root) { dispatch(Decr) }),
      ]),
    )
  }

  let app = agnostic.application(init, update, view)
  let assert Ok(runtime) = agnostic.start(app, on: platform.headless(), with: 0)
  let client = process.new_subject()

  server_component.register_subject(client) |> agnostic.send(to: runtime)

  // The synchronous effect ran before the client connected: the mounted view
  // shows the incremented count.
  assert process.receive_forever(client)
    == transport.mount(
      True,
      True,
      [],
      [],
      [],
      dict.new(),
      view(1),
      mutable_map.new(),
    )

  // The deferred effect is dropped: no patch ever arrives.
  let assert Error(Nil) = process.receive(client, 100)

  server_component.deregister_subject(client) |> agnostic.send(to: runtime)

  agnostic.shutdown() |> agnostic.send(to: runtime)
}

// JAVASCRIPT HEADLESS RUNTIME TESTS -------------------------------------------
//
// The JavaScript headless runtime lives entirely in `runtime/headless.ffi.mjs`
// and was previously untested: every test above is `@target(erlang)`, so this
// module compiled to an empty JavaScript module. These tests cover the message
// branches of `Runtime.send`.

@target(javascript)
/// Every branch of `Runtime.send` that we can drive from Gleam, in one test.
/// Each `send` below crashed before the fix, so any regression turns this red
/// immediately rather than at the final assertion.
///
pub fn javascript_headless_send_test() {
  use <- lustre_test.test_filter("javascript_headless_send_test")
  use received, runtime <- with_javascript_runtime(js_init)

  // The client receives a `Mount` message as soon as it registers.
  assert list.length(booklet.get(received)) == 1

  // `EffectDispatchedMessage`: the runtime updates the model and broadcasts a
  // reconcile.
  agnostic.dispatch(JsIncr) |> agnostic.send(to: runtime)

  assert list.length(booklet.get(received)) == 2

  // `ClientDispatchedMessage` wrapping an `EventFired` server message: two
  // separate destructuring sites in `send` and `#handle_client_message`.
  transport.event_fired(js_incr, "click", dynamic.nil())
  |> headless.ClientDispatchedMessage
  |> agnostic.send(to: runtime)

  assert list.length(booklet.get(received)) == 3

  // `EffectRemovedContextSubscription`: removes the decoder from the config
  // and tells the client to unsubscribe.
  headless.EffectRemovedContextSubscription("context")
  |> agnostic.send(to: runtime)

  assert list.length(booklet.get(received)) == 4
}

@target(javascript)
/// A headless app whose `init` returns an effect that dispatches a message. The
/// effect is deferred to a microtask, so the assertion has to happen on a later
/// tick.
///
pub fn javascript_headless_init_effect_test() {
  use <- async_test_filter("javascript_headless_init_effect_test")

  let init = fn(count) {
    #(count, effect.from(fn(dispatch) { dispatch(JsIncr) }))
  }

  use received, _runtime <- with_javascript_runtime(init)
  use <- next_tick

  // The mount message, then the reconcile produced by the dispatched message.
  assert list.length(booklet.get(received)) == 2
}

@target(javascript)
/// The `Batch` branch of `#handle_client_message` used to guard each nested
/// result with `Result$isOk` — a test that never held, because the nested call
/// returns an `Element`. The trailing `this.#model = model` then wrote back the
/// model captured before the loop, reverting every nested update. `Reset`
/// leads so the final count differs from the count the reverting runtime
/// produced: an empty patch instead of one replacing the text with `2`.
///
pub fn javascript_headless_batch_test() {
  use <- async_test_filter("javascript_headless_batch_test")
  use received, runtime <- with_javascript_runtime(js_init)

  let click = transport.event_fired(js_incr, "click", dynamic.nil())
  let reset_click = transport.event_fired(js_reset, "click", dynamic.nil())

  transport.batch([reset_click, click, click])
  |> headless.ClientDispatchedMessage
  |> agnostic.send(to: runtime)

  let expected =
    patch.new(0, 0, [patch.replace_text("2")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  let assert [transport.Reconcile(patch:, ..), ..] = booklet.get(received)
  assert patch == expected

  // `JsReset`'s effect is deferred to a microtask, so its `Emit` only reaches
  // the client on a later tick.
  use <- next_tick

  let assert [transport.Emit(name:, ..), ..] = booklet.get(received)
  assert name == "reset"
}

@target(javascript)
/// Mirror of `batch_partial_failure_test` on the JavaScript target.
///
pub fn javascript_headless_batch_partial_failure_test() {
  use <- async_test_filter("javascript_headless_batch_partial_failure_test")
  use received, runtime <- with_javascript_runtime(js_init)

  let click = transport.event_fired(js_incr, "click", dynamic.nil())
  let bogus = transport.event_fired(js_bogus, "click", dynamic.nil())

  transport.batch([click, bogus])
  |> headless.ClientDispatchedMessage
  |> agnostic.send(to: runtime)

  use <- next_tick

  let expected =
    patch.new(0, 0, [patch.replace_text("1")], [])
    |> patch.add_parent(1)
    |> patch.add_parent(0)
    |> patch.add_parent(0)

  let assert [transport.Reconcile(patch:, ..), ..] = booklet.get(received)
  assert patch == expected
}

// UTILS -----------------------------------------------------------------------

@target(javascript)
pub type Promise(value)

@target(javascript)
/// gleeunit awaits the value each test function returns, so a test that has to
/// wait for a deferred effect can return a promise. `lustre_test.test_filter`
/// is typed `fn() -> Nil` and cannot carry one, hence this variant.
///
fn async_test_filter(name: String, f: fn() -> Promise(Nil)) -> Promise(Nil) {
  case argv.load().arguments {
    ["--test-name-filter=" <> test_name, ..] if test_name == name -> f()
    ["--test-name-filter=" <> _, ..] -> resolved()

    _ -> f()
  }
}

@target(javascript)
@external(javascript, "./runtime_test.ffi.mjs", "next_tick")
fn next_tick(run: fn() -> Nil) -> Promise(Nil)

@target(javascript)
@external(javascript, "./runtime_test.ffi.mjs", "resolved")
fn resolved() -> Promise(Nil)

@target(javascript)
fn with_javascript_runtime(
  init: fn(Int) -> #(Int, effect.Effect(JsMessage)),
  run_test: fn(
    booklet.Booklet(List(transport.ClientMessage(JsMessage))),
    agnostic.Runtime(JsMessage),
  ) -> result,
) -> result {
  let received = booklet.new([])
  let app = agnostic.application(init, js_update, js_view)
  let assert Ok(runtime) = agnostic.start(app, on: platform.headless(), with: 0)

  server_component.register_callback(fn(message) {
    let _ = booklet.update(received, fn(messages) { [message, ..messages] })
    Nil
  })
  |> agnostic.send(to: runtime)

  run_test(received, runtime)
}

@target(javascript)
fn js_init(count) {
  #(count, effect.none())
}

@target(javascript)
type JsMessage {
  JsIncr
  JsDecr
  JsReset
}

@target(javascript)
fn js_update(model, message) {
  case message {
    JsIncr -> #(model + 1, effect.none())
    JsDecr -> #(model - 1, effect.none())
    JsReset -> #(0, event.emit("reset", json.null()))
  }
}

@target(javascript)
const js_incr = "0" <> path.separator_element <> "2"

@target(javascript)
const js_reset = "0" <> path.separator_element <> "3"

@target(javascript)
const js_bogus = "0" <> path.separator_element <> "9"

@target(javascript)
fn js_view(model) {
  html.div([], [
    html.button([event.on_click(JsDecr)], [html.text("-")]),
    html.p([], [html.text(int.to_string(model))]),
    html.button([event.on_click(JsIncr)], [html.text("+")]),
    html.button([event.on_click(JsReset)], [html.text("reset")]),
  ])
}

@target(erlang)
fn with_erlang_runtime(run_test) {
  let app = agnostic.application(init, update, view)
  let assert Ok(runtime) = agnostic.start(app, on: platform.headless(), with: 0)
  let client = process.new_subject()

  server_component.register_subject(client) |> agnostic.send(to: runtime)

  run_test(client, runtime)

  server_component.deregister_subject(client) |> agnostic.send(to: runtime)

  agnostic.shutdown() |> agnostic.send(to: runtime)
}

// COUNTER APP -----------------------------------------------------------------

@target(erlang)
fn init(count) {
  #(count, effect.none())
}

@target(erlang)
type Message {
  Incr
  Decr
  Reset
}

@target(erlang)
fn update(model, message) {
  case message {
    Incr -> #(model + 1, effect.none())
    Decr -> #(model - 1, effect.none())
    Reset -> #(0, event.emit("reset", json.null()))
  }
}

@target(erlang)
const incr = "0" <> path.separator_element <> "2"

@target(erlang)
const reset = "0" <> path.separator_element <> "3"

@target(erlang)
const bogus = "0" <> path.separator_element <> "9"

@target(erlang)
fn view(model) {
  html.div([], [
    html.button([event.on_click(Decr)], [html.text("-")]),
    html.p([], [html.text(int.to_string(model))]),
    html.button([event.on_click(Incr)], [html.text("+")]),
    html.button([event.on_click(Reset)], [html.text("reset")]),
  ])
}
