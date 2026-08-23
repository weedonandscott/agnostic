//// Manual verification for `event.on_size_change`.
////
//// The outer box's size tracks the terminal, so its computed size changes on
//// every terminal resize — and once on the first layout at mount. Each such
//// change must fire `on_size_change`, incrementing the counter below.
////
//// Expected:
////   - The count shows 1 immediately at startup (the first layout counts).
////   - Resizing the terminal makes the count climb, one per size change.
////
//// Run with `gleam run` and resize the terminal window. Press `q` to quit.

import gleam/int

import agnostic
import agnostic/effect
import agnostic/platform/opentui
import agnostic/platform/opentui/attribute
import agnostic/platform/opentui/effect as tui_effect
import agnostic/platform/opentui/element
import agnostic/platform/opentui/event

pub fn main() {
  let config =
    opentui.default_config()
    |> opentui.use_mouse(False)

  use platform <- opentui.platform(config)
  let app = agnostic.application(init, update, view)
  let assert Ok(_) = agnostic.start(app, on: platform, with: Nil)
  Nil
}

pub type Model {
  Model(size_changes: Int)
}

pub type Msg {
  SizeChanged
  KeyPressed(tui_effect.KeyEvent)
}

fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  #(Model(size_changes: 0), tui_effect.subscribe_keyboard(KeyPressed))
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    SizeChanged -> #(Model(size_changes: model.size_changes + 1), effect.none())
    KeyPressed(key_event) ->
      case key_event.key {
        "q" -> #(model, tui_effect.destroy())
        _ -> #(model, effect.none())
      }
  }
}

fn view(model: Model) {
  element.box(
    [
      // The element under test. Its width/height are 100%, so its computed size
      // follows the terminal and every resize fires on_size_change.
      attribute.width_("100%"),
      attribute.height_("100%"),
      attribute.flex_direction("column"),
      attribute.align_items("center"),
      attribute.justify_content("center"),
      attribute.gap(1),
      event.on_size_change(SizeChanged),
    ],
    [
      element.text([
        attribute.content(
          "on_size_change fired: "
          <> int.to_string(model.size_changes)
          <> " time(s)",
        ),
        attribute.bold(True),
        attribute.color("#fff"),
      ]),
      element.text([
        attribute.content(
          "Should read 1 at startup, then climb as you resize the terminal.",
        ),
        attribute.color("#888"),
        attribute.dim(True),
      ]),
      element.text([
        attribute.content("Press q to quit."),
        attribute.color("#888"),
        attribute.dim(True),
      ]),
    ],
  )
}
