// IMPORTS ---------------------------------------------------------------------

import { virtualise } from "../vdom/virtualise.ffi.mjs";
import {
  NAMESPACE_HTML,
  SUPPORTS_MOVE_BEFORE,
} from "../internals/constants.ffi.mjs";
import {
  Result$Ok,
  Result$Error,
  Result$isOk,
  Result$Ok$0,
} from "../../gleam.mjs";
import { new$ as newPlatform, Phase$Phase } from "../platform.mjs";
import { toList } from "../internals/list.ffi.mjs";
// Own compiled module: single source of truth for the DOM phase names. This is
// an ES-module cycle (dom.mjs imports dom.ffi.mjs for its externals), which is
// safe because the constants are only referenced lazily — inside phases(),
// called from dom_strict at platform-construction time — never in a top-level
// initializer, where they could hit the temporal dead zone.
import { before_paint_phase, after_paint_phase } from "./dom.mjs";

// TYPES -----------------------------------------------------------------------

// The platform contract's node-reference slot: Gleam's `Result(node, Nil)`.
/** @typedef {import("../../gleam.mjs").Result<Node, undefined>} NodeRef */

// The platform contract's `raw` slot. Gleam's `RawContent` is an erased
// external type, so the generated `.d.mts` spells it `any` — and it has to be,
// because the DOM platform stores an HTML string for a raw *container* and a
// live node for a raw *node*. Neither annotation would fit both slots.
/** @typedef {import("../vdom/vnode.mjs").RawContent$} RawContent */

// Helpers to convert between Gleam Result and nullable. `Result$isOk` narrows
// its argument to `Result<unknown, unknown>`, so `Result$Ok$0` comes back as
// `unknown` and the node type has to be restored on the way out.
const unwrapResult = (/** @type {NodeRef} */ result) =>
  Result$isOk(result) ? /** @type {Node} */ (Result$Ok$0(result)) : null;
const wrapResult = (value) =>
  value != null ? Result$Ok(value) : Result$Error(undefined);

// MOUNT -----------------------------------------------------------------------

// Returns Result(DomNode, String) — Error carries the selector string so Gleam
// can wrap it in PlatformError.ElementNotFound.
export const query_selector = (selector) => {
  const root = globalThis.document.querySelector(selector);
  if (!root) return Result$Error(selector);
  return Result$Ok(root);
};

// Takes a known-good node and virtualises it. No Result — always succeeds.
export const mount_strict = (/** @type {Node} */ root) => {
  const initialVdom = virtualise(root);

  // Gleam expects the pair `#(root, initial_vdom)`; an array literal widens to
  // `any[]` without this. The first element must be spelled `Node` rather than
  // `any`: it is one of the inference sites for the platform's node type, and
  // an `any` there would collapse the whole record's node slot back to `any`.
  return /** @type {[Node, import("../vdom/vnode.mjs").Element$<any>]} */ ([
    root,
    initialVdom,
  ]);
};

// Legacy mount — kept for compatibility but no longer used by platform.dom().
export const mount = (target) => {
  const root =
    target instanceof HTMLElement
      ? target
      : globalThis.document.querySelector(target);
  if (!root) return Result$Error(target);
  const initialVdom = virtualise(root);
  return Result$Ok([root, initialVdom]);
};

// NODE CREATION ---------------------------------------------------------------

export const create_element = (
  /** @type {string} */ ns,
  /** @type {string} */ tag,
) => globalThis.document.createElementNS(ns || NAMESPACE_HTML, tag);

export const create_text_node = (/** @type {string} */ content) =>
  globalThis.document.createTextNode(content ?? "");

export const create_fragment = () => globalThis.document.createDocumentFragment();

export const create_comment = (/** @type {string} */ data) =>
  globalThis.document.createComment(data);

// TREE MANIPULATION -----------------------------------------------------------

// NOTE: the explicit `return undefined` on every `Nil`-returning function from
// here down is not decoration. Gleam's `Nil` is `undefined`, and a JavaScript
// function that falls off its end has return type `void`, which is not
// assignable to `undefined` — the platform record would silently take an `any`
// instead. The same goes for the parameter annotations: without them every
// function here is `(...args: any[]) => X`, assignable to *any* slot of the
// record, and `newPlatform` below stops checking anything.
export const insert_before = (
  /** @type {Node} */ parent,
  /** @type {Node} */ node,
  /** @type {NodeRef} */ ref,
) => {
  parent.insertBefore(node, unwrapResult(ref));

  return undefined;
};

export const move_before = SUPPORTS_MOVE_BEFORE
  ? (
      /** @type {Node} */ parent,
      /** @type {Node} */ node,
      /** @type {NodeRef} */ ref,
    ) => {
      // `moveBefore` is declared on `ParentNode`, not on `Node`; the runtime
      // guard above is what actually establishes it is there.
      /** @type {ParentNode} */ (parent).moveBefore(node, unwrapResult(ref));

      return undefined;
    }
  : (
      /** @type {Node} */ parent,
      /** @type {Node} */ node,
      /** @type {NodeRef} */ ref,
    ) => {
      parent.insertBefore(node, unwrapResult(ref));

      return undefined;
    };

