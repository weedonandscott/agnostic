//// Decoder-shape tests for `agnostic/platform/opentui/event`.
////
//// These pin the payload shape each OpenTUI event handler expects against the
//// shape `opentui.ffi.ts` actually delivers. They stop at the decoder: the FFI
//// half — which OpenTUI property or emitter event a Lustre event name is wired
//// to — needs a live `CliRenderer`, and @opentui/core's native FFI is
//// Bun-only, while `gleam test --target javascript` runs on Node.

// IMPORTS ---------------------------------------------------------------------

import agnostic/platform/opentui/element
import agnostic/platform/opentui/event
import agnostic/vdom/cache
import agnostic/vdom/vattr.{Handler}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/result
import lustre_test

// TYPES -----------------------------------------------------------------------

type Msg {
  SliderChanged(Float)
  Changed(String)
}

// HELPERS ---------------------------------------------------------------------

fn payload(encoded: String) -> Dynamic {
  encoded
  |> json.parse(decode.dynamic)
  |> result.unwrap(dynamic.nil())
}

// TESTS -----------------------------------------------------------------------

/// `SliderRenderable` reports a value change with `emit("change", { value })`,
/// which the FFI wraps as `event.detail`. The handler must read
/// `detail.value`, not `detail`.
///
pub fn slider_change_reads_detail_value_test() {
  use <- lustre_test.test_filter("slider_change_reads_detail_value_test")

  let vdom = element.slider([event.on_slider_change(SliderChanged)])
  let events = cache.from_node(vdom)

  let #(_, actual) =
    cache.handle(
      events,
      "0",
      "sliderchange",
      payload("{\"detail\":{\"value\":42.0}}"),
    )

  assert actual
    == Ok(Handler(
      prevent_default: False,
      stop_propagation: False,
      message: SliderChanged(42.0),
    ))
}

/// The shape the handler used to expect. Nothing emits it, so decoding it must
/// fail — otherwise the handler has drifted back onto the dead path.
///
pub fn slider_change_rejects_bare_detail_test() {
  use <- lustre_test.test_filter("slider_change_rejects_bare_detail_test")

  let vdom = element.slider([event.on_slider_change(SliderChanged)])
  let events = cache.from_node(vdom)

  let #(_, actual) =
    cache.handle(events, "0", "sliderchange", payload("{\"detail\":42.0}"))

  assert result.is_error(actual)
}

/// `on_change` is shared with `InputRenderable`, which emits `change` with a
/// bare string rather than the slider's `{ value }` record. The two shapes are
/// why `sliderchange` stays a separate Lustre event name.
///
pub fn change_reads_bare_string_detail_test() {
  use <- lustre_test.test_filter("change_reads_bare_string_detail_test")

  let vdom = element.input([event.on_change(Changed)])
  let events = cache.from_node(vdom)

  let #(_, actual) =
    cache.handle(events, "0", "change", payload("{\"detail\":\"hello\"}"))

  assert actual
    == Ok(Handler(
      prevent_default: False,
      stop_propagation: False,
      message: Changed("hello"),
    ))
}
