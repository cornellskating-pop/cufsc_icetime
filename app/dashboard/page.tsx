"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabaseClient";
import { Loading, Msg, SpotBar } from "../../lib/ui";

type Session = {
  id: string;
  start_time: string;
  end_time: string;
  release_at: string | null;
  capacity: number;
  label: string | null;
  spots_left: number;
};

type MyBooking = {
  booking_id: string;
  status: string;
  session_id: string;
  start_time: string;
  end_time: string;
};

type Profile = {
  email: string;
  name: string | null;
  tier: string | null;
  credits_balance: number;
  is_admin: boolean;
};

const RED = "var(--red)";
const BORDER = "var(--border)";
const MUTED = "var(--muted)";
const CREAM = "var(--cream)";
const INK = "var(--ink)";
const RED_LIGHT = "var(--red-light)";
const SUCCESS_BG = "var(--success-bg)";
const SUCCESS = "var(--success)";

function formatET(d: string) {
  return new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York",
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatETShort(d: string) {
  return new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function canCancelBooking(startTime: string) {
  const now = new Date();
  const start = new Date(startTime);
  return now.getTime() <= start.getTime() + 15 * 60 * 1000;
}

type SessionStatus = "open" | "grace" | "soon" | "full" | "closed" | "ended";

function getSessionStatus(s: Session): { status: SessionStatus; badgeLabel: string; subtext?: string } {
  const now = new Date();
  const start = new Date(s.start_time);
  const end = new Date(s.end_time);
  const release = s.release_at ? new Date(s.release_at) : null;

  if (now > end) return { status: "ended", badgeLabel: "Ended" };

  if (release && now < release) {
    const mins = Math.max(0, Math.ceil((release.getTime() - now.getTime()) / 60000));
    return {
      status: "soon",
      badgeLabel: mins < 60 ? `Opens in ${mins}m` : `Opens in ${Math.ceil(mins / 60)}h`,
    };
  }

  if (s.spots_left <= 0) return { status: "full", badgeLabel: "Full" };

  const minsLeft = (end.getTime() - now.getTime()) / 60000;
  const minsToStart = (start.getTime() - now.getTime()) / 60000;
  const inProgress = now >= start && now <= end;

  if (inProgress && minsLeft < 30) return { status: "closed", badgeLabel: "Closed" };

  if (minsToStart >= 0 && minsToStart <= 60) {
    return { status: "grace", badgeLabel: "Grace", subtext: "Last-hour: no credit deducted" };
  }

  return { status: "open", badgeLabel: "Open" };
}

function SessionRow({
  s,
  checked,
  disabled,
  onToggle,
}: {
  s: Session;
  checked: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  const { status, badgeLabel, subtext } = getSessionStatus(s);
  const isDisabled =
    disabled || status === "ended" || status === "full" || status === "closed" || status === "soon";

  return (
    <div
      onClick={() => !isDisabled && onToggle()}
      style={{
        padding: "13px 20px",
        borderBottom: `1px solid ${BORDER}`,
        display: "flex",
        alignItems: "center",
        gap: 12,
        cursor: isDisabled ? "not-allowed" : "pointer",
        background: checked ? RED_LIGHT : "white",
        opacity: status === "ended" || status === "full" ? 0.45 : 1,
        transition: "background .15s",
      }}
    >
      <div
        style={{
          width: 18,
          height: 18,
          border: `1.5px solid ${checked ? RED : BORDER}`,
          borderRadius: 5,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: checked ? RED : "white",
          transition: "all .15s",
        }}
      >
        {checked && (
          <svg
            width="10"
            height="10"
            viewBox="0 0 10 10"
            fill="none"
            stroke="white"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <polyline points="1.5,5 4,7.5 8.5,2.5" />
          </svg>
        )}
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 500, fontSize: 13, color: INK }}>
          {formatET(s.start_time)}
          <span style={{ color: MUTED }}>
            {" "}
            –{" "}
            {new Date(s.end_time).toLocaleString("en-US", {
              timeZone: "America/New_York",
              hour: "numeric",
              minute: "2-digit",
            })}
          </span>
        </div>
        <div style={{ fontSize: 11, color: MUTED, marginTop: 2 }}>
          {s.spots_left} spot{s.spots_left !== 1 ? "s" : ""} left
          {subtext && <span style={{ color: "#854D0E", marginLeft: 6 }}>· {subtext}</span>}
        </div>
        <SpotBar used={s.capacity - s.spots_left} cap={s.capacity} />
      </div>

      <span className={`badge badge-${status}`}>{badgeLabel}</span>
    </div>
  );
}

export default function Dashboard() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [myBookings, setMyBookings] = useState<MyBooking[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [showAll, setShowAll] = useState(false);
  const [loading, setLoading] = useState(true);
  const [booking, setBooking] = useState(false);
  const [msg, setMsg] = useState("");
  const [msgType, setMsgType] = useState<"success" | "error" | "info">("info");

  const refreshData = async (userId: string) => {
    const [{ data: sData }, { data: bData }, { data: uData }] = await Promise.all([
      supabase.from("sessions_with_spots").select("*").order("start_time", { ascending: true }),
      supabase.from("my_bookings").select("*").eq("status", "active").gte("start_time", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()).order("start_time", { ascending: false }),
      supabase.from("users").select("email, name, tier, credits_balance, is_admin").eq("id", userId).maybeSingle(),
    ]);

    setSessions((sData || []) as Session[]);
    setMyBookings((bData || []) as MyBooking[]);
    if (uData) setProfile(uData as Profile);
  };

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) {
        window.location.href = "/login";
        return;
      }
      refreshData(data.user.id).then(() => setLoading(false));
    });
  }, []);

  const [accessStatus, setAccessStatus] = useState<"idle"|"pending"|"requested"|"error">("idle");
  const [accessError, setAccessError] = useState("");

  const requestAccess = async () => {
    const { data, error } = await supabase.rpc("request_user_access");
    if (error) { setAccessError(error.message); setAccessStatus("error"); return; }
    setAccessStatus(data === "PENDING" ? "pending" : "requested");
  };

  useEffect(() => {
    if (!loading && !profile) {
      supabase.rpc("request_user_access").then(({ data }) => {
        if (data === "PENDING") setAccessStatus("pending");
      });
    }
  }, [loading, profile]);

  const credits = profile?.credits_balance ?? 0;
  const maxSelect = Math.min(2, Math.max(0, credits));

  const visibleSessions = useMemo(() => {
    const now = new Date();
    const upcoming = sessions.filter((s) => new Date(s.end_time) > now);
    return showAll ? upcoming : upcoming.slice(0, 5);
  }, [sessions, showAll]);

  const upcomingCount = useMemo(
    () => sessions.filter((s) => new Date(s.end_time) > new Date()).length,
    [sessions]
  );

  const toggle = (id: string) => {
    setMsg("");
    setSelected((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id);
      if (prev.length >= 2) {
        setMsg("You can select at most 2 sessions.");
        setMsgType("error");
        return prev;
      }
      if (prev.length >= maxSelect && credits > 0) {
        setMsg(`You only have ${credits} credit${credits !== 1 ? "s" : ""}.`);
        setMsgType("error");
        return prev;
      }
      return [...prev, id];
    });
  };

  const book = async () => {
    if (selected.length === 0) return;

    setBooking(true);
    setMsg("");

    const { data, error } = await supabase.rpc("book_sessions", { session_ids: selected });

    setBooking(false);

    if (error) {
      setMsg(error.message || "Booking failed.");
      setMsgType("error");
      return;
    }

    const results: any[] = Array.isArray(data) ? data : [];
    const allOk = results.every((r) => r.ok);

    setMsg(results.map((r) => `${r.ok ? "✓" : "✗"} ${r.message}`).join("  ·  "));
    setMsgType(allOk ? "success" : "error");
    setSelected([]);

    const { data: u } = await supabase.auth.getUser();
    if (u.user) await refreshData(u.user.id);
  };

  const cancel = async (bookingId: string, startTime: string) => {

    console.log('cancel bookingId:', bookingId);  
    
    if (!canCancelBooking(startTime)) {
      setMsg("This booking can no longer be cancelled because the session started more than 15 minutes ago.");
      setMsgType("error");
      return;
    }

    setMsg("");

    const { error } = await supabase.rpc("cancel_booking", {
      p_booking_id: bookingId,
    });

    if (error) {
      setMsg(error.message || "Cancellation failed.");
      setMsgType("error");
      return;
    }

    setMsg("Booking cancelled");
    setMsgType("success");

    const { data: u } = await supabase.auth.getUser();
    if (u.user) await refreshData(u.user.id);
  };

  const logout = async () => {
    await supabase.auth.signOut();
    window.location.href = "/login";
  };

  if (loading) return <Loading />;

  if (!profile) return (
    <div style={{ minHeight: "100vh", background: CREAM, display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ maxWidth: 400, width: "90%", textAlign: "center" }}>
        <div style={{ width: 48, height: 48, background: RED, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 20px" }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2L2 7l10 5 10-5-10-5z" /><path d="M2 17l10 5 10-5" /><path d="M2 12l10 5 10-5" />
          </svg>
        </div>
        <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, marginBottom: 8 }}>Not yet a member</div>
        <div style={{ fontSize: 13, color: MUTED, marginBottom: 24 }}>
          Your account isn't in the system yet. Request access and an admin will approve you.
        </div>
        {accessStatus === "requested" && (
          <div style={{ background: SUCCESS_BG, color: SUCCESS, borderRadius: 8, padding: "10px 16px", fontSize: 13, marginBottom: 16 }}>
            Request submitted — you'll be added once an admin approves it.
          </div>
        )}
        {accessStatus === "pending" && (
          <div style={{ background: "var(--warn-bg, #fefce8)", color: "#854D0E", borderRadius: 8, padding: "10px 16px", fontSize: 13, marginBottom: 16 }}>
            Your request is already pending — an admin will review it soon.
          </div>
        )}
        {accessStatus === "error" && (
          <div style={{ background: RED_LIGHT, color: RED, borderRadius: 8, padding: "10px 16px", fontSize: 13, marginBottom: 16 }}>
            {accessError || "Something went wrong. Please try again."}
          </div>
        )}
        {accessStatus === "idle" && (
          <button className="btn-primary" style={{ width: "100%" }} onClick={requestAccess}>
            Request Access
          </button>
        )}
        <button className="btn-ghost" style={{ marginTop: 10, width: "100%", fontSize: 12 }} onClick={logout}>
          Sign out
        </button>
      </div>
    </div>
  );

  return (
    <div style={{ background: CREAM, minHeight: "100vh" }}>
      <nav
        style={{
          background: "white",
          borderBottom: `1px solid ${BORDER}`,
          padding: "0 28px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          height: 60,
          position: "sticky",
          top: 0,
          zIndex: 50,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div
            style={{
              width: 30,
              height: 30,
              background: RED,
              borderRadius: 6,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="white"
              strokeWidth="2.2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M12 2L2 7l10 5 10-5-10-5z" />
              <path d="M2 17l10 5 10-5" />
              <path d="M2 12l10 5 10-5" />
            </svg>
          </div>
          <span
            style={{
              fontFamily: "'Syne',sans-serif",
              fontWeight: 800,
              fontSize: 15,
              letterSpacing: "-0.02em",
            }}
          >
            CUFSC <span style={{ color: RED }}>Ice Time</span>
          </span>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          {profile?.is_admin && (
            <a
              href="/admin"
              style={{ fontSize: 12, fontWeight: 600, color: MUTED, textDecoration: "none" }}
            >
              Admin ↗
            </a>
          )}
          <span style={{ fontSize: 12, color: MUTED }}>{profile?.email}</span>
          <span
            style={{
              background: RED_LIGHT,
              color: RED,
              fontFamily: "'Syne',sans-serif",
              fontWeight: 700,
              fontSize: 11,
              padding: "4px 12px",
              borderRadius: 100,
            }}
          >
            {credits} {credits === 1 ? "Credit" : "Credits"}
          </span>
          <button className="btn-ghost" style={{ padding: "6px 12px", fontSize: 12 }} onClick={logout}>
            Sign out
          </button>
        </div>
      </nav>

      <div
        style={{
          background: "var(--ink)",
          padding: "40px 28px",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            right: -80,
            top: -80,
            width: 400,
            height: 400,
            background: "radial-gradient(circle, rgba(179,27,27,0.22) 0%, transparent 70%)",
            pointerEvents: "none",
          }}
        />
        <div style={{ maxWidth: 900, margin: "0 auto", position: "relative", zIndex: 1 }}>
          <div
            style={{
              fontSize: 10,
              fontWeight: 600,
              letterSpacing: "0.14em",
              textTransform: "uppercase",
              color: "var(--ice-mid)",
              marginBottom: 10,
            }}
          >
            Cornell University Figure Skating Club
          </div>
          <div
            style={{
              fontFamily: "'Syne',sans-serif",
              fontWeight: 800,
              fontSize: "clamp(28px,4vw,44px)",
              lineHeight: 1.05,
              letterSpacing: "-0.03em",
              color: "white",
              marginBottom: 10,
            }}
          >
            Book Your
            <br />
            <span style={{ color: RED }}>Ice Time</span>
          </div>
          <div style={{ fontSize: 13, color: "#999", fontWeight: 300, marginBottom: 28, maxWidth: 420 }}>
            Select up to 2 sessions. Credits deducted at booking and refunded if cancelled ≥ 30 min before start.
          </div>
          <div style={{ display: "flex", gap: 32, flexWrap: "wrap" }}>
            {[
              [String(credits), "Credits Left"],
              [profile?.tier ?? "—", "Tier"],
              [String(myBookings.length), "Active Bookings"],
            ].map(([n, l]) => (
              <div key={l} style={{ borderLeft: `2px solid ${RED}`, paddingLeft: 14 }}>
                <div
                  style={{
                    fontFamily: "'Syne',sans-serif",
                    fontSize: 24,
                    fontWeight: 800,
                    color: "white",
                    lineHeight: 1,
                  }}
                >
                  {n}
                </div>
                <div style={{ fontSize: 11, color: "#888", marginTop: 3 }}>{l}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div
        className="dashboard-grid"
        style={{
          maxWidth: 900,
          margin: "0 auto",
          padding: "28px 24px 80px",
          display: "grid",
          gridTemplateColumns: "1fr 300px",
          gap: 24,
          alignItems: "start",
        }}
      >
        <div>
          <div className="section-label">Available Sessions</div>
          <div className="card">
            <div className="card-header">
              <span style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14 }}>
                This Week
              </span>
              <span style={{ fontSize: 12, color: MUTED }}>Select up to 2</span>
            </div>

            {visibleSessions.length === 0 && (
              <div style={{ padding: "24px 20px", color: MUTED, fontSize: 13 }}>No upcoming sessions.</div>
            )}

            {visibleSessions.map((s) => (
              <SessionRow
                key={s.id}
                s={s}
                checked={selected.includes(s.id)}
                disabled={!selected.includes(s.id) && selected.length >= 2}
                onToggle={() => toggle(s.id)}
              />
            ))}

            {upcomingCount > 5 && (
              <div style={{ display: "flex", borderTop: `1px solid ${BORDER}` }}>
                <button
                  onClick={() => setShowAll((v) => !v)}
                  style={{
                    flex: 1,
                    padding: 11,
                    background: "none",
                    border: "none",
                    color: RED,
                    fontSize: 13,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  {showAll ? "Show less ↑" : `Show ${upcomingCount - 5} more ↓`}
                </button>
              </div>
            )}

            <div style={{ padding: "14px 20px", background: CREAM, borderTop: `1px solid ${BORDER}` }}>
              {msg && <Msg text={msg} type={msgType} />}
              <button
                className="btn-primary"
                style={{
                  width: "100%",
                  marginTop: msg ? 10 : 0,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: 8,
                }}
                disabled={selected.length === 0 || booking}
                onClick={book}
              >
                {booking ? "Booking…" : `Book Selected (${selected.length}/2)`}
              </button>
            </div>
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div className="card" style={{ padding: 18 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
              <div
                style={{
                  width: 38,
                  height: 38,
                  borderRadius: "50%",
                  background: RED,
                  color: "white",
                  fontFamily: "'Syne',sans-serif",
                  fontWeight: 800,
                  fontSize: 16,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                {(profile?.name || profile?.email || "?")[0].toUpperCase()}
              </div>
              <div>
                <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14 }}>
                  {profile?.name || "Member"}
                </div>
                <div style={{ fontSize: 11, color: MUTED }}>{profile?.email}</div>
              </div>
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                paddingTop: 12,
                borderTop: `1px solid ${BORDER}`,
                marginBottom: 12,
              }}
            >
              <span
                style={{
                  fontSize: 10,
                  textTransform: "uppercase",
                  letterSpacing: "0.08em",
                  color: MUTED,
                }}
              >
                Tier
              </span>
              <span
                style={{
                  background: "var(--ink)",
                  color: "white",
                  fontFamily: "'Syne',sans-serif",
                  fontSize: 10,
                  fontWeight: 700,
                  padding: "3px 10px",
                  borderRadius: 100,
                  textTransform: "uppercase",
                  letterSpacing: "0.04em",
                }}
              >
                {profile?.tier ?? "—"}
              </span>
            </div>

            <div
              style={{
                fontSize: 11,
                color: MUTED,
                display: "flex",
                justifyContent: "space-between",
                marginBottom: 6,
              }}
            >
              <span>Credits remaining</span>
              <strong style={{ color: INK }}>{credits}</strong>
            </div>
            <div style={{ height: 6, background: BORDER, borderRadius: 100, overflow: "hidden" }}>
              <div
                style={{
                  width: `${Math.min(100, credits * 20)}%`,
                  height: "100%",
                  background: `linear-gradient(90deg, var(--red-dark), ${RED})`,
                  borderRadius: 100,
                }}
              />
            </div>
          </div>

          <div>
            <div className="section-label">My Bookings</div>
            <div className="card">
              {myBookings.length === 0 ? (
                <div style={{ padding: "20px 16px", color: MUTED, fontSize: 13 }}>No active bookings.</div>
              ) : (
                myBookings.map((b, i) => {
                  const canCancel = canCancelBooking(b.start_time);

                  return (
                    <div
                      key={b.booking_id}
                      style={{
                        padding: "12px 16px",
                        borderBottom: i < myBookings.length - 1 ? `1px solid ${BORDER}` : "none",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        gap: 10,
                      }}
                    >
                      <div>
                        <div style={{ fontSize: 13, fontWeight: 500, color: INK }}>
                          {formatETShort(b.start_time)}
                        </div>
                        <div style={{ fontSize: 11, color: MUTED, marginTop: 1 }}>
                          ends{" "}
                          {new Date(b.end_time).toLocaleString("en-US", {
                            timeZone: "America/New_York",
                            hour: "numeric",
                            minute: "2-digit",
                          })}
                        </div>
                        {!canCancel && (
                          <div style={{ fontSize: 11, color: MUTED, marginTop: 4 }}>
                            Cancellation window closed
                          </div>
                        )}
                      </div>

                      <button
                        className="btn-danger"
                        onClick={() => cancel(b.booking_id, b.start_time)}
                        disabled={!canCancel}
                        style={{
                          opacity: canCancel ? 1 : 0.5,
                          cursor: canCancel ? "pointer" : "not-allowed",
                        }}
                      >
                        Cancel
                      </button>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      </div>

      <style>{`
        @media (max-width: 680px) {
          .dashboard-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>
    </div>
  );
}