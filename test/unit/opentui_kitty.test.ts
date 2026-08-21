// Test for the `with_kitty_keyboard` / `KittyConfig` sum-type API (see CHANGELOG).
//
// This is a Bun test, run with `bun test test/unit/opentui_kitty.test.ts`. It
// is intentionally NOT part of `gleam test`: it needs `mock.module` to capture
// the options object `create_renderer` hands to `@opentui/core`'s
// `createCliRenderer`, which the Gleam test runner cannot express. It drives
// the real built Gleam API (`default_config` -> `with_kitty_keyboard` ->
// `platform`), so it exercises `opentui.ffi.ts:create_renderer` for real; it
// only stubs the renderer factory. Requires `gleam build --target javascript`
// to have populated build/ first.

import { test, expect, mock } from "bun:test";
import { buildKittyKeyboardFlags } from "@opentui/core";
import * as realCore from "@opentui/core";

// --- Part 1: pin the upstream flag arithmetic (@opentui/core 0.5.6).
//
// buildKittyKeyboardFlags turns disambiguate + alternateKeys ON unless each is
// explicitly `false`, so `{}` and `{true,true}` both yield 5, and only an
// explicit all-`false` object yields 0 — which is why `KittyOff` must emit that
// object rather than leave the option unset (OpenTUI reads
// `config.useKittyKeyboard ?? {}`). The `events:true` case adds a distinct bit,
// proving the previously-unreachable flags now round-trip.
test("buildKittyKeyboardFlags: off=0, defaults=5, events adds a distinct bit", () => {
  expect(
    buildKittyKeyboardFlags({
      disambiguate: false,
      alternateKeys: false,
      events: false,
      allKeysAsEscapes: false,
      reportText: false,
    }),
  ).toBe(0);
  expect(buildKittyKeyboardFlags({})).toBe(5);
  expect(buildKittyKeyboardFlags({ disambiguate: true, alternateKeys: true })).toBe(5);
  expect(
    buildKittyKeyboardFlags({ disambiguate: true, alternateKeys: true, events: true }),
  ).toBe(7);
});

// --- Part 2: capture the opts create_renderer passes to createCliRenderer.
let captured: { useKittyKeyboard?: unknown } | null = null;
mock.module("@opentui/core", () => ({
  ...realCore,
  createCliRenderer: (opts: { useKittyKeyboard?: unknown }) => {
    captured = opts;
    // Never resolve: platform()'s `.then` needs a live renderer and must not
    // run. `opts` is already captured synchronously above.
    return new Promise(() => {});
  },
}));

const opentui: {
  default_config: () => unknown;
  with_kitty_keyboard: (config: unknown, kitty: unknown) => unknown;
  KittyOff: new () => unknown;
  KittyOn: new (
    disambiguate: boolean,
    alternate_keys: boolean,
    events: boolean,
    all_keys_as_escapes: boolean,
    report_text: boolean,
  ) => unknown;
  platform: (config: unknown, callback: (p: unknown) => void) => void;
} = await import(
  "../../build/dev/javascript/agnostic/agnostic/platform/opentui.mjs"
);

function optsFor(kitty: unknown): { useKittyKeyboard?: unknown } {
  captured = null;
  const config = opentui.with_kitty_keyboard(opentui.default_config(), kitty);
  opentui.platform(config, () => {});
  if (!captured) throw new Error("createCliRenderer was not called");
  return captured;
}

// The default config, with with_kitty_keyboard never called (kitty stays None).
function defaultOpts(): { useKittyKeyboard?: unknown } {
  captured = null;
  opentui.platform(opentui.default_config(), () => {});
  if (!captured) throw new Error("createCliRenderer was not called");
  return captured;
}

test("default_config (None) leaves useKittyKeyboard unset — defers to OpenTUI", () => {
  const opts = defaultOpts();
  // The key is never written, so OpenTUI's own `?? {}` default applies at
  // runtime. We assert absence, not a value: nothing here hardcodes OpenTUI's
  // current default, so it can't drift out of sync with it.
  expect("useKittyKeyboard" in opts).toBe(false);
  expect(opts.useKittyKeyboard).toBeUndefined();
  // For reference, that absent-config path is what OpenTUI turns into flags 5.
  expect(buildKittyKeyboardFlags(opts.useKittyKeyboard ?? {})).toBe(5);
});

test("KittyOff emits an all-false object; buildKittyKeyboardFlags -> 0", () => {
  const opts = optsFor(new opentui.KittyOff());
  expect(opts.useKittyKeyboard).toEqual({
    disambiguate: false,
    alternateKeys: false,
    events: false,
    allKeysAsEscapes: false,
    reportText: false,
  });
  // Same `?? {}` OpenTUI applies: still 0, i.e. actively disabled.
  expect(buildKittyKeyboardFlags(opts.useKittyKeyboard ?? {})).toBe(0);
});

test("KittyOn(true, true, false, false, false) round-trips to flags 5", () => {
  const opts = optsFor(new opentui.KittyOn(true, true, false, false, false));
  expect(opts.useKittyKeyboard).toEqual({
    disambiguate: true,
    alternateKeys: true,
    events: false,
    allKeysAsEscapes: false,
    reportText: false,
  });
  expect(buildKittyKeyboardFlags(opts.useKittyKeyboard ?? {})).toBe(5);
});

test("KittyOn(events: true) reaches opts and flags — a flag unreachable before", () => {
  const opts = optsFor(new opentui.KittyOn(true, true, true, false, false));
  expect(opts.useKittyKeyboard).toEqual({
    disambiguate: true,
    alternateKeys: true,
    events: true,
    allKeysAsEscapes: false,
    reportText: false,
  });
  // 5 (defaults) + the events bit -> 7. Proves the new expressiveness makes it
  // all the way through create_renderer and buildKittyKeyboardFlags.
  expect(buildKittyKeyboardFlags(opts.useKittyKeyboard ?? {})).toBe(7);
});
