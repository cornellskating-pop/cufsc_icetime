import { test } from "node:test";
import assert from "node:assert/strict";
import { walkOnPayment } from "../lib/walkOnPayment.ts";

const request = (id: string) => ({ ok: true, session_id: id, message: "Approval request submitted" });
test("payment counts successful new requests, excluding pending retries, bookings, failures and duplicates", () => {
  const payment = walkOnPayment([request("a"), request("b"), request("a"),
    { ok: true, session_id: "c", message: "Approval request already pending" },
    { ok: true, session_id: "d", message: "Booked successfully" },
    { ok: false, session_id: "e", message: "Session is full" }], "Test Member", "member@example.test");
  assert.equal(payment?.count, 2);
  assert.equal(payment?.amount, "30.00");
});
test("payment link pays CUFSC and safely encodes the actual member name", () => {
  const payment = walkOnPayment([request("a")], "Test & Member + 演", "member@example.test")!;
  const url = new URL(payment.url);
  assert.equal(url.origin, "https://venmo.com");
  assert.equal(url.searchParams.get("txn"), "pay");
  assert.equal(url.searchParams.get("recipients"), "CUFSC");
  assert.equal(url.searchParams.get("amount"), "15.00");
  assert.equal(url.searchParams.get("note"), "WalkOn Fee Test & Member + 演 · 1 session");
});
test("no prompt without new requests; missing name falls back to email", () => {
  assert.equal(walkOnPayment([], null, "member@example.test"), null);
  assert.equal(walkOnPayment([{ ok: true, message: "Approval request already pending", session_id: "a" }], null, "member@example.test"), null);
  assert.match(walkOnPayment([request("a")], " ", "member@example.test")!.note, /member@example.test/);
});

test("one credit covering one of two sessions leaves only a $15 payment", () => {
  const payment = walkOnPayment([
    { ok: true, session_id: "covered", message: "Booked successfully" },
    request("uncovered"),
  ], "Test Member", "member@example.test")!;
  assert.equal(payment.count, 1);
  assert.equal(new URL(payment.url).searchParams.get("amount"), "15.00");
});
test("fully credit-covered bookings do not prompt for payment", () => {
  assert.equal(walkOnPayment([
    { ok: true, session_id: "a", message: "Booked successfully" },
    { ok: true, session_id: "b", message: "Booked successfully" },
  ], "Test Member", "member@example.test"), null);
});
