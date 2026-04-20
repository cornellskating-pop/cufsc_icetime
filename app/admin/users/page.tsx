"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { AdminTopBar, Avatar, Msg } from "../../../lib/ui";

type Row = { id: string; email: string; name: string; tier: string; credits_balance: number; is_admin: boolean };
const EMPTY = { id: "", email: "", name: "", tier: "basic", credits_balance: 0, is_admin: false };
const TIERS = ["basic", "temp", "admin"];

export default function AdminUsers() {
  const [rows, setRows] = useState<Row[]>([]);
  const [form, setForm] = useState(EMPTY);
  const [editing, setEditing] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success"|"error"|"info">("info");
  const [search, setSearch] = useState("");
  const [tierFilter, setTierFilter] = useState("all");
  const [deleteTarget, setDeleteTarget] = useState<Row | null>(null);

  const load = async () => {
    const { data, error } = await supabase.rpc("admin_list_users");
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setRows((data || []) as Row[]);
  };

  useEffect(() => { load(); }, []);

  const edit = (r: Row) => {
    setForm({ id: r.id, email: r.email, name: r.name || "", tier: r.tier || "basic",
      credits_balance: r.credits_balance ?? 0, is_admin: r.is_admin ?? false });
    setEditing(true); setShowForm(true); setMsg("");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const save = async () => {
    setMsg("");
    const { data, error } = await supabase.rpc("admin_upsert_user", {
      p_id: form.id || null, p_email: form.email, p_name: form.name,
      p_tier: form.tier, p_credits_balance: form.credits_balance, p_is_admin: form.is_admin,
    });
    if (error) { setMsg(error.message); setMsgType("error"); return; }
    setMsg(`User saved: ${data}`); setMsgType("success");
    setForm(EMPTY); setEditing(false); setShowForm(false); load();
  };

  const deleteUser = async (id: string) => {
    const { error } = await supabase.rpc("admin_delete_user", { p_id: id });
    if (error) { setMsg(error.message); setMsgType("error"); }
    else { setMsg("User deleted."); setMsgType("success"); load(); }
    setDeleteTarget(null);
  };

  const sf = (k: keyof typeof EMPTY) => (e: React.ChangeEvent<HTMLInputElement|HTMLSelectElement>) =>
    setForm(prev => ({ ...prev, [k]: e.target.type === "checkbox" ? (e.target as HTMLInputElement).checked : e.target.value }));

  const filtered = rows.filter(r => {
    const q = search.toLowerCase();
    const matchSearch = !q || r.email?.toLowerCase().includes(q) || r.name?.toLowerCase().includes(q);
    const matchTier = tierFilter === "all" || r.tier === tierFilter;
    return matchSearch && matchTier;
  });

  const allTiers = [...new Set(rows.map(r => r.tier).filter(Boolean))].sort();

  return (
    <>
    <div>
      <AdminTopBar active="users" />
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <div>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>Users</div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>{rows.length} members</div>
          </div>
          <button className="btn-primary" onClick={() => { setForm(EMPTY); setEditing(false); setShowForm(v => !v); }}>
            {showForm && !editing ? "✕ Cancel" : "+ Add User"}
          </button>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        {/* Form */}
        {showForm && (
          <div className="card" style={{ padding: 20, marginBottom: 24 }}>
            <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14, marginBottom: 16 }}>
              {editing ? "Edit User" : "New User"}
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
              {[["Email", "email", "text", "netid@cornell.edu"], ["Name", "name", "text", "Full Name"]].map(([label, key, type, ph]) => (
                <div key={key}>
                  <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>{label}</label>
                  <input className="input" type={type} placeholder={ph} value={String(form[key as keyof typeof EMPTY])} onChange={sf(key as keyof typeof EMPTY)} />
                </div>
              ))}
              <div>
                <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>Tier</label>
                <select className="input" value={form.tier} onChange={sf("tier")}>
                  {TIERS.map(t => <option key={t} value={t}>{t}</option>)}
                </select>
              </div>
              <div>
                <label style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.08em", display: "block", marginBottom: 5 }}>Credits</label>
                <input className="input" type="number" min={0} value={form.credits_balance} onChange={sf("credits_balance")} />
              </div>
              <div style={{ gridColumn: "1/-1", display: "flex", alignItems: "center", gap: 10 }}>
                <input type="checkbox" id="is_admin" checked={form.is_admin}
                  onChange={e => setForm(p => ({ ...p, is_admin: e.target.checked }))} />
                <label htmlFor="is_admin" style={{ fontSize: 13 }}>Grant admin access</label>
              </div>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 16 }}>
              <button className="btn-primary" onClick={save}>Save User</button>
              <button className="btn-ghost" onClick={() => { setShowForm(false); setEditing(false); setForm(EMPTY); }}>Cancel</button>
            </div>
          </div>
        )}

        {/* Search + filter */}
        <div style={{ display: "flex", gap: 10, marginBottom: 16, flexWrap: "wrap" }}>
          <input className="input input-sm" placeholder="Search by name or email…" value={search}
            onChange={e => setSearch(e.target.value)} style={{ maxWidth: 280 }} />
          <select className="input input-sm" value={tierFilter} onChange={e => setTierFilter(e.target.value)} style={{ maxWidth: 140 }}>
            <option value="all">All Tiers</option>
            {allTiers.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
        </div>

        <div className="card">
          <div style={{ overflowX: "auto" }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Member</th>
                  <th>Tier</th>
                  <th>Credits</th>
                  <th>Admin</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(r => (
                  <tr key={r.id}>
                    <td>
                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <Avatar name={r.name || r.email} size={28} />
                        <div>
                          <div style={{ fontWeight: 500, fontSize: 13 }}>{r.name || <span style={{ color: "var(--muted)" }}>—</span>}</div>
                          <div style={{ fontSize: 11, color: "var(--muted)" }}>{r.email}</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <span style={{ background: "var(--ink)", color: "white", fontFamily: "'Syne',sans-serif",
                        fontSize: 10, fontWeight: 700, padding: "2px 8px", borderRadius: 100,
                        textTransform: "uppercase", letterSpacing: "0.04em" }}>
                        {r.tier}
                      </span>
                    </td>
                    <td>{r.credits_balance ?? 0}</td>
                    <td>
                      <span className={`badge ${r.is_admin ? "badge-open" : "badge-ended"}`}>
                        {r.is_admin ? "Yes" : "No"}
                      </span>
                    </td>
                    <td>
                      <div style={{ display: "flex", gap: 8 }}>
                        <button className="btn-link" onClick={() => edit(r)}>Edit</button>
                        <button className="btn-link" style={{ color: "var(--red)" }} onClick={() => setDeleteTarget(r)}>Delete</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    {deleteTarget && (
      <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)", zIndex: 100,
        display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="card" style={{ padding: 28, maxWidth: 400, width: "90%", textAlign: "center" }}>
          <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 18, marginBottom: 8 }}>Delete User?</div>
          <div style={{ fontSize: 13, color: "var(--muted)", marginBottom: 20 }}>
            This will permanently delete <strong>{deleteTarget.name || deleteTarget.email}</strong> and cannot be undone.
          </div>
          <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
            <button className="btn-danger" onClick={() => deleteUser(deleteTarget!.id)}>Yes, Delete</button>
            <button className="btn-ghost" onClick={() => setDeleteTarget(null)}>Cancel</button>
          </div>
        </div>
      </div>
    )}
    </>
  );
}