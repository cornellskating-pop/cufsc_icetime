"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "./supabaseClient";
import { easternToday } from "./infractionPanel";
import { Msg } from "./ui";
import { strikeCategory, strikeReason } from "./strikeReason";

type Strike = { id: string; marked_date: string; reason: "unregistered" | "no_show" | "manual"; session_start: string | null; created_at: string; justification: string | null; created_by_name: string | null; voided_at: string | null; voided_by_name: string | null; void_justification: string | null };
type History = { strikes: Strike[]; history: Strike[]; restriction: { blocked: boolean; marks: number; remaining_days: number } };
const validNote = (s: string) => s.trim().length >= 3 && s.trim().length <= 1000;

export function UserStrikeDialog({ user, onClose }: { user: { id: string; name: string; email: string }; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const request = useRef<{ key: string; id: string } | null>(null);
  const [history, setHistory] = useState<History | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [revision, setRevision] = useState(0);
  const [date, setDate] = useState(easternToday);
  const [addNote, setAddNote] = useState("");
  const [removeTarget, setRemoveTarget] = useState<Strike | null>(null);
  const [removeNote, setRemoveNote] = useState("");

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

  const refresh = async () => {
    const { data, error } = await supabase.rpc("admin_user_infractions", { p_user_id: user.id });
    if (error) { setHistory(null); throw new Error("Adjustment saved, but the updated history could not be loaded. Please reload strikes."); }
    setHistory(data as History);
  };

  const add = async () => {
    if (busy || !date || !validNote(addNote)) return;
    if (!window.confirm(`Add one strike dated ${date} to ${user.name || user.email}? Your written justification will be saved and booking eligibility recalculated.`)) return;
    const key = JSON.stringify([user.id, date, addNote.trim()]);
    if (request.current?.key !== key) request.current = { key, id: crypto.randomUUID() };
    setBusy(true); setError(""); setMessage("");
    try {
      const { error } = await supabase.rpc("admin_add_strike", { p_user_id: user.id, p_date: date, p_justification: addNote.trim(), p_request_id: request.current.id });
      if (error) throw error;
      setAddNote(""); request.current = null;
      await refresh(); setMessage("Strike added. Justification recorded and booking restriction recalculated.");
    } catch (e) { setError((e as { message?: string }).message || "Unable to add strike. Reload and try again."); }
    finally { setBusy(false); }
  };

  const remove = async () => {
    if (busy || !removeTarget || !validNote(removeNote)) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { error } = await supabase.rpc("admin_void_infraction", { p_id: removeTarget.id, p_justification: removeNote.trim() });
      if (error) throw error;
      setRemoveTarget(null); setRemoveNote("");
      await refresh(); setMessage("Strike removed. The original and removal justifications remain in history.");
    } catch (e) { setError((e as { message?: string }).message || "Unable to remove strike. Reload and try again."); }
    finally { setBusy(false); }
  };

  const record = (s: Strike) => <div style={{ minWidth: 0, overflowWrap: "anywhere" }}>
    <strong>{s.marked_date}</strong>
    <div style={{ fontSize: 12, color: "var(--muted)" }}>Category: {strikeCategory(s.reason)}</div>
    <p style={{ margin: "4px 0", whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{strikeReason(s)}</p>
    <div style={{ fontSize: 12, color: "var(--muted)" }}>Granted by {s.created_by_name || "an admin (name unavailable)"} · {new Date(s.created_at).toLocaleString("en-US", { timeZone: "America/New_York" })} ET</div>
    {s.voided_at && <div style={{ marginTop: 6, fontSize: 12, whiteSpace: "pre-wrap" }}>Removed by {s.voided_by_name || "an admin (name unavailable)"} · {new Date(s.voided_at).toLocaleString("en-US", { timeZone: "America/New_York" })} ET<br />Removal reason: {s.void_justification || "No written justification recorded (legacy removal)."}</div>}
  </div>;

  return <dialog ref={dialog} aria-labelledby="user-strikes-heading" onCancel={e => { if (busy) e.preventDefault(); else onClose(); }} onClose={onClose}
    style={{ width: "min(680px, calc(100vw - 32px))", maxHeight: "85vh", padding: 24, border: "1px solid var(--border)", borderRadius: 16 }}>
    <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "start" }}>
      <div><h2 id="user-strikes-heading" style={{ fontSize: 20, margin: "0 0 4px" }}>Strikes · {user.name || user.email}</h2><p style={{ fontSize: 12, marginTop: 0, overflowWrap: "anywhere" }}>{user.email}</p></div>
      <button className="btn-ghost" disabled={busy} onClick={onClose}>Close</button>
    </div>
    <p style={{ fontSize: 13, color: "var(--muted)" }}>A written justification is required for every addition or removal (3–1000 characters). One active strike per skater per date. Adjustments recalculate booking eligibility and keep an audit record; credits and bookings stay unchanged.</p>
    {error && <Msg type="error" text={error} />}{message && <Msg type="success" text={message} />}
    <fieldset disabled={busy || !history} style={{ border: "1px solid var(--border)", borderRadius: 10, padding: 14, margin: "12px 0" }}>
      <legend>Add one strike</legend>
      <label style={{ display: "block", fontSize: 13 }}>Strike date (Eastern)<input className="input" type="date" max={easternToday()} value={date} onChange={e => setDate(e.target.value)} style={{ marginTop: 4, maxWidth: 220, display: "block" }} /></label>
      <label style={{ display: "block", margin: "10px 0", fontSize: 13 }}>Why is this strike being granted?<textarea className="input" value={addNote} maxLength={1000} rows={3} onChange={e => setAddNote(e.target.value)} placeholder="Describe the reason for this strike. This reason is visible to the skater." style={{ marginTop: 4, resize: "vertical" }} /></label>
      <button className="btn-primary" disabled={!date || !validNote(addNote)} onClick={() => void add()}>Add strike</button>
    </fieldset>
    {!history ? <p>{error ? "Strike history unavailable." : "Loading strikes…"}</p> : <>
      <p style={{ fontSize: 13 }}>{history.restriction.marks} strike(s) this semester · {history.restriction.blocked ? `Booking restricted (${history.restriction.remaining_days} ice day(s) remaining)` : "No active booking restriction"}</p>
      <h3 style={{ fontSize: 15 }}>Active strikes ({history.strikes.length})</h3>
      {history.strikes.length === 0 ? <p>No active strikes.</p> : <ul style={{ padding: 0, listStyle: "none", fontSize: 13 }}>
        {history.strikes.map(s => <li key={s.id} style={{ padding: "12px 0", borderBottom: "1px solid var(--border)" }}>
          {record(s)}
          <button className="btn-danger" disabled={busy} style={{ marginTop: 8 }} onClick={() => { setRemoveTarget(s); setRemoveNote(""); }}>Remove strike</button>
          {removeTarget?.id === s.id && <div style={{ marginTop: 10 }}>
            <label>Why is this strike being removed?<textarea className="input" value={removeNote} maxLength={1000} rows={3} disabled={busy} onChange={e => setRemoveNote(e.target.value)} style={{ marginTop: 4, resize: "vertical" }} /></label>
            <div style={{ display: "flex", gap: 8, marginTop: 8 }}><button className="btn-danger" disabled={busy || !validNote(removeNote)} onClick={() => void remove()}>Confirm removal</button><button className="btn-ghost" disabled={busy} onClick={() => setRemoveTarget(null)}>Cancel</button></div>
          </div>}
        </li>)}
      </ul>}
      <details style={{ margin: "16px 0" }}><summary style={{ cursor: "pointer", fontWeight: 600 }}>Removed strikes ({(history.history || []).filter(s => s.voided_at).length})</summary>
        <ul style={{ listStyle: "none", padding: 0, fontSize: 13 }}>{(history.history || []).filter(s => s.voided_at).map(s => <li key={s.id} style={{ padding: "12px 0", borderBottom: "1px solid var(--border)" }}>{record(s)}</li>)}</ul>
      </details>
    </>}
    <button className="btn-ghost" disabled={busy} onClick={() => { setError(""); setMessage(""); setHistory(null); setRevision(r => r + 1); }}>Reload strikes</button>
  </dialog>;
}
