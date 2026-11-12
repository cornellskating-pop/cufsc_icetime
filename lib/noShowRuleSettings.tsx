"use client";

import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Msg } from "./ui";
import { noShowRuleDescription, type NoShowRules } from "./noShowRules";

const fields = [
  ["duration_boundary_minutes", "Session-length boundary (minutes)", 1, 240],
  ["short_delay_minutes", "Delay for shorter sessions (minutes)", 0, 120],
  ["long_delay_minutes", "Delay at or above the boundary (minutes)", 0, 120],
] as const;

export function NoShowRuleSettings() {
  const [saved, setSaved] = useState<NoShowRules | null>(null);
  const [form, setForm] = useState({ duration_boundary_minutes: "", short_delay_minutes: "", long_delay_minutes: "" });
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [revision, setRevision] = useState(0);
  const values = { duration_boundary_minutes: Number(form.duration_boundary_minutes), short_delay_minutes: Number(form.short_delay_minutes), long_delay_minutes: Number(form.long_delay_minutes) };
  const valid = fields.every(([key, , min, max]) => form[key].trim() !== "" && Number.isInteger(values[key]) && values[key] >= min && values[key] <= max);
  const changed = !!saved && fields.some(([key]) => values[key] !== saved[key]);

  const apply = (r: NoShowRules) => {
    setSaved(r);
    setForm({ duration_boundary_minutes: String(r.duration_boundary_minutes), short_delay_minutes: String(r.short_delay_minutes), long_delay_minutes: String(r.long_delay_minutes) });
  };

  useEffect(() => {
    let active = true;
    void supabase.rpc("admin_get_no_show_rules").then(({ data, error }) => {
      if (!active) return;
      setLoading(false);
      if (error) { setError(error.message); return; }
      apply(data as NoShowRules);
    });
    return () => { active = false; };
  }, [revision]);

  const save = async () => {
    if (!saved || !valid || busy || !changed) return;
    if (!window.confirm(`${noShowRuleDescription(values)} Apply these rules to all new reports, including reports for past sessions? Existing strikes keep their original cutoff records.`)) return;
    setBusy(true); setError(""); setMessage("");
    try {
      const { data, error } = await supabase.rpc("admin_set_no_show_rules", { p_duration_boundary_minutes: values.duration_boundary_minutes, p_short_delay_minutes: values.short_delay_minutes, p_long_delay_minutes: values.long_delay_minutes, p_expected_version: saved.version });
      if (error) throw error;
      apply(data as NoShowRules);
      setMessage("Timing rules saved. The reporting page uses these saved rules and refreshes automatically within 30 seconds.");
    } catch (e) { setError((e as { message?: string }).message || "Unable to save rules. Please retry."); }
    finally { setBusy(false); }
  };

  return <section className="card" aria-labelledby="no-show-settings-heading" style={{ padding: 20, marginBottom: 20 }}>
    <h2 id="no-show-settings-heading" style={{ fontSize: 18, margin: "0 0 8px" }}>No-show penalty timing</h2>
    <p style={{ fontSize: 13, color: "var(--muted)" }}>Change when admins can report booked skaters as absent. A session exactly at the length boundary uses the longer-session delay. Changes apply to new reports for ongoing and past sessions; existing strikes stay unchanged.</p>
    {error && <Msg type="error" text={error} />}
    {message && <Msg type="success" text={message} />}
    {loading ? <p>Loading saved rules…</p> : <>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12 }}>
        {fields.map(([key, label, min, max]) => <label key={key} style={{ fontSize: 13 }}>{label}<input className="input" type="number" min={min} max={max} step={1} value={form[key]} disabled={busy || !saved} onChange={e => { setForm(old => ({ ...old, [key]: e.target.value })); setMessage(""); }} style={{ display: "block", marginTop: 5 }} /></label>)}
      </div>
      <p style={{ fontSize: 13 }}><strong>Preview: </strong>{valid ? noShowRuleDescription(values) : "Enter whole numbers: boundary 1–240 minutes; delays 0–120 minutes."}</p>
      {saved && <p style={{ fontSize: 12, color: "var(--muted)" }}>Last saved: {new Date(saved.updated_at).toLocaleString("en-US", { timeZone: "America/New_York" })} ET</p>}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        <button className="btn-primary" disabled={busy || !valid || !changed} onClick={() => void save()}>{busy ? "Saving…" : "Save timing rules"}</button>
        <button className="btn-ghost" disabled={busy} onClick={() => { if (changed && !window.confirm("Discard your edits and reload the saved rules?")) return; setLoading(true); setError(""); setMessage(""); setRevision(r => r + 1); }}>Reload saved rules</button>
      </div>
    </>}
  </section>;
}
