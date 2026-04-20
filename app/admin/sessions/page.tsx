"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg, SpotBar } from "../../../lib/ui";

type Row = {
  id: string;
  label: string | null;
  start_time: string;
  end_time: string;
  release_at: string | null;
  capacity: number;
  spots_left?: number;
};

const EMPTY_FORM = { id: "", label: "", start_time: "", end_time: "", release_at: "", capacity: 25 };

export default function AdminSessions() {
  const [rows, setRows] = useState<Row[]>([]);
  const [form, setForm] = useState(EMPTY_FORM);
  const [editing, setEditing] = useState(false);
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success"|"error"|"info">("info");
  const [showForm, setShowForm] = useState(false);

  const load = async () => {
    const { data, error } = await supabase.rpc("admin_list_sessions");
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setRows(((data || []) as Row[]).reverse());
  };

  useEffect(() => { load(); }, []);

  const edit = (r: Row) => {
    setForm({
      id: r.id, label: r.label || "",
      start_time: fromET(r.start_time),
      end_time: fromET(r.end_time),
      release_at: r.release_at ? fromET(r.release_at) : "",
      capacity: r.capacity,
    });
    setEditing(true); setShowForm(true); setMsg("");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const fromET = (iso: string) =>
    new Date(iso).toLocaleString("sv-SE", { timeZone: "America/New_York" }).replace(" ", "T").slice(0, 16);

  const toET = (local: string) => {
    if (!local) return null;
    const tzPart = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      timeZoneName: "shortOffset",
    }).formatToParts(new Date(local)).find(p => p.type === "timeZoneName")!.value;
    const match = tzPart.match(/GMT([+-])(\d+)(?::(\d+))?/);
    if (!match) return local;
    const [, sign, h, m = "00"] = match;
    return `${local}:00${sign}${h.padStart(2, "0")}:${m.padStart(2, "0")}`;
  };

  const save = async () => {
    setMsg("");
    if (!form.id.trim()) { setMsg("Session ID is required."); setMsgType("error"); return; }
    if (!form.start_time) { setMsg("Start time is required."); setMsgType("error"); return; }
    if (!form.end_time) { setMsg("End time is required."); setMsgType("error"); return; }
    const start = new Date(form.start_time);
    const end = new Date(form.end_time);
    const release = form.release_at ? new Date(form.release_at) : null;
    if (end <= start) { setMsg("End time must be after start time."); setMsgType("error"); return; }
    if (release && release >= start) { setMsg("Release time must be before the session starts."); setMsgType("error"); return; }
    if (Number(form.capacity) < 0) { setMsg("Capacity cannot be negative."); setMsgType("error"); return; }
    const { data, error } = await supabase.rpc("admin_upsert_session", {
      p_id: form.id.trim(),
      p_label: form.label || null,
      p_start_time: toET(form.start_time),
      p_end_time: toET(form.end_time),
      p_release_at: form.release_at ? toET(form.release_at) : null,
      p_capacity: Number(form.capacity),
    });
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(`Session saved: ${data}`); setMsgType("success");
    setForm(EMPTY_FORM); setEditing(false); setShowForm(false);
    load();
  };

  const f = (k: keyof typeof EMPTY_FORM) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm(prev => ({ ...prev, [k]: e.target.value }));

  return (
    <div>
      <AdminTopBar active="sessions" />

      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>

        {/* Header row */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <div>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>Sessions</div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>{rows.length} total</div>
          </div>
          <button className="btn-primary" onClick={() => { setForm(EMPTY_FORM); setEditing(false); setShowForm(v => !v); }}>
            {showForm && !editing ? "✕ Cancel" : "+ Add Session"}
          </button>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        {/* Form */}
        {showForm && (
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14, marginBottom: 16 }}>
              {editing ? "Edit Session" : "New Session"}
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
              <div style={{ gridColumn: "1/-1" }}>
                <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>Session ID</label>
                <input className="input" placeholder="e.g. SCT-2026-03-04-1800" value={form.id} onChange={f("id")} />
              </div>
              <div style={{ gridColumn: "1/-1" }}>
                <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>Label (optional)</label>
                <input className="input" placeholder="e.g. Tuesday Open Skate" value={form.label} onChange={f("label")} />
              </div>
              {[
                ["Start Time", "start_time"], ["End Time", "end_time"], ["Release At", "release_at"],
              ].map(([label, key]) => (
                <div key={key}>
                  <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>{label}</label>
                  <input className="input" type="datetime-local" value={form[key as keyof typeof EMPTY_FORM]} onChange={f(key as keyof typeof EMPTY_FORM)} />
                </div>
              ))}
              <div>
                <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>Capacity</label>
                <input className="input" type="number" min={1} value={form.capacity} onChange={f("capacity")} />
              </div>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 16 }}>
              <button className="btn-primary" onClick={save}>Save Session</button>
              <button className="btn-ghost" onClick={() => { setShowForm(false); setEditing(false); setForm(EMPTY_FORM); }}>Cancel</button>
            </div>
          </div>
        )}

        {/* Table */}
        <div className="card">
          <div style={{ overflowX: "auto" }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Label</th>
                  <th>Start</th>
                  <th>End</th>
                  <th>Release</th>
                  <th>Capacity</th>
                  <th>Booked</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => {
                  const booked = r.capacity - (r.spots_left ?? r.capacity);
                  return (
                    <tr key={r.id}>
                      <td style={{ fontFamily: "monospace", fontSize: 11, color: "var(--muted)" }}>{r.id}</td>
                      <td style={{ fontWeight: 500 }}>{r.label || <span style={{ color: "var(--muted)" }}>—</span>}</td>
                      <td style={{ whiteSpace: "nowrap" }}>
                        {new Date(r.start_time).toLocaleString("en-US", { timeZone: "America/New_York", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}
                      </td>
                      <td style={{ whiteSpace: "nowrap", color: "var(--muted)" }}>
                        {new Date(r.end_time).toLocaleString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" })}
                      </td>
                      <td style={{ color: "var(--muted)", fontSize: 12 }}>
                        {r.release_at ? new Date(r.release_at).toLocaleString("en-US", { timeZone: "America/New_York", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : "—"}
                      </td>
                      <td>{r.capacity}</td>
                      <td style={{ minWidth: 100 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                          <div style={{ flex: 1, height: 4, background: "var(--border)", borderRadius: 4, overflow: "hidden" }}>
                            <div style={{ width: `${r.capacity > 0 ? (booked / r.capacity) * 100 : 0}%`, height: "100%",
                              background: booked / r.capacity > 0.8 ? "var(--warn)" : "var(--success)", borderRadius: 4 }} />
                          </div>
                          <span style={{ fontSize: 11, color: "var(--muted)" }}>{booked}/{r.capacity}</span>
                        </div>
                      </td>
                      <td>
                        <button className="btn-link" onClick={() => edit(r)}>Edit</button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}