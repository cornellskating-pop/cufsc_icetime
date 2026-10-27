"use client";

import { useEffect, useRef } from "react";
import { walkOnPayment } from "./walkOnPayment";

type Payment = NonNullable<ReturnType<typeof walkOnPayment>>;

export function WalkOnPaymentDialog({ payment, onClose }: { payment: Payment; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);

  return <dialog ref={ref} onCancel={event => { event.preventDefault(); onClose(); }} aria-labelledby="walk-on-title" aria-describedby="walk-on-description"
    style={{ width: "min(440px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 32px)", overflowY: "auto", border: "1px solid var(--border)", borderRadius: 16, padding: 24, color: "var(--ink)" }}>
    <h2 id="walk-on-title" style={{ marginTop: 0, fontSize: 22 }}>Complete your walk-on request</h2>
    <p id="walk-on-description">Approval requested for {payment.count} session{payment.count === 1 ? "" : "s"}. Please Venmo <strong>${payment.amount} to @CUFSC</strong> ($15 per session).</p>
    <p style={{ fontSize: 13 }}>Your payment note is prefilled with: <strong>{payment.note}</strong>. Please also include your Cornell email.</p>
    <p style={{ fontSize: 13 }}>If you already paid, don’t pay again. Your sessions remain pending until an admin approves them; opening Venmo does not confirm payment or a booking.</p>
    <div style={{ display: "flex", flexWrap: "wrap", gap: 12, marginTop: 20 }}>
      <a className="btn-primary" href={payment.url} target="_blank" rel="noopener noreferrer">Pay ${payment.amount} on Venmo</a>
      <button type="button" className="btn-ghost" onClick={onClose}>Close</button>
    </div>
    <style>{`dialog::backdrop { background: rgba(0, 0, 0, .5); }`}</style>
  </dialog>;
}
