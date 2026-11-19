import test from "node:test";
import assert from "node:assert/strict";
import { stoppedConnect } from "./lib/stopped-connect.mjs";

for (const stage of ["descriptor", "session", "ticket", "socket", "shell"]) {
  test(`connection: stop during ${stage} leaves no socket or subscriptions`, async () => {
    const state = await stoppedConnect(stage);
    assert.equal(state.openSockets, 0, "no socket stays open after stop");
    assert.equal(state.subscriptions, 0, "no subscriptions remain after stop");
    assert.equal(state.subscriptionRequests, 0, "no subscriptions start after stop");
    assert.equal(state.polling, false, "no polling timer starts after stop");
    if (stage !== "shell") {
      const stages = ["descriptor", "session", "ticket", "socket"];
      assert.deepEqual(state.requests, stages.slice(0, Math.min(stages.indexOf(stage) + 1, 3)));
    }
  });
}

test("connection: a handshake failure after stop does not start HTTP fallback", async () => {
  const state = await stoppedConnect("socket", true);
  assert.equal(state.polling, false);
  assert.deepEqual(state.requests, ["descriptor", "session", "ticket"]);
});
