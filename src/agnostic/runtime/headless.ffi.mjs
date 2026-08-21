import {
  Result$Ok,
  Result$Ok$0,
  Result$isOk,
  List$NonEmpty$rest,
  List$NonEmpty$first,
} from "../../gleam.mjs";
import * as Decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as Dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as Option from "../../../gleam_stdlib/gleam/option.mjs";
import * as Diff from "../vdom/diff.mjs";
import * as Cache from "../vdom/cache.mjs";
import { isEqual } from "../internals/equals.ffi.mjs";
import {
  Message$isClientDispatchedMessage,
  Message$ClientDispatchedMessage$message,
  Message$isClientRegisteredCallback,
  Message$ClientRegisteredCallback$callback,
  Message$isClientDeregisteredCallback,
  Message$ClientDeregisteredCallback$callback,
  //
  Message$EffectDispatchedMessage,
  Message$isEffectDispatchedMessage,
  Message$EffectDispatchedMessage$message,
  Message$EffectEmitEvent,
  Message$isEffectEmitEvent,
  Message$EffectEmitEvent$name,
  Message$EffectEmitEvent$data,
  Message$EffectProvidedValue,
  Message$isEffectProvidedValue,
  Message$EffectProvidedValue$key,
  Message$EffectProvidedValue$value,
  Message$EffectRequestedContextSubscription,
  Message$isEffectRequestedContextSubscription,
  Message$EffectRequestedContextSubscription$key,
  Message$EffectRequestedContextSubscription$decoder,
  Message$EffectRemovedContextSubscription,
  Message$isEffectRemovedContextSubscription,
  Message$EffectRemovedContextSubscription$key,
  //
  Message$isSystemRequestedShutdown,
} from "./headless.mjs";
import * as Component from "../component.mjs";
import * as Effect from "../effect.mjs";
import * as Transport from "./transport.mjs";
import {
  ServerMessage$isBatch,
  ServerMessage$Batch$messages,
  ServerMessage$isAttributeChanged,
  ServerMessage$AttributeChanged$name,
  ServerMessage$AttributeChanged$value,
  ServerMessage$isPropertyChanged,
  ServerMessage$PropertyChanged$name,
  ServerMessage$PropertyChanged$value,
  ServerMessage$isEventFired,
  ServerMessage$EventFired$path,
  ServerMessage$EventFired$name,
  ServerMessage$EventFired$event,
  ServerMessage$isContextProvided,
  ServerMessage$ContextProvided$key,
  ServerMessage$ContextProvided$value,
} from "./transport.mjs";
import { Handler$Handler$message } from "../vdom/vattr.mjs";

//

export class Runtime {
  #model;
  #update;
  #view;
  #config;

  #vdom;
  #cache;
  #providers = Dict.new$();

  #callbacks = /* @__PURE__ */ new Set();

  constructor(_, init, update, view, config, start_arguments) {
    const [model, effects] = init(start_arguments);
    this.#model = model;
    this.#update = update;
    this.#view = view;
    this.#config = config;

    this.#vdom = this.#view(this.#model);
    this.#cache = Cache.from_node(this.#vdom);

    this.#handle_effect(effects);
  }

