/// Run `callback` on a later tick and resolve once it has returned. Effects
/// scheduled by the headless runtime are deferred with `queueMicrotask`, so a
/// test that wants to observe them has to yield first.
///
/// The returned promise rejects if `callback` throws, which is what lets
/// gleeunit report the failure against the test that produced it.
export function resolved() {
  return Promise.resolve(undefined);
}

export function next_tick(callback) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      try {
        callback();
        resolve(undefined);
      } catch (error) {
        reject(error);
      }
    }, 0);
  });
}
