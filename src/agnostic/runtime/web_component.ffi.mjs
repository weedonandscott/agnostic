// IMPORTS ---------------------------------------------------------------------

import {
  Result$Ok,
  Result$Error,
  Result$isOk,
  Result$Ok$0,
} from "../../gleam.mjs";
import { run as decode } from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import {
  Option$isSome,
  Option$Some$0,
} from "../../../gleam_stdlib/gleam/option.mjs";
import { filter } from "../../../gleam_stdlib/gleam/list.mjs";

import {
  Error$BadComponentName,
  Error$ComponentAlreadyRegistered,
  Error$NotABrowser,
} from "../../agnostic.mjs";
import {
  Runtime,
  ContextRequestEvent,
  adoptStylesheets,
  is_browser,
} from "./platform/base.ffi.mjs";
import {
  Message$isEffectDispatchedMessage,
  Message$EffectDispatchedMessage$message,
  Message$isEffectEmitEvent,
  Message$EffectEmitEvent$name,
  Message$EffectEmitEvent$data,
  Message$isSystemRequestedShutdown,
} from "./headless.mjs";
import { iterate } from "../internals/list.ffi.mjs";

//

export const make_component = (app, make_platform, name) => {
  if (!is_browser()) return Result$Error(Error$NotABrowser());
  if (!name.includes("-")) return Result$Error(Error$BadComponentName(name));
  if (globalThis.customElements.get(name)) {
    return Result$Error(Error$ComponentAlreadyRegistered(name));
  }

  const { init, update, view, config } = app;

  const attributes = new Map();
  const observedAttributes = [];
  iterate(config.attributes, ([name, decoder]) => {
    if (attributes.has(name)) return;

    attributes.set(name, decoder);
    observedAttributes.push(name);
  });

  const [model, effects] = init(undefined);

  const component = class Component extends globalThis.HTMLElement {
    static get observedAttributes() {
      return observedAttributes;
    }

    static formAssociated = config.is_form_associated;

    #runtime;
    #adoptedStyleNodes = [];
    #initialContexts = config.contexts;

    constructor() {
      super();

      // There are talks of potentially having `attachInternals` set `.internals`
      // automatically in the future.
      this.internals = this.attachInternals();

      // Only attach a shadow root if we don't already have one from the declarative
      // shadow DOM. This means components can be SSR'd and then hydrated like
      // normal apps.
      if (!this.internals.shadowRoot) {
        this.attachShadow({
          mode: config.open_shadow_root ? "open" : "closed",
          delegatesFocus: config.delegates_focus,
        });
      }

      if (config.adopt_styles) {
        this.#adoptStyleSheets();
      }

      const platform = make_platform(this.internals.shadowRoot);
      const [root, initialVdom] = platform.mount(this.internals.shadowRoot);
      this.#runtime = new Runtime(
        root,
        initialVdom,
        [model, effects],
        view,
        update,
        platform,
      );
    }

    // CUSTOM ELEMENT LIFECYCLE METHODS ----------------------------------------

    // When an element is constructed by `document.createElement` and then added
    // to the DOM, the lifecycle callbacks run in this order:
    //
    //   constructor -> attributeChangedCallback -> connectedCallback
    //
    // If the element is added to the document through `document.importNode` then
    // we get:
    //
    //   constructor -> connectedCallback
    //
    // The connectedCallback is also called when the element is moved to a new
    // position in the same document, so it's important we don't do any *one-time*
    // work here.
    //
    connectedCallback() {
      this.#requestContexts();

      if (Option$isSome(config.on_connect)) {
        this.dispatch(Option$Some$0(config.on_connect));
      }
    }

    // If the element is imported into the document through `document.adoptNode`
    // then the lifecycle callbacks are:
    //
    //   disconnectedCallback -> adoptedCallback -> connectedCallback
    //
    adoptedCallback() {
      if (config.adopt_styles) {
        this.#adoptStyleSheets();
      }

      this.#unsubscribeContexts();

      if (Option$isSome(config.on_adopt)) {
        this.dispatch(Option$Some$0(config.on_adopt));
      }
    }

    // The disconnected callback is also called when the element is disconnected
    // from the document even if it is reconnected somewhere else. It's important
    // we use this callback just for DOM-related cleanup.
    //
    disconnectedCallback() {
      this.#unsubscribeContexts();

      if (Option$isSome(config.on_disconnect)) {
        this.dispatch(Option$Some$0(config.on_disconnect));
      }
    }

    attributeChangedCallback(name, _, value) {
      const decoded = attributes.get(name)(value ?? "");

      if (Result$isOk(decoded)) {
        this.dispatch(Result$Ok$0(decoded), true);
      }
    }

    formResetCallback() {
      if (Option$isSome(config.on_form_reset)) {
        this.dispatch(Option$Some$0(config.on_form_reset));
      }
    }

    formStateRestoreCallback(state, reason) {
      switch (reason) {
        case "restore":
          if (Option$isSome(config.on_form_restore)) {
            this.dispatch(Option$Some$0(config.on_form_restore)(state));
          }
          break;

        case "autocomplete":
          if (Option$isSome(config.on_form_autofill)) {
            this.dispatch(Option$Some$0(config.on_form_autofill)(state));
          }
          break;
      }
    }

    formDisabledCallback(disabled) {
      if (Option$isSome(config.on_form_disabled)) {
        this.dispatch(Option$Some$0(config.on_form_disabled)(disabled));
      }
    }

    // LUSTRE RUNTIME METHODS --------------------------------------------------

    send(message) {
      if (Message$isEffectDispatchedMessage(message)) {
        this.dispatch(Message$EffectDispatchedMessage$message(message), false);
      } else if (Message$isEffectEmitEvent(message)) {
        this.emit(
          Message$EffectEmitEvent$name(message),
          Message$EffectEmitEvent$data(message),
        );
      } else if (Message$isSystemRequestedShutdown(message)) {
        // TODO
      }
    }

    dispatch(message, shouldFlush = false) {
      this.#runtime.dispatch(message, shouldFlush);
    }

    emit(event, data) {
      this.#runtime.emit(event, data);
    }

    provide(key, value) {
      this.#runtime.provide(key, value);
    }

    subscribe(key, decoder) {
      this.#runtime.subscribe(key, decoder);
    }

    unsubscribe(key) {
      this.#runtime.unsubscribe(key);
      // Once a component is running and has a context subscription torn down, we
      // don't want it to start back up again if the component is disconnected but
      // later reconnected to the DOM.
      //
      // In future versions of Lustre the static `on_context_change` option will
      // go awawy in favour of the uniform `effect.subscribe` and then we won't
      // need this.
      this.#initialContexts = filter(this.#initialContexts, (subscription) => {
        return subscription[0] !== key;
      });
    }

    // INTERNAL METHODS --------------------------------------------------------

    #requestContexts() {
      const requested = new Set();

      iterate(this.#initialContexts, ([key, decoder]) => {
        // An empty key is not valid so we skip over any of those.
        if (!key) return;

        // Likewise if we've requested a context for this key already then we
        // don't want to dispatch a second event, even if the user provided a
        // different decoder.
        if (requested.has(key)) return;

        this.#runtime.subscribe(key, decoder);
        requested.add(key);
      });
    }

    #unsubscribeContexts() {
      this.#runtime.unsubscribeAll();
    }

    async #adoptStyleSheets() {
      // `internals.shadowRoot` rather than `this.shadowRoot`: the latter is
      // `null` whenever `open_shadow_root` is `False`. The constructor always
      // leaves a shadow root attached — inherited from declarative shadow DOM
      // or attached here — so the `null` in the `lib.dom` type is unreachable.
      const shadowRoot = /** @type {ShadowRoot} */ (this.internals.shadowRoot);

      // `adoptStylesheets` prepends each clone and returns those same nodes, so
      // removing the popped node is the whole job. This loop used to also
      // remove `firstChild` on every iteration, which took out a second,
      // unrelated node — app content, once the style clones ran out.
      while (this.#adoptedStyleNodes.length) {
        this.#adoptedStyleNodes.pop().remove();
      }

      this.#adoptedStyleNodes = await adoptStylesheets(shadowRoot);
    }
  };

  iterate(config.properties, ([name, decoder]) => {
    if (Object.hasOwn(component.prototype, name)) {
      return;
    }

    Object.defineProperty(component.prototype, name, {
      get() {
        return this[`_${name}`];
      },

      set(value) {
        this[`_${name}`] = value;
        const decoded = decode(value, decoder);

        if (Result$isOk(decoded)) {
          this.dispatch(Result$Ok$0(decoded), true);
        }
      },
    });
  });

  globalThis.customElements.define(name, component);

  return Result$Ok(undefined);
};