  send(message) {
    if (Message$isClientDispatchedMessage(message)) {
      const client_message = Message$ClientDispatchedMessage$message(message);
      const next = this.#handle_client_message(client_message);
      const diff = Diff.diff(this.#cache, this.#vdom, next);

      this.#vdom = next;
      this.#cache = diff.cache;

      this.broadcast(Transport.reconcile(diff.patch, Cache.memos(diff.cache)));
    } else if (Message$isClientRegisteredCallback(message)) {
      const callback = Message$ClientRegisteredCallback$callback(message);
      this.#callbacks.add(callback);

      callback(
        Transport.mount(
          this.#config.open_shadow_root,
          this.#config.adopt_styles,
          Dict.keys(this.#config.attributes),
          Dict.keys(this.#config.properties),
          Dict.keys(this.#config.contexts),
          this.#providers,
          this.#vdom,
          Cache.memos(this.#cache),
        ),
      );

      if (Option.Option$isSome(this.#config.on_connect)) {
        this.#dispatch(Option.Option$Some$0(this.#config.on_connect));
      }
    } else if (Message$isClientDeregisteredCallback(message)) {
      const callback = Message$ClientDeregisteredCallback$callback(message);
      this.#callbacks.delete(callback);

      if (Option.Option$isSome(this.#config.on_disconnect)) {
        this.#dispatch(Option.Option$Some$0(this.#config.on_disconnect));
      }
    } else if (Message$isEffectDispatchedMessage(message)) {
      const dispatched_message = Message$EffectDispatchedMessage$message(message);
      const [model, effect] = this.#update(this.#model, dispatched_message);
      const next = this.#view(model);
      const diff = Diff.diff(this.#cache, this.#vdom, next);

      this.#handle_effect(effect);

      this.#model = model;
      this.#vdom = next;
      this.#cache = diff.cache;

      this.broadcast(Transport.reconcile(diff.patch, Cache.memos(diff.cache)));
    } else if (Message$isEffectEmitEvent(message)) {
      const name = Message$EffectEmitEvent$name(message);
      const data = Message$EffectEmitEvent$data(message);

      this.broadcast(Transport.emit(name, data));
    } else if (Message$isEffectProvidedValue(message)) {
      const key = Message$EffectProvidedValue$key(message);
      const value = Message$EffectProvidedValue$value(message);
      const existing = Dict.get(this.#providers, key);
      // we do not need to broadcast an update if the provided value is the same.
      if (Result$isOk(existing) && isEqual(Result$Ok$0(existing), value)) {
        return undefined;
      }

      this.#providers = Dict.insert(this.#providers, key, value);
      this.broadcast(Transport.provide(key, value));
    } else if (Message$isEffectRequestedContextSubscription(message)) {
      const key = Message$EffectRequestedContextSubscription$key(message);
      const decoder = Message$EffectRequestedContextSubscription$decoder(message);

      this.broadcast(Transport.subscribe(key));
      this.#config.contexts = Dict.insert(this.#config.contexts, key, decoder);
    } else if (Message$isEffectRemovedContextSubscription(message)) {
      const key = Message$EffectRemovedContextSubscription$key(message);

      this.broadcast(Transport.unsubscribe(key));
      this.#config.contexts = Dict.delete$(this.#config.contexts, key);
    } else if (Message$isSystemRequestedShutdown(message)) {
      // Every field below is typed by its live value; after a shutdown the
      // runtime is inert and nothing reads them again, so the nulling is
      // deliberately outside the declared shape.
      const dead = /** @type {any} */ (null);

      this.#model = dead;
      this.#update = dead;
      this.#view = dead;
      this.#config = dead;
      this.#vdom = dead;
      this.#cache = dead;
      this.#providers = dead;
      this.#callbacks.clear();
    }

    return undefined;
  }

  broadcast(message) {
    for (const callback of this.#callbacks) {
      callback(message);
    }
  }

  // `vdom` is the fold's accumulator, matching the Erlang runtime's `state`
  // (headless.gleam: `list.fold(messages, state, handle_client_message)`). It
  // has to be threaded rather than read from `this.#vdom`, because `send()`
  // only writes `this.#vdom` once the whole batch has been handled: a nested
  // message that fails must return what the *previous* nested message
  // produced, not the pre-batch vdom. Top-level calls start from `this.#vdom`,
  // which is the same thing when the batch is empty.
  #handle_client_message(message, vdom = this.#vdom) {
    if (ServerMessage$isBatch(message)) {
      const messages = ServerMessage$Batch$messages(message);
      // Each nested call already updates `this.#model` and `this.#cache` and
      // schedules its own effects, so the vdom is all this branch threads.
      for (
        let list = messages, tail = List$NonEmpty$rest(list);
        tail !== undefined;
        list = tail, tail = List$NonEmpty$rest(list)
      ) {
        vdom = this.#handle_client_message(List$NonEmpty$first(list), vdom);
      }

      return vdom;
    } else if (ServerMessage$isAttributeChanged(message)) {
      const name = ServerMessage$AttributeChanged$name(message);
      const value = ServerMessage$AttributeChanged$value(message);
      const result = this.#handle_attribute_change(name, value);
      if (!Result$isOk(result)) {
        return vdom;
      }

      return this.#dispatch(Result$Ok$0(result));
    } else if (ServerMessage$isPropertyChanged(message)) {
      const name = ServerMessage$PropertyChanged$name(message);
      const value = ServerMessage$PropertyChanged$value(message);
      const result = this.#handle_properties_change(name, value);
      if (!Result$isOk(result)) {
        return vdom;
      }

      return this.#dispatch(Result$Ok$0(result));
    } else if (ServerMessage$isEventFired(message)) {
      const path = ServerMessage$EventFired$path(message);
      const name = ServerMessage$EventFired$name(message);
      const event = ServerMessage$EventFired$event(message);
      const [cache, result] = Cache.handle(this.#cache, path, name, event);

      this.#cache = cache;
      if (!Result$isOk(result)) {
        return vdom;
      }

      // `Result$isOk` narrows to `Result<unknown, unknown>` and `Result$Ok$0`
      // is typed `T | undefined`, so the payload type has to be restored by
      // hand after the guard above.
      const handler = /** @type {import("../vdom/vattr.mjs").Handler$<any>} */ (
        Result$Ok$0(result)
      );

      return this.#dispatch(Handler$Handler$message(handler));
    } else if (ServerMessage$isContextProvided(message)) {
      const key = ServerMessage$ContextProvided$key(message);
      const value = ServerMessage$ContextProvided$value(message);
      let result = Dict.get(this.#config.contexts, key);
      if (!Result$isOk(result)) {
        return vdom;
      }

      result = Decode.run(value, Result$Ok$0(result));
      if (!Result$isOk(result)) {
        return vdom;
      }

      return this.#dispatch(Result$Ok$0(result));
    }
  }

  #dispatch(message) {
    const [model, effects] = this.#update(this.#model, message);
    this.#handle_effect(effects);
    this.#model = model;

    return this.#view(this.#model);
  }

  #handle_attribute_change(name, value) {
    const result = Dict.get(this.#config.attributes, name);
    if (!Result$isOk(result)) {
      return result;
    }

    return Result$Ok$0(result)(value);
  }

  #handle_properties_change(name, value) {
    const result = Dict.get(this.#config.properties, name);
    if (!Result$isOk(result)) {
      return result;
    }

    return Result$Ok$0(result)(value);
  }

  #handle_effect(effect) {
    const dispatch = (message) =>
      this.send(Message$EffectDispatchedMessage(message));
    const emit = (name, data) => this.send(Message$EffectEmitEvent(name, data));
    const select = () => undefined;
    const internals = () => undefined;
    const provide = (key, value) =>
      this.send(Message$EffectProvidedValue(key, value));
    const subscribe = (key, decoder) => 
      this.send(Message$EffectRequestedContextSubscription(key, decoder));
    const unsubscribe = (key) => 
      this.send(Message$EffectRemovedContextSubscription(key));

    globalThis.queueMicrotask(() => {
      Effect.perform(effect, 
        dispatch, 
        emit, 
        select, 
        internals, 
        provide, 
        subscribe, 
        unsubscribe
      );
    });
  }
}

export const start = (app, start_arguments) => {
  const config = Component.to_server_component_config(app.config);

  // The constructor's first parameter is the (unused) app name, mirroring the
  // Erlang runtime's start signature.
  return Result$Ok(
    new Runtime(app.name, app.init, app.update, app.view, config, start_arguments),
  );
};

export const send = (runtime, message) => {
  runtime.send(message);
};
