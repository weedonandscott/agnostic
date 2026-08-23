// IMPORTS ---------------------------------------------------------------------

import { Runtime } from "./platform/base.ffi.mjs";
import {
  Message$isEffectDispatchedMessage,
  Message$EffectDispatchedMessage$message,
  Message$isEffectEmitEvent,
  Message$EffectEmitEvent$name,
  Message$EffectEmitEvent$data,
  Message$isSystemRequestedShutdown,
} from "./headless.mjs";

//

export class Platform {
  #runtime;

  constructor(root, initialVdom, [init, effects], update, view, platform) {
    this.#runtime = new Runtime(root, initialVdom, [init, effects], view, update, platform);
  }

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
}

export const start = (root, initialVdom, app, platform, flags) => {
  return new Platform(root, initialVdom, app.init(flags), app.update, app.view, platform);
};