//

/**
 * The host of a shadow root reached by the four helpers below is always the
 * `Component` class defined in `make_component` above, which assigns
 * `internals` in its constructor. That class is built at runtime, so `lib.dom`
 * only knows the host as a plain `Element` and the property has to be spelled
 * out here.
 *
 * @param {ShadowRoot} root
 * @returns {ElementInternals}
 */
const hostInternals = (root) =>
  /** @type {Element & { internals: ElementInternals }} */ (root.host).internals;

export const set_form_value = (root, value) => {
  if (!is_browser()) return;
  if (root instanceof ShadowRoot) {
    hostInternals(root).setFormValue(value);
  }
};

export const clear_form_value = (root) => {
  if (!is_browser()) return;
  if (root instanceof ShadowRoot) {
    // `null` rather than `undefined`: `setFormValue` takes a nullable union, so
    // WebIDL coerces both to the same thing, but only `null` is in the type.
    hostInternals(root).setFormValue(null);
  }
};

export const set_pseudo_state = (root, value) => {
  if (!is_browser()) return;
  if (root instanceof ShadowRoot) {
    hostInternals(root).states.add(value);
  }
};

export const remove_pseudo_state = (root, value) => {
  if (!is_browser()) return;
  if (root instanceof ShadowRoot) {
    hostInternals(root).states.delete(value);
  }
};
