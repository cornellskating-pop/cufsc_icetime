import { test } from "node:test";
import assert from "node:assert/strict";
import { freeBookingIndicator } from "../lib/bookingTime.ts";

const start = Date.parse("2026-10-01T00:00:00Z");
const session = { start_time: new Date(start).toISOString(), release_at: null, capacity: 25, spots_left: 3 };
test("no-credit countdown opens exactly 60 minutes before start and closes at start", () => {
  assert.equal(freeBookingIndicator(session, start - 61 * 60_000), "No-credit booking in 1m");
  assert.equal(freeBookingIndicator(session, start - 60 * 60_000), "No-credit booking now");
  assert.equal(freeBookingIndicator(session, start), null);
});
test("release time, capacity and full sessions are respected", () => {
  assert.equal(freeBookingIndicator({ ...session, release_at: new Date(start - 30 * 60_000).toISOString() }, start - 45 * 60_000), "No-credit booking in 15m");
  assert.equal(freeBookingIndicator({ ...session, capacity: 0 }, start - 30 * 60_000), null);
  assert.equal(freeBookingIndicator({ ...session, spots_left: 0 }, start - 30 * 60_000), "No-credit window · full");
});
