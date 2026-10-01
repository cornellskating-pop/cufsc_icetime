import { test } from "node:test";
import assert from "node:assert/strict";
import { canSelectSession, selectionCost } from "../lib/bookingSelection.ts";
const now = Date.parse("2026-09-30T12:00:00Z");
const sessions = ["a", "b", "c", "d"].map(id => ({ id, start_time: new Date(now + 7200000).toISOString() }));
sessions.push({ id: "free", start_time: new Date(now + 3600000).toISOString() });
test("credit balance replaces fixed two-session cap", () => {
  assert.equal(canSelectSession(sessions, ["a", "b"], "c", 3, now), true);
  assert.equal(canSelectSession(sessions, ["a", "b", "c"], "d", 3, now), false);
  assert.equal(canSelectSession(sessions, ["a"], "a", 0, now), true);
});
test("free bookings and approval requests do not consume selection credits", () => {
  assert.equal(canSelectSession(sessions, [], "free", 0, now), true);
  assert.equal(selectionCost(sessions, ["a", "free"], now), 1);
  assert.equal(canSelectSession(sessions, ["a", "b"], "c", 0, now, true), true);
  assert.equal(canSelectSession(sessions, [], "a", 0, now), false);
});
