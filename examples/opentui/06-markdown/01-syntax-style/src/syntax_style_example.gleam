//// Declaring syntax styles on the config, and switching between them while
//// the app is running.
////
//// A `SyntaxStyle` maps tree-sitter capture names — `markup.heading.1`,
//// `markup.strong`, `keyword`, … — to a foreground, a background and the four
//// text flags.
////
//// Styles are declared on the `Config`, by name, once; the attribute picks one
//// per element. Pressing `t` points `attribute.syntax_style` at the other
//// registered name, which restyles the live node in place.
////
//// One block does not follow: the horizontal rule below keeps the colour it
//// was built with. OpenTUI reads its border from `conceal` once, when the
//// rule is created, and the pass that re-applies a new style to every other
//// block skips it. Block quote bars, which read the same capture, do restyle.
////
//// The two theme functions below double as the list of capture names the
//// markdown and code renderers actually ask for.

// IMPORTS ---------------------------------------------------------------------

import agnostic
import agnostic/effect
import agnostic/element.{type Element}
import agnostic/platform/opentui
import agnostic/platform/opentui/attribute
import agnostic/platform/opentui/effect as tui_effect
import agnostic/platform/opentui/element as tui
import agnostic/platform/opentui/syntax
import gleam/string

// MAIN ------------------------------------------------------------------------

pub fn main() {
  // Both themes are built here, once. A registered style is a handle to an
  // allocation in OpenTUI's core that lives for the process, so there is
  // nothing per-frame and nothing to free.
  let config =
    opentui.default_config()
    |> opentui.use_mouse(False)
    |> opentui.register_syntax_style(theme_name(Dark), dark_theme())
    |> opentui.register_syntax_style(theme_name(Light), light_theme())

  use platform <- opentui.platform(config)
  let app = agnostic.application(init, update, view)
  let assert Ok(_) = agnostic.start(app, on: platform, with: Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(theme: Theme)
}

/// The two registered styles. Names are plain strings at the API boundary, so
/// both ends go through `theme_name`: a name that was never registered is not
/// an error, it just falls back to the unstyled default.
///
type Theme {
  Dark
  Light
}

fn theme_name(theme: Theme) -> String {
  case theme {
    Dark -> "dark"
    Light -> "light"
  }
}

fn theme_bg(theme: Theme) -> String {
  case theme {
    Dark -> "#0D1117"
    Light -> "#FFFFFF"
  }
}

fn other(theme: Theme) -> Theme {
  case theme {
    Dark -> Light
    Light -> Dark
  }
}

fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  #(Model(theme: Dark), tui_effect.subscribe_keyboard(KeyPressed))
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  KeyPressed(tui_effect.KeyEvent)
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    KeyPressed(key_event) ->
      case key_event.key, key_event.ctrl {
        "q", True -> #(model, tui_effect.destroy())
        // Only the attribute value changes. The markdown node is kept and
        // restyled, not rebuilt.
        "t", _ -> #(Model(theme: other(model.theme)), effect.none())
        _, _ -> #(model, effect.none())
      }
  }
}

// THEMES ----------------------------------------------------------------------

