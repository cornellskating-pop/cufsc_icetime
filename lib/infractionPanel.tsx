"use client";

import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Msg } from "./ui";

type Restriction = { blocked: boolean; marks: number; ends_at: string | null; remaining_days: number };
type Skater = { id: string; name: string | null; email: string; marks: number; marked_on_date: boolean; restriction: Restriction };
type Mark = { id: string; user_id: string; name: string | null; email: string; marked_date: string; restriction: Restriction };

export function easternToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

function restrictionLabel(r: Restriction) {
  return r.blocked ? `${r.marks} marks this semester · Booking restricted (${r.remaining_days} ice days left)` : `${r.marks} marks this semester`;
}

export function InfractionPanel() {
  const [date, setDate] = useState(easternToday);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Skater[]>([]);
  const [stack, setStack] = useState<Skater[]>([]);
  const [marks, setMarks] = useState<Mark[]>([]);
  const [busy, setBusy] = useState(false);
  const [searching, setSearching] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    let active = true;
    void supabase.rpc("admin_list_infractions", { p_date: date }).then(({ data, error }) => {
      if (!active) return;
      if (error) { setError(error.message); return; }
      setMarks((data || []) as Mark[]);
    });
    return () => { active = false; };
  }, [date, revision]);

  useEffect(() => {
    let active = true;
    const timer = window.setTimeout(async () => {
      if (query.trim().length < 2) { setResults([]); setSearching(false); return; }
      setSearching(true);
      const { data, error } = await supabase.rpc("admin_search_skaters", { p_query: query, p_date: date });
      if (!active) return;
      setSearching(false);
      if (error) { setError(error.message); setResults([]); return; }
      setResults((data || []) as Skater[]);
    }, 250);
    return () => { active = false; window.clearTimeout(timer); };
  }, [query, date, revision]);

  const submit = async () => {
    if (!stack.length || !date || busy) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { data, error } = await supabase.rpc("admin_submit_infractions", { p_user_ids: stack.map(s => s.id), p_date: date });
      if (error) throw error;
      setMessage(`${data.added} infraction${data.added === 1 ? "" : "s"} submitted. ${data.already_marked ? `${data.already_marked} already marked for this date.` : ""}`);
      setStack([]); setRevision(r => r + 1);
    } catch (e) { setError(e instanceof Error ? e.message : (e as { message?: string }).message || "Unable to submit infractions. Try again."); }
    finally { setBusy(false); }
  };

  const undo = async (mark: Mark) => {
    if (!window.confirm(`Undo the ${mark.marked_date} infraction for ${mark.name || mark.email}? Their booking restriction will be recalculated.`)) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { error } = await supabase.rpc("admin_void_infraction", { p_id: mark.id });
      if (error) throw error;
      setMessage("Infraction undone."); setRevision(r => r + 1);
    } catch (e) { setError((e as { message?: string }).message || "Unable to undo infraction."); }
    finally { setBusy(false); }
  };

  return <section className="card" aria-labelledby="infractions-heading" style={{ padding: 20, marginBottom: 24 }}>
    <h2 id="infractions-heading" style={{ fontSize: 18, margin: "0 0 8px" }}>Skating without signing up</h2>
    <p style={{ fontSize: 13, color: "var(--muted)" }}>Add skaters who skated without a booking, choose the date, then submit together. One mark per skater per date. Every third mark in a semester restricts new bookings through the next four ice dates.</p>
    <p style={{ fontSize: 12, color: "var(--muted)" }}>Semesters: Jan–Jul and Aug–Dec. Cancelled sessions and show practices do not count toward the four days. Existing bookings stay in place.</p>
    {error && <Msg text={error} type="error" />}
    {message && <Msg text={message} type="success" />}
    <label style={{ display: "block", marginBottom: 12 }}>Date of marking
      <input className="input" type="date" value={date} max={easternToday()} disabled={busy} onChange={e => { setDate(e.target.value); setResults([]); setMarks([]); setMessage(""); setError(""); }} style={{ maxWidth: 220, display: "block", marginTop: 4 }} />
    </label>
    <label style={{ display: "block" }}>Find a skater
      <input className="input" type="search" placeholder="Search by name or email (2+ characters)" value={query} disabled={busy} onChange={e => { setQuery(e.target.value); setResults([]); }} style={{ marginTop: 4 }} />
    </label>
    <div aria-live="polite" style={{ marginTop: 8 }}>
      {searching && <p>Searching…</p>}
      {!searching && query.trim().length >= 2 && !results.length && <p style={{ fontSize: 13 }}>No matching accounts.</p>}
      {results.map(s => <div key={s.id} style={{ display: "flex", gap: 12, alignItems: "center", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid var(--border)" }}>
        <div><strong>{s.name || s.email}</strong><div style={{ fontSize: 12 }}>{s.email} · {s.marks} marks in selected semester{s.marked_on_date ? " · Already marked on this date" : ""}</div></div>
        <button className="btn-ghost" disabled={busy || s.marked_on_date || stack.some(x => x.id === s.id)} onClick={() => setStack(old => old.some(x => x.id === s.id) ? old : [...old, s])}>Add</button>
      </div>)}
    </div>
    <h3 style={{ fontSize: 14, marginTop: 20 }}>Selected skaters ({stack.length})</h3>
    {stack.length === 0 && <p style={{ fontSize: 13, color: "var(--muted)" }}>Add accounts from the search results.</p>}
    <ul style={{ paddingLeft: 20 }}>{stack.map(s => <li key={s.id} style={{ marginBottom: 8 }}>{s.name || s.email} <span style={{ fontSize: 12 }}>({s.email})</span> <button className="btn-link" disabled={busy} onClick={() => setStack(old => old.filter(x => x.id !== s.id))} aria-label={`Remove ${s.name || s.email} from selection`}>Remove</button></li>)}</ul>
    <button className="btn-primary" disabled={busy || !stack.length || !date} onClick={() => void submit()}>{busy ? "Saving…" : "Submit Infractions"}</button>
    <h3 style={{ fontSize: 14, marginTop: 24 }}>Marks on {date || "selected date"}</h3>
    {marks.length === 0 && <p style={{ fontSize: 13, color: "var(--muted)" }}>No marks recorded.</p>}
    {marks.map(m => <div key={m.id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, padding: "8px 0" }}>
      <div><strong>{m.name || m.email}</strong><div style={{ fontSize: 12 }}>{restrictionLabel(m.restriction)}</div></div>
      <button className="btn-link" disabled={busy} onClick={() => void undo(m)}>Undo mark</button>
    </div>)}
  </section>;
}
