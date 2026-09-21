//// Encoder-shape tests for `agnostic/platform/opentui/syntax` and the
//// `syntax_style` attribute that addresses a registered theme by name.
////
//// These pin the JSON `opentui.register_syntax_style` hands to OpenTUI's
//// `SyntaxStyle.fromStyles` against the field names that constructor reads,
//// and the attribute against the name `opentui.ffi.ts` intercepts. They stop
//// there: a `SyntaxStyle` only exists once @opentui/core has resolved its
//// native render library, which `gleam test` cannot do on either target.
////
//// The encoded object is read back through a JSON round trip rather than
//// compared against `json.to_string` output, so no test depends on the order
//// the encoder emits fields in.

// IMPORTS ---------------------------------------------------------------------

import agnostic/platform/opentui/attribute
import agnostic/platform/opentui/syntax
import agnostic/vdom/vattr.{Attribute}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lustre_test

// HELPERS ---------------------------------------------------------------------

/// The object `register_syntax_style` stores on `Config`, read back as
/// `Dynamic` so a test can assert one field at a time.
///
fn encoded(styles: List(syntax.Style)) -> Dynamic {
  styles
  |> syntax.to_json
  |> json.to_string
  |> json.parse(decode.dynamic)
  |> result.unwrap(dynamic.nil())
}

fn at(
  styles: List(syntax.Style),
  path: List(String),
  decoder: decode.Decoder(a),
) -> Result(a, List(decode.DecodeError)) {
  decode.run(encoded(styles), decode.at(path, decoder))
}

/// Every field emitted for `capture`, sorted, so an assertion covers the whole
/// record rather than only the fields it names.
///
fn keys(styles: List(syntax.Style), capture: String) -> List(String) {
  let record = decode.dict(decode.string, decode.dynamic)

  encoded(styles)
  |> decode.run(decode.at([capture], record))
  |> result.map(dict.keys)
  |> result.unwrap([])
  |> list.sort(string.compare)
}

// TESTS -----------------------------------------------------------------------

/// `opentui.ffi.ts` maps `syntax-style` through `ATTR_MAP` and intercepts the
/// resulting `syntaxStyle` by name, resolving the value against the registry
/// `register_syntax_style` fills. The value therefore has to reach it as a
/// plain string attribute, not a property.
///
pub fn syntax_style_is_a_string_attribute_test() {
  use <- lustre_test.test_filter("syntax_style_is_a_string_attribute_test")

  assert attribute.syntax_style("handbook")
    == Attribute(
      kind: vattr.attribute_kind,
      name: "syntax-style",
      value: "handbook",
    )
}

/// `SyntaxStyle.fromStyles` reads `fg` and `bg`, not `foreground` and
/// `background`. Every field that was never set is left out rather than sent
/// as null or `false`: `treeSitterToTextChunks` merges the captures covering
/// one span field by field, guarded on `!== undefined`, so a `false` on a more
/// specific capture would switch off an attribute a less specific one set.
///
pub fn to_json_emits_only_fields_that_were_set_test() {
  use <- lustre_test.test_filter("to_json_emits_only_fields_that_were_set_test")

  let theme = [
    syntax.style("keyword") |> syntax.fg("#58A6FF") |> syntax.bold(True),
    syntax.style("conceal") |> syntax.dim(True),
    syntax.style("markup.strong") |> syntax.italic(False),
  ]

  assert keys(theme, "keyword") == ["bold", "fg"]
  assert keys(theme, "conceal") == ["dim"]
  assert keys(theme, "markup.strong") == ["italic"]

  assert at(theme, ["keyword", "fg"], decode.string) == Ok("#58A6FF")
  assert at(theme, ["keyword", "bold"], decode.bool) == Ok(True)
  assert at(theme, ["conceal", "dim"], decode.bool) == Ok(True)
  assert at(theme, ["markup.strong", "italic"], decode.bool) == Ok(False)
}

/// A theme is written as a pipeline, so every setter has to carry the ones set
/// before it.
///
pub fn style_setters_compose_test() {
  use <- lustre_test.test_filter("style_setters_compose_test")

  let theme = [
    syntax.style("markup.strong")
      |> syntax.fg("#fff")
      |> syntax.bold(True)
      |> syntax.italic(True),
    syntax.style("markup.link.url")
      |> syntax.bg("#000")
      |> syntax.underline(True)
      |> syntax.dim(True),
  ]

  assert keys(theme, "markup.strong") == ["bold", "fg", "italic"]
  assert at(theme, ["markup.strong", "fg"], decode.string) == Ok("#fff")
  assert at(theme, ["markup.strong", "bold"], decode.bool) == Ok(True)
  assert at(theme, ["markup.strong", "italic"], decode.bool) == Ok(True)

  assert keys(theme, "markup.link.url") == ["bg", "dim", "underline"]
  assert at(theme, ["markup.link.url", "bg"], decode.string) == Ok("#000")
  assert at(theme, ["markup.link.url", "underline"], decode.bool) == Ok(True)
  assert at(theme, ["markup.link.url", "dim"], decode.bool) == Ok(True)
}

/// The encoded object has one entry per capture, so naming a capture twice
/// keeps the last entry whole — the second `default` replaces the first rather
/// than merging with it.
///
pub fn duplicate_captures_keep_the_last_test() {
  use <- lustre_test.test_filter("duplicate_captures_keep_the_last_test")

  let theme = [
    syntax.style("default") |> syntax.fg("#111111") |> syntax.italic(True),
    syntax.style("default") |> syntax.fg("#222222") |> syntax.bold(True),
  ]

  assert keys(theme, "default") == ["bold", "fg"]
  assert at(theme, ["default", "fg"], decode.string) == Ok("#222222")
  assert at(theme, ["default", "bold"], decode.bool) == Ok(True)
}

/// `define_syntax_style` reaches the FFI as a property rather than a string
/// attribute, carrying the theme beside the name that keys it. `set_property`
/// intercepts on the property name, so that name is `syntaxStyle` — already
/// camelCase, since properties skip `ATTR_MAP`.
///
pub fn define_syntax_style_carries_name_and_styles_test() {
  use <- lustre_test.test_filter(
    "define_syntax_style_carries_name_and_styles_test",
  )

  let assert vattr.Property(kind:, name:, value:) =
    attribute.define_syntax_style("handbook", [
      syntax.style("keyword") |> syntax.fg("#58A6FF") |> syntax.bold(True),
    ])

  assert kind == vattr.property_kind
  assert name == "syntaxStyle"

  let spec =
    value
    |> json.to_string
    |> json.parse(decode.dynamic)
    |> result.unwrap(dynamic.nil())

  assert decode.run(spec, decode.at(["name"], decode.string)) == Ok("handbook")
  assert decode.run(spec, decode.at(["styles", "keyword", "fg"], decode.string))
    == Ok("#58A6FF")
  assert decode.run(spec, decode.at(["styles", "keyword", "bold"], decode.bool))
    == Ok(True)
}
