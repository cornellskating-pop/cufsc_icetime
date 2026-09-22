"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabaseClient";
import { SessionBookingHeader } from "../../../lib/sessionBookingHeader";
import { AdminTopBar, Msg } from "../../../lib/ui";

type BookingEntry = {
  booking_id: string;
  created_at: string;
  user_id: string;
  email: string;
  name: string;
  tier: string;
  status: string;
};

type SessionGroup = {
  session_id: string;
  start_time: string;
  end_time: string;
  label: string | null;
  capacity: number;
  bookings: BookingEntry[];
};

type SessionRow = {
  id: string;
  start_time: string;
  end_time: string;
  label: string | null;
  capacity: number;
};

type GroupedBookingRow = {
  session_id: string;
  bookings: BookingEntry[] | null;
};

export default function AdminBookings() {
  const [removing, setRemoving] = useState<string | null>(null);
  const [groups, setGroups] = useState<SessionGroup[]>([]);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success" | "error" | "info">("info");

  useEffect(() => {
    void Promise.all([
      supabase.rpc("admin_list_sessions"),
      supabase.rpc("admin_list_session_bookings_grouped"),
    ]).then(([sessionsResult, bookingsResult]) => {
      if (sessionsResult.error) {
        setMsg(sessionsResult.error.message);
        setMsgType("error");
        return;
      }
      if (bookingsResult.error) {
        setMsg(bookingsResult.error.message);
        setMsgType("error");
        return;
      }

      const bookingMap = new Map<string, BookingEntry[]>();
      ((bookingsResult.data || []) as GroupedBookingRow[]).forEach(row => {
        bookingMap.set(row.session_id, (row.bookings || []).filter(b => b.status === "active"));
      });

      const now = new Date();
      const allSessions = (sessionsResult.data || []) as SessionRow[];
      const upcoming = allSessions.filter(s => new Date(s.start_time) >= now);
      const past8 = allSessions.filter(s => new Date(s.end_time) < now).slice(-8).reverse();

      setGroups([...upcoming, ...past8].map(s => ({
        session_id: s.id,
        start_time: s.start_time,
        end_time: s.end_time,
        label: s.label,
        capacity: s.capacity,
        bookings: bookingMap.get(s.id) || [],
      })));
      setExpanded(new Set(upcoming.map(s => s.id)));
    });
  }, []);

  const removeBooking = async (entry: BookingEntry, group: SessionGroup) => {
    if (!window.confirm(`Remove ${entry.name || "this member"} from ${new Date(group.start_time).toLocaleString("en-US", { timeZone: "America/New_York" })} ET? Any charged credit will be refunded, and a removal email will be sent.`)) return;
    setRemoving(entry.booking_id);
    try {
      const { data, error } = await supabase.rpc("admin_remove_booking", { p_booking_id: entry.booking_id });
      if (error) throw error;
      setGroups(current => current.map(item => item.session_id === group.session_id
        ? { ...item, bookings: item.bookings.filter(booking => booking.booking_id !== entry.booking_id) } : item));
      setMsg(String(data));
      setMsgType("success");
    } catch {
      setMsg("Unable to remove this booking. Please try again.");
      setMsgType("error");
    } finally { setRemoving(null); }
  };

  const toggle = (id: string) =>
    setExpanded(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const fmtShort = (d: string) => new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York", month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit",
  });

  const now = new Date();
  const totalActive = groups.reduce((s, g) => s + g.bookings.length, 0);

  return (
    <div>
      <AdminTopBar active="bookings" />
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "28px 24px 80px" }}>
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, letterSpacing: "-0.02em" }}>Bookings</div>
          <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>
            {groups.length} sessions · {totalActive} active bookings
          </div>
        </div>

        {msg && <Msg text={msg} type={msgType} />}

        {groups.length === 0 ? (
          <div style={{ padding: "40px 0", textAlign: "center", color: "var(--muted)" }}>No sessions to show.</div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            {groups.map(g => {
              const isPast = new Date(g.end_time) < now;
              const isOpen = expanded.has(g.session_id);
              return (
                <div key={g.session_id} className="card">
                  <div
                    onClick={() => toggle(g.session_id)}
                    style={{
                      padding: "14px 20px", cursor: "pointer",
                      background: isPast ? "var(--muted-bg, #f5f5f5)" : "var(--ink)",
                      display: "flex", alignItems: "center", justifyContent: "space-between",
                    }}
                  >
                    <SessionBookingHeader startTime={g.start_time} endTime={g.end_time} label={g.label} count={g.bookings.length} capacity={g.capacity} isOpen={isOpen} isPast={isPast} />
                  </div>

                  {isOpen && (
                    g.bookings.length === 0 ? (
                      <div style={{ padding: "16px 20px", fontSize: 13, color: "var(--muted)" }}>No bookings for this session.</div>
                    ) : (
                      <table className="data-table">
                        <thead>
                          <tr>
                            <th>#</th>
                            <th>Name</th>
                            <th>Email</th>
                            <th>Tier</th>
                            <th>Signed Up</th>
                            <th>Actions</th>
                          </tr>
                        </thead>
                        <tbody>
                          {g.bookings.map((b, i) => (
                            <tr key={b.booking_id}>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{i + 1}</td>
                              <td style={{ fontWeight: 500 }}>{b.name || "—"}</td>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{b.email}</td>
                              <td>
                                <span style={{
                                  background: "var(--ink)", color: "white", fontFamily: "'Syne',sans-serif",
                                  fontSize: 9, fontWeight: 700, padding: "2px 7px", borderRadius: 100,
                                  textTransform: "uppercase", letterSpacing: "0.04em",
                                }}>
                                  {b.tier}
                                </span>
                              </td>
                              <td style={{ color: "var(--muted)", fontSize: 12 }}>{fmtShort(b.created_at)}</td>
                              <td>{!isPast && <button className="btn-danger" disabled={removing !== null} onClick={() => void removeBooking(b, g)}>{removing === b.booking_id ? "Removing…" : "Remove"}</button>}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
