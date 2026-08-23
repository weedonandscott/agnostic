//// The OpenTUI platform for Lustre. This module provides a platform
//// configuration that targets `@opentui/core` for building terminal user
//// interfaces with Lustre's MVU architecture.
////

// IMPORTS ---------------------------------------------------------------------

import gleam/list
import gleam/option.{type Option, None, Some}

@target(javascript)
import agnostic/platform.{type Platform}

// TYPES -----------------------------------------------------------------------

/// A type representing a TUI renderable node from @opentui/core.
///
pub type Node

/// A type representing a TUI event.
///
pub type Event

/// A type representing a TUI property value.
///
pub type Value

/// A type representing an OpenTUI CLI renderer.
///
pub type Renderer

/// A factory function that receives the renderer and returns a renderable node.
/// Used with `register_element` to define custom element types.
///
pub type ElementFactory =
  fn(Renderer) -> Node

/// A signal name, as accepted by [`exit_signals`](#exit_signals).
///
pub type Signal {
  Sigabrt
  Sigalrm
  Sigbus
  Sigchld
  Sigcont
  Sigfpe
  Sighup
  Sigill
  Sigint
  Sigio
  Sigiot
  Sigpipe
  Sigpoll
  Sigprof
  Sigpwr
  Sigquit
  Sigsegv
  Sigstkflt
  Sigsys
  Sigterm
  Sigtrap
  Sigtstp
  Sigttin
  Sigttou
  Sigunused
  Sigurg
  Sigusr1
  Sigusr2
  Sigvtalrm
  Sigwinch
  Sigxcpu
  Sigxfsz
  Sigbreak
  Siglost
  Siginfo
}

fn signal_to_string(signal: Signal) -> String {
  case signal {
    Sigabrt -> "SIGABRT"
    Sigalrm -> "SIGALRM"
    Sigbus -> "SIGBUS"
    Sigchld -> "SIGCHLD"
    Sigcont -> "SIGCONT"
    Sigfpe -> "SIGFPE"
    Sighup -> "SIGHUP"
    Sigill -> "SIGILL"
    Sigint -> "SIGINT"
    Sigio -> "SIGIO"
    Sigiot -> "SIGIOT"
    Sigpipe -> "SIGPIPE"
    Sigpoll -> "SIGPOLL"
    Sigprof -> "SIGPROF"
    Sigpwr -> "SIGPWR"
    Sigquit -> "SIGQUIT"
    Sigsegv -> "SIGSEGV"
    Sigstkflt -> "SIGSTKFLT"
    Sigsys -> "SIGSYS"
    Sigterm -> "SIGTERM"
    Sigtrap -> "SIGTRAP"
    Sigtstp -> "SIGTSTP"
    Sigttin -> "SIGTTIN"
    Sigttou -> "SIGTTOU"
    Sigunused -> "SIGUNUSED"
    Sigurg -> "SIGURG"
    Sigusr1 -> "SIGUSR1"
    Sigusr2 -> "SIGUSR2"
    Sigvtalrm -> "SIGVTALRM"
    Sigwinch -> "SIGWINCH"
    Sigxcpu -> "SIGXCPU"
    Sigxfsz -> "SIGXFSZ"
    Sigbreak -> "SIGBREAK"
    Siglost -> "SIGLOST"
    Siginfo -> "SIGINFO"
  }
}

/// The Kitty keyboard protocol configuration, as accepted by
/// [`with_kitty_keyboard`](#with_kitty_keyboard).
///
/// `KittyOff` disables the protocol entirely — every flag off. `KittyOn`
/// enables it and selects which of OpenTUI's five flags are on, mirroring
/// `KittyKeyboardOptions` in `@opentui/core`.
///
/// Held as an `Option(KittyConfig)`: [`default_config`](#default_config) leaves it
/// `None`, which sends nothing to OpenTUI so its own default applies. We defer
/// to that default rather than copy it, so ours can't drift from OpenTUI's.
///
pub type KittyConfig {
  KittyOff
  KittyOn(
    disambiguate: Bool,
    alternate_keys: Bool,
    events: Bool,
    all_keys_as_escapes: Bool,
    report_text: Bool,
  )
}