/// Lookup is the exact capture name, then the segment before the *first* dot;
/// `default` applies to a span only when none of its captures contributed.
///
/// `markup.heading.4`, `.5` and `.6` are left out on purpose: the first-dot
/// rule takes them to `markup`, never to `markup.heading`, so with no `markup`
/// entry registered they land on `default`. That same rule is why one `keyword`
/// entry covers TypeScript's `keyword.import`, `keyword.return` and the rest.
///
fn dark_theme() -> List(syntax.Style) {
  [
    // Everything the renderer cannot place — paragraph prose most of all.
    syntax.style("default") |> syntax.fg("#E6EDF3"),
    // Syntax markers the renderer hides — heading `#`s and link brackets among
    // them. Its foreground is also what block quote bars, horizontal rules and
    // table borders are drawn in, so it needs a colour even though the markers
    // themselves are gone.
    syntax.style("conceal") |> syntax.fg("#484F58") |> syntax.dim(True),
    // Headings. The level-less `markup.heading` is what table header cells use.
    syntax.style("markup.heading") |> syntax.fg("#79C0FF") |> syntax.bold(True),
    syntax.style("markup.heading.1")
      |> syntax.fg("#58A6FF")
      |> syntax.bold(True),
    syntax.style("markup.heading.2")
      |> syntax.fg("#79C0FF")
      |> syntax.bold(True),
    syntax.style("markup.heading.3")
      |> syntax.fg("#A5D6FF")
      |> syntax.bold(True),
    // Inline emphasis.
    syntax.style("markup.strong") |> syntax.fg("#FFA657") |> syntax.bold(True),
    syntax.style("markup.italic") |> syntax.fg("#D2A8FF") |> syntax.italic(True),
    syntax.style("markup.strikethrough")
      |> syntax.fg("#8B949E")
      |> syntax.dim(True),
    // Inline `code` spans. A fenced block goes to a CodeRenderable and uses the
    // code captures below instead; with no parser for its info string it falls
    // back to plain unstyled text rather than to `markup.raw`.
    syntax.style("markup.raw") |> syntax.fg("#7EE787"),
    // Links: the brackets and parens, the label, the destination.
    syntax.style("markup.link") |> syntax.fg("#8B949E"),
    syntax.style("markup.link.label") |> syntax.fg("#58A6FF"),
    syntax.style("markup.link.url")
      |> syntax.fg("#A5D6FF")
      |> syntax.underline(True),
    // List bullets and numbers — the marker only, not the item text.
    syntax.style("markup.list") |> syntax.fg("#FFA657"),
    // Block quote bodies.
    syntax.style("markup.quote") |> syntax.fg("#8B949E") |> syntax.italic(True),
    // Inside a fenced block the ordinary code captures apply, resolved against
    // this same table.
    syntax.style("keyword") |> syntax.fg("#FF7B72"),
    syntax.style("string") |> syntax.fg("#A5D6FF"),
    syntax.style("comment") |> syntax.fg("#8B949E") |> syntax.italic(True),
    syntax.style("function") |> syntax.fg("#D2A8FF"),
    syntax.style("number") |> syntax.fg("#79C0FF"),
    syntax.style("boolean") |> syntax.fg("#79C0FF"),
    syntax.style("type") |> syntax.fg("#FFA657"),
    syntax.style("variable") |> syntax.fg("#E6EDF3"),
  ]
}

/// The same captures again, tuned for a light terminal background. Switching
/// between the two is all the `t` key does.
///
fn light_theme() -> List(syntax.Style) {
  [
    syntax.style("default") |> syntax.fg("#24292F"),
    syntax.style("conceal") |> syntax.fg("#8C959F") |> syntax.dim(True),
    syntax.style("markup.heading") |> syntax.fg("#0550AE") |> syntax.bold(True),
    syntax.style("markup.heading.1")
      |> syntax.fg("#0550AE")
      |> syntax.bold(True),
    syntax.style("markup.heading.2")
      |> syntax.fg("#0969DA")
      |> syntax.bold(True),
    syntax.style("markup.heading.3")
      |> syntax.fg("#218BFF")
      |> syntax.bold(True),
    syntax.style("markup.strong") |> syntax.fg("#953800") |> syntax.bold(True),
    syntax.style("markup.italic") |> syntax.fg("#8250DF") |> syntax.italic(True),
    syntax.style("markup.strikethrough")
      |> syntax.fg("#6E7781")
      |> syntax.dim(True),
    syntax.style("markup.raw") |> syntax.fg("#116329"),
    syntax.style("markup.link") |> syntax.fg("#6E7781"),
    syntax.style("markup.link.label") |> syntax.fg("#0969DA"),
    syntax.style("markup.link.url")
      |> syntax.fg("#0550AE")
      |> syntax.underline(True),
    syntax.style("markup.list") |> syntax.fg("#953800"),
    syntax.style("markup.quote") |> syntax.fg("#6E7781") |> syntax.italic(True),
    syntax.style("keyword") |> syntax.fg("#CF222E"),
    syntax.style("string") |> syntax.fg("#0A3069"),
    syntax.style("comment") |> syntax.fg("#6E7781") |> syntax.italic(True),
    syntax.style("function") |> syntax.fg("#8250DF"),
    syntax.style("number") |> syntax.fg("#0550AE"),
    syntax.style("boolean") |> syntax.fg("#0550AE"),
    syntax.style("type") |> syntax.fg("#953800"),
    syntax.style("variable") |> syntax.fg("#24292F"),
  ]
}

