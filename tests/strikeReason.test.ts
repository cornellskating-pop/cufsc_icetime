import assert from "node:assert/strict";
import test from "node:test";
import { strikeReason } from "../lib/strikeReason.ts";

test("recorded explanations override every category and preserve lines", () => {
  for (const reason of ["manual", "unregistered", "no_show"]) {
    assert.equal(strikeReason({ reason, justification: "  Actual reported reason\nMore detail  " }), "Actual reported reason\nMore detail");
  }
});
test("missing legacy reasons are explicit and unknown categories are neutral", () => {
  for (const justification of [null, undefined, "", "  "]) {
    assert.match(strikeReason({ reason: "manual", justification }), /Manual strike — no written reason recorded/);
  }
  assert.match(strikeReason({ reason: "unregistered" }), /^Skating without signing up — no written reason/);
  assert.match(strikeReason({ reason: "no_show" }), /^Historical absence strike — no written reason/);
  assert.match(strikeReason({ reason: "unknown" }), /^Strike — no written reason/);
});