/// Where the renderer owns terminal space, as accepted by
/// [`screen_mode`](#screen_mode). Mirrors OpenTUI's `ScreenMode`:
/// `AlternateScreen` uses the terminal's alternate buffer, `MainScreen` renders
/// on the main screen, and `SplitFooter` keeps the renderer in a reserved
/// footer on the main screen.
///
/// Held as an `Option(ScreenMode)`: [`default_config`](#default_config) leaves it
/// `None`, which sends nothing so OpenTUI's own default applies.
///
pub type ScreenMode {
  AlternateScreen
  MainScreen
  SplitFooter
}

/// What the built-in console overlay does, as accepted by
/// [`console_mode`](#console_mode). Mirrors OpenTUI's `ConsoleMode`:
/// `ConsoleOverlay` shows the overlay, `Disabled` turns it off.
///
/// Held as an `Option(ConsoleMode)`: [`default_config`](#default_config) leaves it
/// `None`, which sends nothing so OpenTUI's own default applies.
///
pub type ConsoleMode {
  ConsoleOverlay
  Disabled
}

// EFFECT PHASES ---------------------------------------------------------------

/// The phase name tagged by
/// [`opentui/effect.frame_callbacks`](./opentui/effect.html#frame_callbacks)
/// and declared by the OpenTUI platform. Public so custom platforms can
/// declare a [`Phase`](../platform.html#Phase) with this exact name to run
/// `frame_callbacks` effects.
///
pub const frame_callbacks_phase = "frame_callbacks"

/// The phase name tagged by
/// [`opentui/effect.after_layout`](./opentui/effect.html#after_layout) and
/// declared by the OpenTUI platform. Public so custom platforms can declare a
/// [`Phase`](../platform.html#Phase) with this exact name to run
/// `after_layout` effects.
///
pub const after_layout_phase = "after_layout"

/// The phase name tagged by
/// [`opentui/effect.after_flush`](./opentui/effect.html#after_flush) and
/// declared by the OpenTUI platform. Public so custom platforms can declare a
/// [`Phase`](../platform.html#Phase) with this exact name to run `after_flush`
/// effects.
///
pub const after_flush_phase = "after_flush"

