"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "./supabaseClient";
import { Msg } from "./ui";

type Strike = { id: string; marked_date: string; reason: "unregistered" | "no_show"; session_start: string | null; created_at: string };
type History = { strikes: Strike[]; restriction: { blocked: boolean; marks: number; remaining_days: number } };

export function UserStrikeDialog({ user, onClose }: { user: { id: string; name: string; email: string }; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [history, setHistory] = useState<History | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [removing, setRemoving] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    const node = dialog.current;
    const previousFocus = document.activeElement;
    node?.showModal();
    return () => { node?.close(); if (previousFocus instanceof HTMLElement) previousFocus.focus(); };
  }, []);

  useEffect(() => {
    let active = true;
    void supabase.rpc("admin_user_infractions", { p_user_id: user.id }).then(({ data, error }) => {
      if (!active) return;
      if (error) { setError(error.message); return; }
      setHistory(data as History);
    });
    return () => { active = false; };
  }, [user.id, revision]);

  const remove = async (strike: Strike) => {
    if (removing || !window.confirm(`Remove the ${strike.marked_date} ${strike.reason === "no_show" ? "no-show" : "skating without signup"} strike from ${user.name || user.email}? Their booking restriction will be recalculated. An audit record is retained.`)) return;
    setRemoving(strike.id); setError(""); setMessage("");
    try {
      const { error } = await supabase.rpc("admin_void_infraction", { p_id: strike.id });
      if (error) throw error;
      const { data, error: refreshError } = await supabase.rpc("admin_user_infractions", { p_user_id: user.id });
      if (refreshError) { setHistory(null); throw new Error("Strike removed, but the updated list could not be loaded. Please reload strikes."); }
      setHistory(data as History); setMessage("Strike removed and booking restriction recalculated.");
    } catch (e) { setError((e as { message?: string }).message || "Unable to remove strike. Reload and try again."); }
    finally { setRemoving(null); }
  };

  return <dialog ref={dialog} aria-labelledby="user-strikes-heading" onCancel={e => { if (removing) e.preventDefault(); else onClose(); }} onClose={onClose}
    style={{ width: "min(640px, calc(100vw - 32px))", maxHeight: "80vh", padding: 24, border: "1px solid var(--border)", borderRadius: 16 }}>
    <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "start" }}>
      <div><h2 id="user-strikes-heading" style={{ fontSize: 20, margin: "0 0 4px" }}>Strikes · {user.name || user.email}</h2><p style={{ fontSize: 12, marginTop: 0, overflowWrap: "anywhere" }}>{user.email}</p></div>
      <button className="btn-ghost" disabled={removing !== null} onClick={onClose}>Close</button>
    </div>
    <p style={{ fontSize: 13, color: "var(--muted)" }}>Active strikes from all semesters. Removing a strike retains its audit history and recalculates booking eligibility. Credits and existing bookings stay unchanged.</p>
    {error && <Msg type="error" text={error} />}{message && <Msg type="success" text={message} />}
    {!history ? <p>{error ? "Strike history unavailable." : "Loading strikes…"}</p> : <>
      <p style={{ fontSize: 13 }}>{history.restriction.marks} strike(s) this semester · {history.restriction.blocked ? `Booking restricted (${history.restriction.remaining_days} ice day(s) remaining)` : "No active booking restriction"}</p>
      {history.strikes.length === 0 ? <p>No active strikes.</p> : <ul style={{ padding: 0, listStyle: "none" }}>
        {history.strikes.map(s => <li key={s.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, padding: "12px 0", borderBottom: "1px solid var(--border)" }}>
          <div><strong>{s.marked_date}</strong><div style={{ fontSize: 13 }}>{s.reason === "no_show" ? "Booked but absent" : "Skating without signing up"}</div>{s.session_start && <div style={{ fontSize: 12 }}>Session: {new Date(s.session_start).toLocaleTimeString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" })} ET</div>}</div>
          <button className="btn-danger" disabled={removing !== null} onClick={() => void remove(s)}>{removing === s.id ? "Removing…" : "Remove strike"}</button>
        </li>)}
      </ul>}
    </>}
    <button className="btn-ghost" disabled={removing !== null} onClick={() => { setError(""); setMessage(""); setHistory(null); setRevision(r => r + 1); }}>Reload strikes</button>
  </dialog>;
}
