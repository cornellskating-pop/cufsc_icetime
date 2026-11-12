import { test } from "node:test";
import assert from "node:assert/strict";
import { noShowRuleDescription } from "../lib/noShowRules.ts";

test("rule description uses saved boundary and both delays", () => {
  assert.equal(noShowRuleDescription({ duration_boundary_minutes: 40, short_delay_minutes: 3, long_delay_minutes: 12 }), "Reporting opens 3 minutes after start for sessions under 40 minutes, or 12 minutes after start for sessions of 40 minutes or more.");
});
test("description supports immediate reporting and singular minutes", () => {
  assert.equal(noShowRuleDescription({ duration_boundary_minutes: 1, short_delay_minutes: 0, long_delay_minutes: 1 }), "Reporting opens 0 minutes after start for sessions under 1 minute, or 1 minute after start for sessions of 1 minute or more.");
});
