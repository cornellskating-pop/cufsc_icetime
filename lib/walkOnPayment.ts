type BookingResult = { ok: boolean; message: string; session_id?: string };

export function walkOnPayment(results: readonly BookingResult[], name: string | null, email: string) {
  // Count only newly created requests, never bookings, failures, or pending retries.
  const count = new Set(results.filter(result => result.ok && result.message === "Approval request submitted" && result.session_id)
    .map(result => result.session_id)).size;
  if (!count) return null;

  const amount = (count * 15).toFixed(2);
  const member = name?.trim() || email;
  const note = `WalkOn Fee ${member} · ${count} session${count === 1 ? "" : "s"}`;
  const query = new URLSearchParams({ txn: "pay", amount, note, recipients: "CUFSC" });
  return { count, amount, note, url: `https://venmo.com/?${query}` };
}
