import { test } from "node:test";
import assert from "node:assert/strict";
import { easternDateKey, monthDays, shiftMonth } from "../lib/adminCalendar.ts";

test("sessions use the Eastern calendar date across midnight and daylight saving", () => {
  assert.equal(easternDateKey("2026-10-28T01:00:00Z"), "2026-10-27");
  assert.equal(easternDateKey("2026-11-01T05:30:00Z"), "2026-11-01");
  assert.equal(easternDateKey("2026-11-01T06:30:00Z"), "2026-11-01");
});
test("month grid includes every date exactly once, padded to full Sunday weeks", () => {
  const october = monthDays("2026-10");
  assert.equal(october.length, 35);
  assert.equal(october[0].key, "2026-09-27");
  assert.equal(october.at(-1)?.key, "2026-10-31");
  assert.equal(october.filter(day => day.inMonth).length, 31);
  const leap = monthDays("2028-02");
  assert.equal(leap.filter(day => day.inMonth).length, 29);
  assert.equal(new Set(leap.map(day => day.key)).size, leap.length);
  assert.equal(monthDays("2026-08").length, 42);
});
test("month navigation crosses year boundaries", () => {
  assert.equal(shiftMonth("2026-12", 1), "2027-01");
  assert.equal(shiftMonth("2026-01", -1), "2025-12");
});