// DOCUMENT --------------------------------------------------------------------

/// One document touching every capture the themes register. Built from a list
/// of lines rather than a multi-line string literal because markdown is
/// indentation-sensitive and a literal would carry this file's indentation
/// into it.
///
fn document() -> String {
  string.join(
    [
      // The `#` markers are `conceal`; the heading text is `markup.heading.N`.
      "# syntax_style",
      "",
      "Prose is `default`. **Bold** is `markup.strong`, *italic* is",
      "`markup.italic`, ~~struck out~~ is `markup.strikethrough`, and a",
      "`code span` is `markup.raw`.",
      "",
      "## Lists and links",
      "",
      // The bullet is `markup.list`; the item text after it is `default`.
      "- the bullet is styled, the item text is not",
      "- [a link label](https://gleam.run) is `markup.link.label`, and the",
      "  destination beside it is `markup.link.url`",
      "",
      // Drawn with `conceal`'s foreground, same as the block quote bar below.
      "---",
      "",
      "> A block quote is `markup.quote`, and the bar down its left edge",
      "> takes `conceal`'s foreground.",
      "",
      "### Fenced code",
      "",
      // The info string picks the parser. OpenTUI ships parsers for
      // javascript, typescript, zig and markdown itself; a fence tagged with
      // anything else has no parser, so its body is never tokenised.
      "```ts",
      "// comments are the `comment` capture",
      "import { readFile } from 'node:fs/promises'",
      "",
      "type Level = 1 | 2 | 3",
      "",
      "export async function load(name: string, level: Level) {",
      "  const trim: boolean = true",
      "  const raw = await readFile(name, 'utf8')",
      "  return trim ? raw.trimEnd() : raw",
      "}",
      "```",
    ],
    "\n",
  )
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  tui.box(
    [
      attribute.flex_direction("column"),
      attribute.width_("100%"),
      attribute.height_("100%"),
      attribute.padding(1),
      attribute.gap(1),
    ],
    [status(model), viewer(model)],
  )
}

fn status(model: Model) -> Element(Msg) {
  tui.box(
    [
      attribute.flex_direction("row"),
      attribute.gap(1),
      attribute.align_items("center"),
    ],
    [
      tui.text([attribute.content("syntax_style:"), attribute.color("#888")]),
      tui.text([
        attribute.content(theme_name(model.theme)),
        attribute.color("#7c6ff5"),
        attribute.bold(True),
      ]),
      tui.text([
        attribute.content(
          "t switches to " <> theme_name(other(model.theme)) <> ", Ctrl+Q quits",
        ),
        attribute.color("#888"),
        attribute.dim(True),
      ]),
    ],
  )
}

fn viewer(model: Model) -> Element(Msg) {
  tui.box(
    [
      attribute.flex_direction("column"),
      attribute.width_("100%"),
      attribute.border_style("round"),
      attribute.border_color("#444"),
      // Blocks inside the markdown are spaced with margins that nothing
      // paints, so the box carries the background too.
      attribute.background_color(theme_bg(model.theme)),
      attribute.padding_left(2),
      attribute.padding_right(2),
      attribute.title(" markdown "),
      attribute.title_alignment("center"),
    ],
    [
      tui.markdown(
        [
          // The whole point of the example. The value is just the name the
          // style was registered under, so a theme switch is a string change
          // the reconciler can diff — nothing structural crosses per render.
          attribute.syntax_style(theme_name(model.theme)),
          attribute.bg(theme_bg(model.theme)),
          attribute.content(document()),
          attribute.width_("100%"),
        ],
        [],
      ),
    ],
  )
}
