//// Syntax styles for OpenTUI's highlighted-text renderables: `markdown`,
//// `code`, and `diff`. Each of them resolves every span of text through an
//// OpenTUI `SyntaxStyle`: a lookup table from tree-sitter capture name —
//// `"default"`, `"markup.strong"`, `"keyword"`, … — to a colour and a set of
//// text attributes.
////
//// A theme is a `List(Style)`, declared on the config under a name with
//// [`opentui.register_syntax_style`](../opentui.html#register_syntax_style)
//// and selected per element by that name with
//// [`opentui/attribute.syntax_style`](./attribute.html#syntax_style).
////
//// ```gleam
//// opentui.default_config()
//// |> opentui.register_syntax_style("handbook", [
////   syntax.style("default") |> syntax.fg("#E6EDF3"),
////   syntax.style("markup.heading.1")
////     |> syntax.fg("#58A6FF")
////     |> syntax.bold(True),
////   syntax.style("markup.link.url")
////     |> syntax.fg("#A5D6FF")
////     |> syntax.underline(True),
////   syntax.style("conceal") |> syntax.dim(True),
//// ])
//// ```
////
//// ## Capture names
////
//// Capture names come from the grammar, so the full set is whatever
//// `@opentui/core`'s `assets/<grammar>/highlights.scm` emits — not a closed
//// list. The ones worth styling first, for `markdown`: `default`, `conceal`,
//// `markup.heading` plus `markup.heading.1` through `markup.heading.6`,
//// `markup.strong`, `markup.italic`, `markup.strikethrough`, `markup.raw`,
//// `markup.link`, `markup.link.label`, `markup.link.url`, `markup.list`, and
//// `markup.quote`. `code` adds the usual code captures — `keyword`, `string`,
//// `comment`, `function`, `number`, and so on — for whichever filetype it is
//// given. A capture with no entry contributes nothing to the span.
////
//// ## Lookup drops everything after the first dot
////
//// A capture resolves to the entry registered under its exact name; failing
//// that, to the entry registered under the segment before its *first* dot.
//// `markup.heading.1` falls back to `markup`, not to `markup.heading`, so
//// register every level you want to style. `default` applies to a span only
//// when none of the captures covering it contributed anything.
////
//// ## Attributes you never set are left out
////
//// An entry that never calls [`bold`](#bold) sends no `bold` at all;
//// `bold(False)` sends an explicit `false`. That matters where two *different*
//// captures cover one span — markdown's `spell` sits under every paragraph,
//// and an emphasis capture like `markup.strong` sits on a run inside it. The
//// highlighter merges those least-specific first, field by field, skipping
//// fields an entry does not carry, so a colour-only `markup.strong` leaves
//// `spell`'s attributes standing. An explicit `false` switches them off.
////
//// This is merging between captures, not inheritance along one. A capture
//// resolves to exactly one entry, by the rule above, and `keyword.import`
//// registered on its own therefore replaces `keyword` rather than adding to
//// it.
////

// IMPORTS ---------------------------------------------------------------------

import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

// TYPES -----------------------------------------------------------------------

/// A style for one tree-sitter capture name: a foreground and background
/// colour, and the four text attributes. Seed one with [`style`](#style) and
/// pipe it through the setters below.
///
pub opaque type Style {
  Style(
    capture: String,
    fg: Option(String),
    bg: Option(String),
    bold: Option(Bool),
    italic: Option(Bool),
    underline: Option(Bool),
    dim: Option(Bool),
  )
}

// BUILDERS --------------------------------------------------------------------

/// Set the foreground colour. OpenTUI parses this as a `ColorInput`, so a hex
/// string like `"#58A6FF"` and a CSS colour name like `"cyan"` both work.
///
pub fn fg(style: Style, value: String) -> Style {
  Style(..style, fg: Some(value))
}

/// Set the background colour. OpenTUI parses this as a `ColorInput`, so a hex
/// string like `"#0D1117"` and a CSS colour name like `"black"` both work.
///
pub fn bg(style: Style, value: String) -> Style {
  Style(..style, bg: Some(value))
}

/// Render matching text bold.
///
pub fn bold(style: Style, value: Bool) -> Style {
  Style(..style, bold: Some(value))
}

/// Render matching text italic.
///
pub fn italic(style: Style, value: Bool) -> Style {
  Style(..style, italic: Some(value))
}

/// Render matching text underlined.
///
pub fn underline(style: Style, value: Bool) -> Style {
  Style(..style, underline: Some(value))
}

/// Render matching text dimmed.
///
pub fn dim(style: Style, value: Bool) -> Style {
  Style(..style, dim: Some(value))
}

// CONSTRUCTORS ----------------------------------------------------------------

/// Create a style for a tree-sitter capture name, with no colours and no
/// attributes set. Capture names are the grammar's own: `"default"`,
/// `"conceal"`, `"markup.strong"`, `"keyword"`, and so on.
///
pub fn style(capture: String) -> Style {
  Style(
    capture:,
    fg: None,
    bg: None,
    bold: None,
    italic: None,
    underline: None,
    dim: None,
  )
}

// ENCODERS --------------------------------------------------------------------

/// Encode a theme as the JSON object OpenTUI wants: one entry per capture
/// name, under OpenTUI's own field names, carrying only the fields that were
/// set.
///
/// You should not need to call this yourself —
/// [`opentui.register_syntax_style`](../opentui.html#register_syntax_style)
/// does it for you. It is public only because `Config` is opaque, so that
/// function has to live in `opentui`, where it cannot reach inside a `Style`.
///
pub fn to_json(styles: List(Style)) -> Json {
  styles
  |> list.fold([], fn(entries, style) {
    // Fields that were never set are left out entirely rather than sent as
    // `false`. OpenTUI merges the styles covering one span field by field,
    // skipping absent fields, so an explicit `false` on a more specific
    // capture would switch off an attribute a less specific one had turned on.
    let fields =
      [
        #("fg", style.fg |> option.map(json.string)),
        #("bg", style.bg |> option.map(json.string)),
        #("bold", style.bold |> option.map(json.bool)),
        #("italic", style.italic |> option.map(json.bool)),
        #("underline", style.underline |> option.map(json.bool)),
        #("dim", style.dim |> option.map(json.bool)),
      ]
      |> list.filter_map(fn(field) {
        case field {
          #(name, Some(value)) -> Ok(#(name, value))
          #(_, None) -> Error(Nil)
        }
      })
      |> json.object
    list.key_set(entries, style.capture, fields)
  })
  |> json.object
}
