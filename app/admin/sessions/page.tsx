"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Msg } from "../../../lib/ui";

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
  const [deleteTarget, setDeleteTarget] = useState<Row | null>(null);
  const [startSort, setStartSort] = useState<"asc" | "desc">("desc");

  const load = async () => {
    const { data, error } = await supabase.rpc("admin_list_sessions");
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setRows((data || []) as Row[]);
  };

  useEffect(() => {
    void supabase.rpc("admin_list_sessions").then(({ data, error }) => {
      if (error) {
        setMsg(error.message);
        setMsgType("error");
        return;
      }
      setRows((data || []) as Row[]);
    });
  }, []);

  const sortedRows = useMemo(
    () => [...rows].sort((a, b) => {
      const timeDifference = new Date(a.start_time).getTime() - new Date(b.start_time).getTime();
      if (timeDifference !== 0) return startSort === "asc" ? timeDifference : -timeDifference;
      return startSort === "asc" ? a.id.localeCompare(b.id) : b.id.localeCompare(a.id);
    }),
    [rows, startSort]
  );

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
    const start = toET(form.start_time);
    const end = toET(form.end_time);
    const release = form.release_at ? toET(form.release_at) : null;
    if (!start || !end) { setMsg("Enter valid session times."); setMsgType("error"); return; }
    if (new Date(end) <= new Date(start)) { setMsg("End time must be after start time."); setMsgType("error"); return; }
    if (release && new Date(release) >= new Date(start)) { setMsg("Release time must be before the session starts."); setMsgType("error"); return; }
    if (Number(form.capacity) < 0) { setMsg("Capacity cannot be negative."); setMsgType("error"); return; }
    const { data, error } = await supabase.rpc("admin_upsert_session", {
      p_id: form.id.trim(),
      p_label: form.label || null,
      p_start_time: start,
      p_end_time: end,
      p_release_at: release,
      p_capacity: Number(form.capacity),
    });
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(`Session saved: ${data}`); setMsgType("success");
    setForm(EMPTY_FORM); setEditing(false); setShowForm(false);
    load();
  };

  const f = (k: keyof typeof EMPTY_FORM) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm(prev => ({ ...prev, [k]: e.target.value }));

  return (<>
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
                  <th aria-sort={startSort === "asc" ? "ascending" : "descending"}>
                    <button
                      type="button"
                      className="admin-start-sort"
                      onClick={() => setStartSort(current => current === "asc" ? "desc" : "asc")}
                      aria-label={`Sort start date ${startSort === "asc" ? "descending" : "ascending"}`}
                    >
                      Start
                      <span className="admin-start-sort-arrow" aria-hidden="true">
                        {startSort === "asc" ? "↑" : "↓"}
                      </span>
                    </button>
                  </th>
                  <th>End</th>
                  <th>Release</th>
                  <th>Capacity</th>
                  <th>Booked</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {sortedRows.map(r => {
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
                        <div style={{ display: "flex", gap: 8 }}>
                          <button className="btn-link" onClick={() => edit(r)}>Edit</button>
                          <button className="btn-link" style={{ color: "var(--red)" }} onClick={() => setDeleteTarget(r)}>Delete</button>
                        </div>
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

    <style>{`
      .admin-start-sort {
        margin: 0;
        padding: 0;
        border: 0;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        background: transparent;
        color: inherit;
        cursor: pointer;
        font: inherit;
        letter-spacing: inherit;
        text-transform: inherit;
      }
      .admin-start-sort:hover,
      .admin-start-sort:focus-visible {
        color: var(--red);
      }
      .admin-start-sort:focus-visible {
        border-radius: 4px;
        outline: 2px solid var(--red-light);
        outline-offset: 3px;
      }
      .admin-start-sort-arrow {
        width: 10px;
        color: var(--red);
        font-size: 11px;
        line-height: 1;
        text-align: center;
      }
    `}</style>

    {deleteTarget && (
      <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)", zIndex: 100,
        display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="card" style={{ padding: 28, maxWidth: 400, width: "90%", textAlign: "center" }}>
          <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 18, marginBottom: 8 }}>Delete Session?</div>
          <div style={{ fontSize: 13, color: "var(--muted)", marginBottom: 20 }}>
            This will permanently delete <strong>{deleteTarget.id}</strong> and all its bookings. This cannot be undone.
          </div>
          <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
            <button className="btn-danger" onClick={async () => {
              const { error } = await supabase.rpc("admin_delete_session", { p_id: deleteTarget.id });
              if (error) { setMsg(error.message); setMsgType("error"); }
              else { setMsg(`Session ${deleteTarget.id} deleted.`); setMsgType("success"); load(); }
              setDeleteTarget(null);
            }}>Yes, Delete</button>
            <button className="btn-ghost" onClick={() => setDeleteTarget(null)}>Cancel</button>
          </div>
        </div>
      </div>
    )}
  </>);
}