export const remove_child = (
  /** @type {Node} */ parent,
  /** @type {Node} */ child,
) => {
  parent.removeChild(child);

  return undefined;
};

export const next_sibling = (/** @type {Node} */ node) => {
  const sibling = node.nextSibling;
  return sibling ? Result$Ok(sibling) : Result$Error(undefined);
};

// ATTRIBUTES ------------------------------------------------------------------

// The contract's node type is uniform, so these arrive typed as `Node` and the
// attribute APIs — which live on `Element` — have to be reached through a cast.
export const get_attribute = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
) => wrapResult(/** @type {Element} */ (node).getAttribute(name));

export const set_attribute = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
  /** @type {string} */ value,
) => {
  /** @type {Element} */ (node).setAttribute(name, value ?? "");

  return undefined;
};

export const remove_attribute = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
) => {
  /** @type {Element} */ (node).removeAttribute(name);

  return undefined;
};

export const set_property = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
  /** @type {unknown} */ value,
) => {
  node[name] = value;

  return undefined;
};

// CONTENT ---------------------------------------------------------------------

export const set_text = (
  /** @type {Node} */ node,
  /** @type {string} */ content,
) => {
  /** @type {CharacterData} */ (node).data = content ?? "";

  return undefined;
};

export const set_raw_content = (
  /** @type {Node} */ node,
  /** @type {RawContent} */ content,
) => {
  /** @type {Element} */ (node).innerHTML = content ?? "";

  return undefined;
};

// `RawContent` is erased to `any`, so the identity has to be re-narrowed on the
// way out: an `any` here is a covariant inference site for the record's node
// type and would collapse it.
export const create_raw_node = (/** @type {RawContent} */ content) =>
  /** @type {Node} */ (content);

// EVENTS ----------------------------------------------------------------------

export const add_event_listener = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
  /** @type {(event: Event) => undefined} */ handler,
  /** @type {boolean} */ passive,
) => {
  node.addEventListener(name, handler, { passive });

  return undefined;
};

export const remove_event_listener = (
  /** @type {Node} */ node,
  /** @type {string} */ name,
  /** @type {(event: Event) => undefined} */ handler,
) => {
  node.removeEventListener(name, handler);

  return undefined;
};

// SCHEDULING ------------------------------------------------------------------

export const schedule_render = (/** @type {() => undefined} */ callback) => {
  const id = window.requestAnimationFrame(callback);

  return () => {
    window.cancelAnimationFrame(id);

    return undefined;
  };
};

export const after_render = () => undefined;

// EFFECT PHASES ---------------------------------------------------------------

const schedule_before_paint = (/** @type {() => undefined} */ callback) => {
  // Upstream-exact: a microtask after the render pass blocks the browser from
  // painting until the phase's effects (and any second render they dispatch)
  // have run. We explicitly queue a microtask instead of synchronously calling
  // the callback to allow the runtime to process any microtasks queued by
  // synchronous effects first, such as promise callbacks.
  queueMicrotask(callback);

  // Gleam's `Nil` is `undefined`, and `void` is not assignable to it.
  return undefined;
};

const schedule_after_paint = (/** @type {() => undefined} */ callback) => {
  // Upstream-exact: rAF requested from within the render pass; fires after the
  // browser paints. Deliberately window.requestAnimationFrame directly — not
  // schedule_render — matching upstream (no cancel handle).
  window.requestAnimationFrame(callback);

  // Gleam's `Nil` is `undefined`, and `void` is not assignable to it.
  return undefined;
};

// Declaration order [before_paint, after_paint] + the runtime's in-order
// scheduler invocation reproduces upstream's drain order: microtasks precede
// rAF/paint, so before_paint effects always run before after_paint effects
// from the same render.
const phases = () =>
  toList([
    Phase$Phase(before_paint_phase, schedule_before_paint),
    Phase$Phase(after_paint_phase, schedule_after_paint),
  ]);

// PLATFORM CONSTRUCTOR --------------------------------------------------------

// Returns a complete Platform record configured for the browser DOM.
// This is called from dom.gleam's dom_strict function.
export const dom_strict = (/** @type {Node} */ root) => {
  return newPlatform(
    root,
    mount_strict,
    create_element,
    create_text_node,
    create_fragment,
    create_comment,
    insert_before,
    move_before,
    remove_child,
    next_sibling,
    get_attribute,
    set_attribute,
    remove_attribute,
    set_property,
    set_text,
    set_raw_content,
    create_raw_node,
    add_event_listener,
    remove_event_listener,
    schedule_render,
    after_render,
    phases(),
  );
};
