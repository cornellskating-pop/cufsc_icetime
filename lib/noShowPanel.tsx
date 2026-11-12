"use client";

import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { easternToday } from "./infractionPanel";
import { Msg } from "./ui";

type Session = { id: string; start_time: string; end_time: string; label: string | null; reportable_at: string };
type Skater = { booking_id: string; name: string | null; email: string; present: boolean; booking_status: string; already_marked: boolean; no_show_mark_id: string | null };
const time = (value: string) => new Date(value).toLocaleTimeString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" });
const eligible = (s: Skater) => !s.present && !s.already_marked && s.booking_status === "active";

export function NoShowPanel() {
  const [date, setDate] = useState(easternToday);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [sessionId, setSessionId] = useState("");
  const [roster, setRoster] = useState<Skater[]>([]);
  const [rosterSession, setRosterSession] = useState("");
  const [selected, setSelected] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [now, setNow] = useState(Date.now);
  const session = sessions.find(s => s.id === sessionId);
  const rosterLoading = loading || (!!sessionId && rosterSession !== sessionId);
  const cutoffReached = !!session && now >= new Date(session.reportable_at).getTime();

  useEffect(() => {
    const timer = window.setInterval(() => { setNow(Date.now()); setRevision(r => r + 1); }, 30_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!date) return;
    let active = true;
    void supabase.rpc("admin_no_show_sessions", { p_date: date }).then(({ data, error }) => {
      if (!active) return;
      if (error) { setError(error.message); setSessions([]); setSessionId(""); setRoster([]); setSelected([]); setLoading(false); return; }
      const rows = (data || []) as Session[];
      setSessions(rows);
      setSessionId(old => rows.some(s => s.id === old) ? old : (rows.find(s => Date.now() < new Date(s.end_time).getTime()) || rows.at(-1))?.id || "");
      if (!rows.length) { setRoster([]); setLoading(false); }
    });
    return () => { active = false; };
  }, [date, revision]);

  useEffect(() => {
    if (!sessionId) return;
    let active = true;
    void supabase.rpc("admin_no_show_roster", { p_session_id: sessionId }).then(({ data, error }) => {
      if (!active) return;
      setLoading(false);
      setRosterSession(sessionId);
      if (error) { setError(error.message); setRoster([]); setSelected([]); return; }
      const rows = (data || []) as Skater[];
      setRoster(rows);
      setSelected(old => old.filter(id => rows.some(s => s.booking_id === id && eligible(s))));
    });
    return () => { active = false; };
  }, [sessionId, revision]);

  const submit = async () => {
    if (busy || rosterLoading || !cutoffReached || !selected.length) return;
    if (!window.confirm(`Report ${selected.length} selected skater(s) as booked but absent on ${date}? These strikes count toward the semester booking restriction.`)) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { data, error } = await supabase.rpc("admin_report_no_shows", { p_session_id: sessionId, p_booking_ids: selected });
      if (error) throw error;
      setSelected([]);
      setMessage(`${data.added} no-show strike(s) recorded.${data.already_marked ? ` ${data.already_marked} already marked for this date.` : ""}`);
      setRevision(r => r + 1);
    } catch (e) { setError((e as { message?: string }).message || "Unable to report no-shows. Refresh and retry."); setRevision(r => r + 1); }
    finally { setBusy(false); }
  };

  const undo = async (s: Skater) => {
    if (!s.no_show_mark_id || !window.confirm(`Undo the no-show strike for ${s.name || s.email} on ${date}?`)) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { error } = await supabase.rpc("admin_void_infraction", { p_id: s.no_show_mark_id });
      if (error) throw error;
      setMessage("No-show strike undone. The booking restriction has been recalculated."); setRevision(r => r + 1);
    } catch (e) { setError((e as { message?: string }).message || "Unable to undo this strike."); }
    finally { setBusy(false); }
  };

  return <section aria-labelledby="no-show-heading" style={{ padding: 20 }}>
    <h2 id="no-show-heading" style={{ fontSize: 18, margin: "0 0 8px" }}>Booked but absent</h2>
    <p style={{ fontSize: 13, color: "var(--muted)" }}>Select a session and only the skaters whose absence you have confirmed. Reporting opens 5 minutes after start for sessions under 35 minutes, or 8 minutes after start for sessions of 35 minutes or more. Past sessions can also be reported.</p>
    <p style={{ fontSize: 12, color: "var(--muted)" }}>Unchecked Present boxes never create automatic strikes. Cancelled bookings are excluded. Strikes use the session’s Eastern date and count toward the existing semester penalty, with at most one strike per skater per date. Bookings and credits stay unchanged.</p>
    {error && <Msg type="error" text={error} />}
    {message && <Msg type="success" text={message} />}
    <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "end" }}>
      <label>Session date (Eastern)
        <input className="input" type="date" value={date} max={easternToday()} disabled={busy} style={{ display: "block", marginTop: 4 }} onChange={e => { setDate(e.target.value); setSessionId(""); setSessions([]); setRoster([]); setSelected([]); setLoading(!!e.target.value); setMessage(""); setError(""); }} />
      </label>
      <label style={{ flex: "1 1 260px", minWidth: 0 }}>Session
        <select className="input" value={sessionId} disabled={busy || !sessions.length} style={{ display: "block", marginTop: 4 }} onChange={e => { setSessionId(e.target.value); setRoster([]); setSelected([]); setLoading(true); setMessage(""); setError(""); }}>
          {!sessions.length && <option value="">No started sessions on this date</option>}
          {sessions.map(s => <option key={s.id} value={s.id}>{time(s.start_time)}–{time(s.end_time)}{s.label ? ` · ${s.label}` : ""}{now < new Date(s.end_time).getTime() ? " · Ongoing" : " · Ended"}</option>)}
        </select>
      </label>
      <button className="btn-ghost" disabled={busy || !date} onClick={() => { setLoading(true); setError(""); setRevision(r => r + 1); }}>Refresh</button>
    </div>
    {session && <p style={{ fontSize: 13 }}>{cutoffReached ? `Reporting is open (cutoff: ${time(session.reportable_at)} ET).` : `Reporting opens at ${time(session.reportable_at)} ET.`}</p>}
    {rosterLoading ? <p aria-live="polite">Loading roster…</p> : session && !roster.length ? <p>No active bookings for this session.</p> : <ul style={{ listStyle: "none", padding: 0 }}>
      {roster.map(s => <li key={s.booking_id} style={{ display: "flex", gap: 12, justifyContent: "space-between", alignItems: "center", padding: "10px 0", borderBottom: "1px solid var(--border)" }}>
        <label style={{ display: "flex", gap: 10, alignItems: "center", minWidth: 0 }}>
          <input type="checkbox" checked={selected.includes(s.booking_id)} disabled={busy || !cutoffReached || !eligible(s)} onChange={e => setSelected(old => e.target.checked ? [...old, s.booking_id] : old.filter(id => id !== s.booking_id))} />
          <span style={{ minWidth: 0, overflowWrap: "anywhere" }}><strong>{s.name || s.email}</strong><span style={{ display: "block", fontSize: 12 }}>{s.email}</span><span style={{ display: "block", fontSize: 12 }}>{s.no_show_mark_id ? "No-show strike recorded" : s.already_marked ? "Already marked on this date" : s.present ? "Marked present" : "Active booking · Confirm absence before selecting"}</span></span>
        </label>
        {s.no_show_mark_id && <button className="btn-link" disabled={busy} onClick={() => void undo(s)}>Undo strike</button>}
      </li>)}
    </ul>}
    <button className="btn-primary" disabled={busy || rosterLoading || !cutoffReached || !selected.length} onClick={() => void submit()}>{busy ? "Saving…" : `Submit No-show Strikes (${selected.length})`}</button>
  </section>;
}