/// Configuration for creating an OpenTUI renderer.
///
pub opaque type Config {
  Config(
    // Upstream OpenTUI options
    exit_on_ctrl_c: Option(Bool),
    exit_signals: Option(List(String)),
    screen_mode: Option(ScreenMode),
    use_mouse: Option(Bool),
    target_fps: Option(Int),
    max_fps: Option(Int),
    debounce_delay: Option(Int),
    auto_focus: Option(Bool),
    enable_mouse_movement: Option(Bool),
    background_color: Option(String),
    console_mode: Option(ConsoleMode),
    open_console_on_error: Option(Bool),
    kitty_keyboard: Option(KittyConfig),
    gather_stats: Option(Bool),
    max_stat_samples: Option(Int),
    use_thread: Option(Bool),
    remote: Option(Bool),
    // Platform options
    custom_elements: List(#(String, ElementFactory)),
  )
}

// BUILDERS --------------------------------------------------------------------

/// Set whether Ctrl+C exits the application.
///
pub fn exit_on_ctrl_c(config: Config, value: Bool) -> Config {
  Config(..config, exit_on_ctrl_c: Some(value))
}

/// Set which signals tear the renderer down, replacing OpenTUI's default list.
///
/// This selects *which* signals are handled, not what happens: every listed
/// signal destroys the renderer, including ones that normally mean something
/// other than "quit" — `Sigchld` destroys it whenever a subprocess exits,
/// `Sigwinch` whenever the terminal is resized, `Sigtstp` instead of
/// suspending. Use
/// [`opentui/effect.on_destroy`](./opentui/effect.html#on_destroy) to run your
/// own cleanup when it does.
///
/// Passing an empty list is not "signals are ignored" — it registers no
/// listener at all, so each signal's default disposition applies instead:
/// most terminate the process with no teardown, leaving the terminal in the
/// alternate screen and in raw mode. `on_destroy` does not run on that path.
///
pub fn exit_signals(config: Config, value: List(Signal)) -> Config {
  Config(..config, exit_signals: Some(list.map(value, signal_to_string)))
}

/// Set where the renderer owns terminal space (alternate screen, main screen,
/// or split footer). Not calling this defers to OpenTUI's own default.
///
pub fn screen_mode(config: Config, mode: ScreenMode) -> Config {
  Config(..config, screen_mode: Some(mode))
}

/// Set whether to enable mouse input.
///
pub fn use_mouse(config: Config, value: Bool) -> Config {
  Config(..config, use_mouse: Some(value))
}

/// Set the target frames per second. Rendering is on-demand: this paces the
/// continuous render loop, which only runs while OpenTUI animations are
/// active (`requestAnimationFrame`, timelines). It has no effect at idle or
/// on state-change renders — those are paced by `max_fps`.
///
pub fn target_fps(config: Config, value: Int) -> Config {
  Config(..config, target_fps: Some(value))
}

/// Set the maximum frames per second. This paces on-demand frames — the
/// one-shot renders triggered by state changes — capping how fast bursts of
/// updates repaint.
///
pub fn max_fps(config: Config, value: Int) -> Config {
  Config(..config, max_fps: Some(value))
}

/// Set the debounce delay in milliseconds.
///
pub fn debounce_delay(config: Config, value: Int) -> Config {
  Config(..config, debounce_delay: Some(value))
}

/// Set whether to auto-focus the first focusable element.
///
pub fn auto_focus(config: Config, value: Bool) -> Config {
  Config(..config, auto_focus: Some(value))
}

/// Set whether to enable mouse movement events.
///
pub fn enable_mouse_movement(config: Config, value: Bool) -> Config {
  Config(..config, enable_mouse_movement: Some(value))
}

/// Set the background color.
///
pub fn background_color(config: Config, value: String) -> Config {
  Config(..config, background_color: Some(value))
}

/// Set what the built-in console overlay does. Not calling this defers to
/// OpenTUI's own default.
///
pub fn console_mode(config: Config, mode: ConsoleMode) -> Config {
  Config(..config, console_mode: Some(mode))
}

/// Set whether to open console on error.
///
pub fn open_console_on_error(config: Config, value: Bool) -> Config {
  Config(..config, open_console_on_error: Some(value))
}

/// Set the Kitty keyboard protocol configuration. Pass `KittyOff` to disable
/// it, or a `KittyOn(...)` to enable it and choose which flags apply. Not
/// calling this defers to OpenTUI's own default
///
pub fn with_kitty_keyboard(config: Config, kitty: KittyConfig) -> Config {
  Config(..config, kitty_keyboard: Some(kitty))
}

/// Set whether to gather performance stats.
///
pub fn gather_stats(config: Config, value: Bool) -> Config {
  Config(..config, gather_stats: Some(value))
}

/// Set the maximum number of stat samples to keep.
///
pub fn max_stat_samples(config: Config, value: Int) -> Config {
  Config(..config, max_stat_samples: Some(value))
}

/// Set whether to use a separate thread for rendering.
///
pub fn use_thread(config: Config, value: Bool) -> Config {
  Config(..config, use_thread: Some(value))
}

/// Set whether to enable remote rendering.
///
pub fn remote(config: Config, value: Bool) -> Config {
  Config(..config, remote: Some(value))
}

/// Register a custom element factory for a tag name. Once registered,
/// using `element.element(tag, attrs, children)` with this tag will create
/// a node via the factory instead of falling back to a box container.
///
/// Built-in tags (box, text, input, etc.) cannot be overridden — custom
/// factories are only consulted when no built-in renderable matches.
///
pub fn register_element(
  config: Config,
  tag: String,
  factory: ElementFactory,
) -> Config {
  Config(..config, custom_elements: [#(tag, factory), ..config.custom_elements])
}

// CONSTRUCTORS ----------------------------------------------------------------

/// Create a default configuration for the OpenTUI renderer.
///
pub fn default_config() -> Config {
  Config(
    exit_on_ctrl_c: None,
    exit_signals: None,
    screen_mode: None,
    use_mouse: None,
    target_fps: None,
    max_fps: None,
    debounce_delay: None,
    auto_focus: None,
    enable_mouse_movement: None,
    background_color: None,
    console_mode: None,
    open_console_on_error: None,
    kitty_keyboard: None,
    gather_stats: None,
    max_stat_samples: None,
    use_thread: None,
    remote: None,
    custom_elements: [],
  )
}

@target(javascript)
/// Create an OpenTUI platform. This handles renderer creation internally.
/// The callback receives the ready platform.
///
/// ```gleam
/// pub fn main() {
///   opentui.platform(opentui.default_config(), fn(platform) {
///     let app = agnostic.application(init, update, view)
///     let assert Ok(_) = agnostic.start(app, on: platform, with: Nil)
///     Nil
///   })
/// }
/// ```
///
@external(javascript, "./opentui.ffi.ts", "platform")
pub fn platform(
  config: Config,
  callback: fn(Platform(Node, Renderer, Value, Event, msg, raw)) -> Nil,
) -> Nil
