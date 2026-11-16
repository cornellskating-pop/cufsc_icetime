import { test } from "node:test";
import assert from "node:assert/strict";
import { noShowRuleDescription } from "../lib/noShowRules.ts";

test("all session lengths use the single saved removal delay", () => {
  assert.equal(noShowRuleDescription({ delay_minutes: 8 }), "Removal opens 8 minutes after start for all sessions. No strikes are applied.");
  assert.match(noShowRuleDescription({ delay_minutes: 12 }), /12 minutes/);
});
test("description supports immediate removal and singular minutes", () => {
  assert.match(noShowRuleDescription({ delay_minutes: 0 }), /0 minutes/);
  assert.match(noShowRuleDescription({ delay_minutes: 1 }), /1 minute after/);
});
