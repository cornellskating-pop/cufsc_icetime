"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabaseClient";
import { Loading, LogoMark, Msg, SpotBar } from "../../lib/ui";

type Session = {
  id: string;
  start_time: string;
  end_time: string;
  release_at: string | null;
  capacity: number;
  label?: string | null;
  notes?: string | null;
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

type BookingResult = {
  ok: boolean;
  message: string;
  session_id?: string;
};

type CalendarMonth = {
  year: number;
  month: number;
};

const RED = "var(--red)";
const BORDER = "var(--border)";
const MUTED = "var(--muted)";
const CREAM = "var(--cream)";
const INK = "var(--ink)";
const RED_LIGHT = "var(--red-light)";
const SUCCESS_BG = "var(--success-bg)";
const SUCCESS = "var(--success)";
const ET_TIME_ZONE = "America/New_York";

const etDatePartsFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: ET_TIME_ZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric",
});

function getETDateParts(date: Date) {
  const parts = etDatePartsFormatter.formatToParts(date);
  const read = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((part) => part.type === type)?.value);

  return {
    year: read("year"),
    month: read("month"),
    day: read("day"),
  };
}

function getCurrentETMonth(): CalendarMonth {
  const { year, month } = getETDateParts(new Date());
  return { year, month };
}

function getETDateKey(date: Date | string) {
  const { year, month, day } = getETDateParts(typeof date === "string" ? new Date(date) : date);
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function shiftCalendarMonth(value: CalendarMonth, offset: number): CalendarMonth {
  const shifted = new Date(Date.UTC(value.year, value.month - 1 + offset, 1));
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1 };
}

function formatCalendarMonth(value: CalendarMonth) {
  return new Date(Date.UTC(value.year, value.month - 1, 1)).toLocaleString("en-US", {
    timeZone: "UTC",
    month: "long",
    year: "numeric",
  });
}

function formatCalendarTime(value: string) {
  return new Date(value).toLocaleString("en-US", {
    timeZone: ET_TIME_ZONE,
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatCountdownAmount(remainingMs: number) {
  if (remainingMs >= 48 * 60 * 60 * 1000) {
    return `${Math.ceil(remainingMs / (24 * 60 * 60 * 1000))}d`;
  }
  if (remainingMs >= 60 * 60 * 1000) {
    return `${Math.ceil(remainingMs / (60 * 60 * 1000))}h`;
  }
  return `${Math.max(1, Math.ceil(remainingMs / (60 * 1000)))}m`;
}

function formatAvailabilityCountdown(releaseAt: string | null, nowMs: number) {
  if (!releaseAt) return null;

  const remaining = new Date(releaseAt).getTime() - nowMs;
  if (remaining <= 0) return null;
  return `Opens in ${formatCountdownAmount(remaining)}`;
}

function formatElapsedAmount(elapsedMs: number) {
  const totalMinutes = Math.max(0, Math.floor(elapsedMs / (60 * 1000)));
  if (totalMinutes < 1) return "Just started";
  if (totalMinutes < 60) return `${totalMinutes}m`;

  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
}

type TimelinePhase = "upcoming" | "in-progress" | "ended";

function getSessionTimeline(
  session: Session,
  nowMs: number,
  upcomingSecondary?: string
): { phase: TimelinePhase; primary: string; secondary?: string } {
  const startMs = new Date(session.start_time).getTime();
  const endMs = new Date(session.end_time).getTime();

  if (nowMs < startMs) {
    return {
      phase: "upcoming",
      primary: `Starts in ${formatCountdownAmount(startMs - nowMs)}`,
      secondary: upcomingSecondary,
    };
  }

  if (nowMs <= endMs) {
    const elapsed = formatElapsedAmount(nowMs - startMs);
    return {
      phase: "in-progress",
      primary: elapsed === "Just started" ? elapsed : `${elapsed} into session`,
      secondary: `${formatCountdownAmount(endMs - nowMs)} remaining`,
    };
  }

  return {
    phase: "ended",
    primary: "Session over",
    secondary: `Ended ${formatCountdownAmount(nowMs - endMs)} ago`,
  };
}

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
  return now.getTime() <= start.getTime() + 30 * 60 * 1000;
}

type SessionStatus = "open" | "grace" | "soon" | "full" | "closed" | "ended";

function getSessionStatus(
  s: Session,
  now = new Date()
): { status: SessionStatus; badgeLabel: string; subtext?: string } {
  const start = new Date(s.start_time);
  const end = new Date(s.end_time);
  const release = s.release_at ? new Date(s.release_at) : null;

  if (now > end) return { status: "ended", badgeLabel: "Ended" };

  if (release && now < release) {
    return {
      status: "soon",
      badgeLabel: formatAvailabilityCountdown(s.release_at, now.getTime()) ?? "Opening soon",
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

function BookedSnowOverlay() {
  return (
    <span className="booked-snow-overlay" aria-hidden="true">
      <span>❄</span>
      <span>❅</span>
      <span>❆</span>
    </span>
  );
}

function isShowSession(session: Session) {
  return (session.label ?? session.notes)?.toLowerCase().includes("show") ?? false;
}

function isTryoutSession(session: Session) {
  return (session.label ?? session.notes)?.toLowerCase().includes("tryout") ?? false;
}

function isCompetitionTeamSession(session: Session) {
  return (session.label ?? session.notes)?.toLowerCase().includes("competition team") ?? false;
}

function TryoutMark() {
  return (
    <svg className="tryout-mark" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7 3.5v10.2c0 2.5 2 4.5 4.5 4.5h4.8" />
      <path d="M7 12.5h6.4l1.9 3.2H19" />
      <path d="M5 20c4.2 1.1 9.3 1.1 14.5-.4" />
      <path d="m17.8 3 .6 1.6L20 5.2l-1.6.6-.6 1.6-.6-1.6-1.6-.6 1.6-.6.6-1.6Z" />
    </svg>
  );
}

function TeamMark() {
  return (
    <svg className="team-mark" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 2.5 20 6v5.5c0 4.5-3 8.1-8 10-5-1.9-8-5.5-8-10V6l8-3.5Z" />
      <path d="m12 6.7 1.3 2.7 3 .4-2.2 2.1.6 3-2.7-1.4-2.7 1.4.6-3-2.2-2.1 3-.4L12 6.7Z" />
    </svg>
  );
}

function SessionRow({
  s,
  checked,
  booked,
  disabled,
  onToggle,
  nowMs,
}: {
  s: Session;
  checked: boolean;
  booked: boolean;
  disabled: boolean;
  onToggle: () => void;
  nowMs: number;
}) {
  const { status, badgeLabel, subtext } = getSessionStatus(s, new Date(nowMs));
  const showSession = isShowSession(s);
  const tryoutSession = isTryoutSession(s);
  const teamSession = isCompetitionTeamSession(s);
  const displayChecked = checked || booked;
  const isDisabled =
    booked || disabled || status === "ended" || status === "full" || status === "closed" || status === "soon";

  return (
    <div
      className={`session-row${booked ? " booked" : ""}${showSession ? " show-session" : ""}${tryoutSession ? " tryout-session" : ""}${teamSession ? " team-session" : ""}`}
      onClick={() => !isDisabled && onToggle()}
      style={{
        padding: "13px 20px",
        borderBottom: `1px solid ${BORDER}`,
        display: "flex",
        alignItems: "center",
        gap: 12,
        cursor: isDisabled ? "not-allowed" : "pointer",
        background: teamSession
          ? "linear-gradient(135deg, rgba(232,248,247,.98), rgba(231,239,255,.98))"
          : tryoutSession
          ? "linear-gradient(135deg, rgba(255,249,230,.98), rgba(255,239,238,.98))"
          : showSession
          ? "linear-gradient(135deg, rgba(240,252,255,.98), rgba(249,244,255,.98))"
          : booked
          ? "linear-gradient(135deg, rgba(237,246,248,.96), rgba(255,255,255,.96))"
          : checked ? RED_LIGHT : "white",
        opacity: teamSession ? 1 : status === "ended" || status === "full" ? 0.45 : 1,
        transition: "background .15s",
      }}
    >
      <div
        style={{
          width: 18,
          height: 18,
          border: `1.5px solid ${displayChecked ? RED : BORDER}`,
          borderRadius: 5,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: displayChecked ? RED : "white",
          transition: "all .15s",
        }}
      >
        {displayChecked && (
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

      <span className="session-badges">
        {teamSession && <span className="badge badge-team"><TeamMark />Competition Team</span>}
        {tryoutSession && <span className="badge badge-tryout"><TryoutMark />Tryouts</span>}
        {showSession && <span className="badge badge-show">Show</span>}
        <span className={`badge badge-${booked ? "active" : status}`}>
          {booked ? "Booked" : badgeLabel}
        </span>
      </span>
      {booked && <BookedSnowOverlay />}
    </div>
  );
}

function CalendarView({
  sessions,
  month,
  selected,
  bookedSessionIds,
  nowMs,
  onMonthChange,
  onToggle,
}: {
  sessions: Session[];
  month: CalendarMonth;
  selected: string[];
  bookedSessionIds: ReadonlySet<string>;
  nowMs: number;
  onMonthChange: (offset: number) => void;
  onToggle: (id: string) => void;
}) {
  const sessionsByDay = useMemo(() => {
    const grouped = new Map<string, Session[]>();
    sessions.forEach((session) => {
      const key = getETDateKey(session.start_time);
      grouped.set(key, [...(grouped.get(key) ?? []), session]);
    });
    return grouped;
  }, [sessions]);

  const days = useMemo(() => {
    const firstWeekday = new Date(Date.UTC(month.year, month.month - 1, 1)).getUTCDay();
    const daysInMonth = new Date(Date.UTC(month.year, month.month, 0)).getUTCDate();
    const cellCount = Math.ceil((firstWeekday + daysInMonth) / 7) * 7;

    return Array.from({ length: cellCount }, (_, index) => {
      const date = new Date(Date.UTC(month.year, month.month - 1, index - firstWeekday + 1));
      const year = date.getUTCFullYear();
      const calendarMonth = date.getUTCMonth() + 1;
      const day = date.getUTCDate();

      return {
        year,
        month: calendarMonth,
        day,
        key: `${year}-${String(calendarMonth).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
        isCurrentMonth: calendarMonth === month.month && year === month.year,
      };
    });
  }, [month]);

  const todayKey = getETDateKey(new Date(nowMs));

  return (
    <>
      <div className="calendar-toolbar">
        <button
          type="button"
          className="calendar-nav-button"
          aria-label="Previous month"
          onClick={() => onMonthChange(-1)}
        >
          ←
        </button>
        <div>
          <div className="calendar-month-title">{formatCalendarMonth(month)}</div>
          <div className="calendar-timezone">Times shown in ET</div>
        </div>
        <button
          type="button"
          className="calendar-nav-button"
          aria-label="Next month"
          onClick={() => onMonthChange(1)}
        >
          →
        </button>
      </div>

      <div className="calendar-scroll">
        <div className="calendar-grid" role="grid" aria-label={`${formatCalendarMonth(month)} sessions`}>
          {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((weekday) => (
            <div className="calendar-weekday" role="columnheader" key={weekday}>
              {weekday}
            </div>
          ))}

          {days.map((day) => {
            const daySessions = sessionsByDay.get(day.key) ?? [];

            return (
              <div
                className={`calendar-day${day.isCurrentMonth ? "" : " outside"}${day.key === todayKey ? " today" : ""}`}
                role="gridcell"
                key={day.key}
              >
                <div className="calendar-day-number">{day.day}</div>
                <div className="calendar-day-sessions">
                  {daySessions.map((session) => {
                    const { status } = getSessionStatus(session, new Date(nowMs));
                    const checked = selected.includes(session.id);
                    const booked = bookedSessionIds.has(session.id);
                    const showSession = isShowSession(session);
                    const tryoutSession = isTryoutSession(session);
                    const teamSession = isCompetitionTeamSession(session);
                    const locked = status === "soon";
                    const unavailable =
                      status === "ended" || status === "full" || status === "closed";
                    const selectionBlocked = !checked && selected.length >= 2;
                    const disabled = booked || locked || unavailable || selectionBlocked;
                    const countdown = formatAvailabilityCountdown(session.release_at, nowMs);
                    const availabilityText = countdown
                      ? countdown
                      : status === "full"
                        ? "Full"
                        : status === "ended"
                          ? "Ended"
                          : status === "closed"
                            ? "Closed"
                            : `${session.spots_left} left`;
                    const timeline = getSessionTimeline(
                      session,
                      nowMs,
                      booked ? "Booked" : availabilityText
                    );

                    return (
                      <button
                        type="button"
                        className={`calendar-session-block status-${status} timeline-${timeline.phase}${checked ? " selected" : ""}${booked ? " booked" : ""}${showSession ? " show-session" : ""}${tryoutSession ? " tryout-session" : ""}${teamSession ? " team-session" : ""}`}
                        disabled={disabled}
                        onClick={() => onToggle(session.id)}
                        title={`${session.label || session.notes || "Ice session"} · ${formatET(session.start_time)} · ${timeline.primary}${timeline.secondary ? ` · ${timeline.secondary}` : ""}`}
                        aria-pressed={checked || booked}
                        key={session.id}
                      >
                        <span className="calendar-check" aria-hidden="true">
                          {checked || booked || timeline.phase === "ended" ? "✓" : ""}
                        </span>
                        <span className="calendar-session-copy">
                          <span className="calendar-session-time">
                            {teamSession && <span className="calendar-team-label"><TeamMark />Team</span>}
                            {tryoutSession && <span className="calendar-tryout-label"><TryoutMark />Tryouts</span>}
                            {showSession && <span className="calendar-show-label">Show</span>}
                            {formatCalendarTime(session.start_time)}
                          </span>
                          <span className="calendar-session-status timeline-primary">{timeline.primary}</span>
                          {timeline.secondary && (
                            <span className="calendar-session-meta">{timeline.secondary}</span>
                          )}
                        </span>
                        {booked && <BookedSnowOverlay />}
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </>
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
  const [viewMode, setViewMode] = useState<"calendar" | "list">("calendar");
  const [calendarMonth, setCalendarMonth] = useState<CalendarMonth>(getCurrentETMonth);
  const [nowMs, setNowMs] = useState(() => Date.now());

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

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30 * 1000);
    return () => window.clearInterval(timer);
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
    const now = new Date(nowMs);
    const upcoming = sessions.filter((s) => new Date(s.end_time) > now);
    return showAll ? upcoming : upcoming.slice(0, 5);
  }, [sessions, showAll, nowMs]);

  const upcomingCount = useMemo(
    () => sessions.filter((s) => new Date(s.end_time).getTime() > nowMs).length,
    [sessions, nowMs]
  );

  const bookedSessionIds = useMemo(
    () => new Set(myBookings.map((booking) => booking.session_id)),
    [myBookings]
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

    const results: BookingResult[] = Array.isArray(data) ? data as BookingResult[] : [];
    const allOk = results.every((r) => r.ok);

    setMsg(results.map((r) => `${r.ok ? "✓" : "✗"} ${r.message}`).join("  ·  "));
    setMsgType(allOk ? "success" : "error");
    setSelected([]);

    const { data: u } = await supabase.auth.getUser();
    if (u.user) await refreshData(u.user.id);
  };

  const cancel = async (bookingId: string, startTime: string) => {
    if (!canCancelBooking(startTime)) {
      setMsg("This booking can no longer be cancelled because the session started more than 30 minutes ago.");
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
        <div style={{ display: "flex", justifyContent: "center", marginBottom: 20 }}>
          <LogoMark size={58} />
        </div>
        <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: 22, marginBottom: 8 }}>Not yet a member</div>
        <div style={{ fontSize: 13, color: MUTED, marginBottom: 24 }}>
          Your account isn&apos;t in the system yet. Request access and an admin will approve you.
        </div>
        {accessStatus === "requested" && (
          <div style={{ background: SUCCESS_BG, color: SUCCESS, borderRadius: 8, padding: "10px 16px", fontSize: 13, marginBottom: 16 }}>
            Request submitted — you&apos;ll be added once an admin approves it.
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
    <div style={{ background: "transparent", minHeight: "100vh" }}>
      <nav
        style={{
          background: "rgba(250,248,245,.94)",
          borderBottom: `1px solid ${BORDER}`,
          padding: "0 28px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          height: 68,
          position: "sticky",
          top: 0,
          zIndex: 50,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <LogoMark size={42} />
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

        <div className="dashboard-nav-actions" style={{ display: "flex", alignItems: "center", gap: 14 }}>
          {profile?.is_admin && (
            <a
              href="/admin"
              style={{ fontSize: 12, fontWeight: 600, color: MUTED, textDecoration: "none" }}
            >
              Admin ↗
            </a>
          )}
          <span className="dashboard-nav-email" style={{ fontSize: 12, color: MUTED }}>{profile?.email}</span>
          <button className="btn-ghost" style={{ padding: "6px 12px", fontSize: 12 }} onClick={logout}>
            Sign out
          </button>
        </div>
      </nav>

      <div className="dashboard-hero-shell" style={{ padding: "30px 28px 0" }}>
        <div
          className="dashboard-hero"
          style={{
            maxWidth: 1100,
            margin: "0 auto",
            display: "grid",
            gridTemplateColumns: "450px minmax(0, 1fr)",
            gap: 40,
            alignItems: "start",
          }}
        >
          <div>
            <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: "0.14em", textTransform: "uppercase", color: MUTED, marginBottom: 10 }}>
              Cornell University Figure Skating Club
            </div>
            <div className="dashboard-title" style={{ fontFamily: "'Syne',sans-serif", fontWeight: 800, fontSize: "clamp(30px,3.5vw,42px)", lineHeight: 1.04, letterSpacing: "-0.04em", color: INK }}>
              Book your ice time <span style={{ color: RED }}>here.</span>
            </div>
            <div className="venmo-credit-info">
              Venmo: @CUFSC <span>· $15/credit · Include your Cornell email</span>
            </div>
          </div>

          <ul className="booking-rules">
            <li>One session per credit.</li>
            <li>You can select and book up to two sessions at a time.</li>
            <li>Charged credits are refunded when cancelled at least 30 minutes before start.</li>
            <li>
              During the final 60 minutes before start, a released session with space can be booked
              without using a credit. Temporary accounts without credits require approval.
            </li>
            <li>Booking closes at the session start; cancellation closes 30 minutes after start.</li>
          </ul>
        </div>
      </div>

      <div
        className="dashboard-grid"
        style={{
          maxWidth: 1100,
          margin: "0 auto",
          padding: "18px 0 80px",
          display: "grid",
          gridTemplateColumns: "minmax(0, 1fr) 300px",
          gap: 24,
          alignItems: "start",
        }}
      >
        <div>
          <div className="section-label">Available Sessions</div>
          <div className="card">
            <div className="card-header session-card-header">
              <span style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14 }}>
                {viewMode === "calendar" ? "Monthly Calendar" : "Session List"}
              </span>
              <div className="session-view-actions">
                <span className="session-select-hint" style={{ fontSize: 12, color: MUTED }}>Select up to 2</span>
                <div className="session-view-toggle" aria-label="Session view">
                  <button
                    type="button"
                    className={viewMode === "calendar" ? "active" : ""}
                    aria-pressed={viewMode === "calendar"}
                    onClick={() => setViewMode("calendar")}
                  >
                    Calendar
                  </button>
                  <button
                    type="button"
                    className={viewMode === "list" ? "active" : ""}
                    aria-pressed={viewMode === "list"}
                    onClick={() => setViewMode("list")}
                  >
                    List
                  </button>
                </div>
              </div>
            </div>

            {viewMode === "calendar" ? (
              <CalendarView
                sessions={sessions}
                month={calendarMonth}
                selected={selected}
                bookedSessionIds={bookedSessionIds}
                nowMs={nowMs}
                onMonthChange={(offset) => setCalendarMonth((current) => shiftCalendarMonth(current, offset))}
                onToggle={toggle}
              />
            ) : (
              <>
                {visibleSessions.length === 0 && (
                  <div style={{ padding: "24px 20px", color: MUTED, fontSize: 13 }}>No upcoming sessions.</div>
                )}

                {visibleSessions.map((s) => (
                  <SessionRow
                    key={s.id}
                    s={s}
                    checked={selected.includes(s.id)}
                    booked={bookedSessionIds.has(s.id)}
                    disabled={!selected.includes(s.id) && selected.length >= 2}
                    onToggle={() => toggle(s.id)}
                    nowMs={nowMs}
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
              </>
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
          <div>
            <div className="section-label dashboard-profile-spacer" aria-hidden="true">&nbsp;</div>
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
                    width: `${Math.min(100, Math.max(0, (credits / 2) * 100))}%`,
                    height: "100%",
                    background: `linear-gradient(90deg, var(--red-dark), ${RED})`,
                    borderRadius: 100,
                  }}
                />
              </div>
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
        .session-view-actions {
          display: flex;
          align-items: center;
          gap: 12px;
        }
        .booking-rules {
          min-width: 0;
          margin: 0;
          padding-left: 18px;
          display: flex;
          flex-direction: column;
          gap: 6px;
          color: ${MUTED};
          font-size: 10.5px;
          line-height: 1.35;
        }
        .booking-rules li::marker {
          color: ${RED};
        }
        .dashboard-title {
          white-space: nowrap;
        }
        .venmo-credit-info {
          width: fit-content;
          margin-top: 10px;
          padding: 5px 10px;
          display: flex;
          align-items: center;
          gap: 6px;
          border: 1px solid rgba(207, 47, 47, .22);
          border-radius: 999px;
          background: rgba(207, 47, 47, .06);
          color: ${RED};
          font-size: 11px;
          font-weight: 700;
          line-height: 1.2;
        }
        .venmo-credit-info span {
          color: ${INK};
          font-weight: 600;
        }
        .session-view-toggle {
          display: flex;
          padding: 3px;
          border: 1px solid ${BORDER};
          border-radius: 10px;
          background: ${CREAM};
        }
        .session-view-toggle button {
          border: 0;
          border-radius: 7px;
          padding: 6px 9px;
          background: transparent;
          color: ${MUTED};
          font-family: 'DM Sans', sans-serif;
          font-size: 11px;
          font-weight: 600;
          cursor: pointer;
        }
        .session-view-toggle button.active {
          background: white;
          color: ${RED};
          box-shadow: 0 2px 6px rgba(45,36,34,.09);
        }
        .session-row {
          position: relative;
          overflow: hidden;
        }
        .session-row.booked {
          box-shadow: inset 4px 0 0 var(--ice-mid);
        }
        .session-row.show-session {
          outline: 1.5px solid transparent;
          outline-offset: -2px;
          box-shadow:
            inset 4px 0 0 #67C9DA,
            inset -2px 0 0 #A58BE8,
            0 0 10px rgba(126, 143, 229, .2);
          animation: showRowGlow 2.8s ease-in-out infinite;
        }
        .session-row.tryout-session {
          outline: 1.5px solid transparent;
          outline-offset: -2px;
          box-shadow:
            inset 4px 0 0 #E6A736,
            inset -2px 0 0 #D86878,
            0 0 12px rgba(216, 104, 120, .18);
        }
        .session-row.team-session {
          outline: 1.5px solid transparent;
          outline-offset: -2px;
          box-shadow:
            inset 4px 0 0 #2A9D8F,
            inset -2px 0 0 #5271C4,
            0 0 12px rgba(42, 157, 143, .18);
        }
        .session-badges {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          gap: 5px;
          flex-wrap: wrap;
          justify-content: flex-end;
        }
        .badge-show {
          border: 1px solid rgba(126, 106, 218, .34);
          background: linear-gradient(120deg, #DDF7FB, #E8E1FF, #F3DDF8);
          color: #6250A4;
          box-shadow: 0 0 8px rgba(126, 143, 229, .2);
        }
        .badge-tryout {
          border: 1px solid rgba(191, 120, 28, .36);
          display: inline-flex;
          align-items: center;
          gap: 3px;
          background: linear-gradient(120deg, #FFF0B8, #FFDADD);
          color: #8B3C3C;
          box-shadow: 0 0 8px rgba(224, 151, 45, .2);
        }
        .badge-team {
          border: 1px solid rgba(37, 120, 135, .34);
          display: inline-flex;
          align-items: center;
          gap: 3px;
          background: linear-gradient(120deg, #D7F4EF, #DDE6FF);
          color: #245B72;
          box-shadow: 0 0 8px rgba(42, 157, 143, .2);
        }
        .tryout-mark {
          width: 14px;
          height: 14px;
          fill: none;
          stroke: currentColor;
          stroke-width: 1.7;
          stroke-linecap: round;
          stroke-linejoin: round;
          flex: 0 0 auto;
        }
        .team-mark {
          width: 14px;
          height: 14px;
          fill: none;
          stroke: currentColor;
          stroke-width: 1.6;
          stroke-linecap: round;
          stroke-linejoin: round;
          flex: 0 0 auto;
        }
        .session-row > :not(.booked-snow-overlay),
        .calendar-session-block > :not(.booked-snow-overlay) {
          position: relative;
          z-index: 1;
        }
        .booked-snow-overlay {
          position: absolute;
          inset: 0;
          z-index: 0;
          display: flex;
          align-items: center;
          justify-content: space-around;
          color: var(--ice-mid);
          opacity: .22;
          overflow: hidden;
          pointer-events: none;
          transform: rotate(-7deg) scale(1.08);
        }
        .booked-snow-overlay span:nth-child(1) { font-size: 18px; transform: translateY(8px); }
        .booked-snow-overlay span:nth-child(2) { font-size: 28px; transform: translateY(-6px); }
        .booked-snow-overlay span:nth-child(3) { font-size: 21px; transform: translateY(7px); }
        .calendar-toolbar {
          min-height: 72px;
          padding: 14px 18px;
          border-bottom: 1px solid ${BORDER};
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          text-align: center;
          background: rgba(247,244,240,.58);
        }
        .calendar-month-title {
          font-family: 'Syne', sans-serif;
          font-size: 17px;
          font-weight: 800;
          color: ${INK};
        }
        .calendar-timezone {
          margin-top: 2px;
          color: ${MUTED};
          font-size: 10px;
        }
        .calendar-nav-button {
          width: 34px;
          height: 34px;
          border: 1px solid ${BORDER};
          border-radius: 10px;
          background: white;
          color: ${INK};
          font-size: 16px;
          cursor: pointer;
        }
        .calendar-nav-button:hover {
          border-color: ${RED};
          color: ${RED};
        }
        .calendar-scroll {
          width: 100%;
          overflow: hidden;
        }
        .calendar-grid {
          display: grid;
          grid-template-columns: repeat(7, minmax(0, 1fr));
          background: ${BORDER};
          gap: 1px;
        }
        .calendar-weekday {
          padding: 8px 3px;
          background: ${CREAM};
          color: ${MUTED};
          font-size: 9px;
          font-weight: 700;
          letter-spacing: .07em;
          text-align: center;
          text-transform: uppercase;
        }
        .calendar-day {
          min-width: 0;
          min-height: 92px;
          padding: 7px 5px;
          background: rgba(255,255,255,.96);
        }
        .calendar-day.outside {
          background: rgba(247,244,240,.72);
        }
        .calendar-day.outside .calendar-day-number {
          opacity: .34;
        }
        .calendar-day.today {
          box-shadow: inset 0 0 0 2px rgba(179,27,27,.24);
        }
        .calendar-day-number {
          margin: 0 2px 6px;
          color: ${MUTED};
          font-size: 10px;
          font-weight: 600;
        }
        .calendar-day.today .calendar-day-number {
          color: ${RED};
          font-weight: 800;
        }
        .calendar-day-sessions {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .calendar-session-block {
          position: relative;
          overflow: hidden;
          width: 100%;
          min-width: 0;
          border: 1px solid rgba(179,27,27,.26);
          border-radius: 7px;
          padding: 5px;
          display: flex;
          align-items: flex-start;
          gap: 4px;
          background: ${RED_LIGHT};
          color: ${RED};
          font-family: 'DM Sans', sans-serif;
          text-align: left;
          cursor: pointer;
          transition: background .15s, border-color .15s, color .15s;
        }
        .calendar-session-block:hover:not(:disabled) {
          border-color: ${RED};
        }
        .calendar-session-block.status-grace {
          border-color: #E5C85B;
          background: #FEF9C3;
          color: #854D0E;
        }
        .calendar-session-block.status-soon,
        .calendar-session-block.status-full,
        .calendar-session-block.status-closed,
        .calendar-session-block.status-ended {
          border-color: #D5D0CC;
          background: #EAE7E3;
          color: #77706C;
          cursor: not-allowed;
          filter: saturate(.45);
        }
        .calendar-session-block.timeline-in-progress {
          border-color: var(--ice-mid);
          background: var(--ice);
          color: #2F6F7A;
          box-shadow: inset 3px 0 0 var(--ice-mid);
          filter: none;
        }
        .calendar-session-block.timeline-ended {
          border-color: #D1CCC8;
          background: #E4E0DC;
          color: #69635F;
          opacity: .78;
        }
        .calendar-session-block.selected {
          border-color: ${RED};
          background: ${RED};
          color: white;
          filter: none;
        }
        .calendar-session-block.booked {
          border-color: var(--ice-mid);
          background: linear-gradient(135deg, var(--ice), #FFFFFF);
          color: #2F6F7A;
          box-shadow: inset 3px 0 0 var(--ice-mid);
          cursor: not-allowed;
          filter: none;
          opacity: 1;
        }
        .calendar-session-block.booked.timeline-ended {
          filter: saturate(.55);
          opacity: .72;
        }
        .calendar-session-block.show-session {
          border: 1.5px solid transparent;
          background:
            linear-gradient(135deg, rgba(241,252,254,.98), rgba(250,245,255,.98)) padding-box,
            linear-gradient(120deg, #64CBDB, #8588E8, #C287E4, #64CBDB) border-box;
          background-size: 100% 100%, 200% 200%;
          color: #6250A4;
          box-shadow:
            0 0 0 1px rgba(104, 202, 219, .14),
            0 0 10px rgba(135, 121, 226, .3);
          filter: none;
          opacity: 1;
          animation: showSessionGlow 2.8s ease-in-out infinite;
        }
        .calendar-session-block.show-session.selected {
          background:
            linear-gradient(135deg, #617FC7, #8567C7) padding-box,
            linear-gradient(120deg, #7CE1EA, #BBA2FF, #F0A9EC, #7CE1EA) border-box;
          color: white;
        }
        .calendar-session-block.tryout-session {
          border: 1.5px solid transparent;
          background:
            linear-gradient(135deg, #FFF9E4, #FFECEF) padding-box,
            linear-gradient(120deg, #E7AE3D, #D86878, #E7AE3D) border-box;
          color: #823B3B;
          box-shadow: 0 0 10px rgba(216, 104, 120, .2);
          filter: none;
          opacity: 1;
        }
        .calendar-session-block.tryout-session.selected {
          background:
            linear-gradient(135deg, #B65B44, #A43F61) padding-box,
            linear-gradient(120deg, #FFE49A, #FFB8C4, #FFE49A) border-box;
          color: white;
        }
        .calendar-session-block.team-session {
          border: 1.5px solid transparent;
          background:
            linear-gradient(135deg, #E8F8F7, #E7EFFF) padding-box,
            linear-gradient(120deg, #2A9D8F, #5271C4, #2A9D8F) border-box;
          color: #245B72;
          box-shadow: 0 0 10px rgba(42, 157, 143, .22);
          filter: none;
          opacity: 1;
        }
        .calendar-show-label {
          margin-right: 3px;
          border-radius: 3px;
          padding: 1px 3px;
          display: inline-flex;
          background: linear-gradient(120deg, #CFF4F8, #E5D9FF);
          color: #6250A4;
          font-size: 6px;
          font-weight: 800;
          letter-spacing: .04em;
          line-height: 1.2;
          text-transform: uppercase;
          vertical-align: 1px;
        }
        .calendar-tryout-label {
          margin-right: 3px;
          border-radius: 3px;
          padding: 1px 3px;
          display: inline-flex;
          align-items: center;
          gap: 2px;
          background: linear-gradient(120deg, #FFE9A4, #FFD1D8);
          color: #823B3B;
          font-size: 6px;
          font-weight: 800;
          letter-spacing: .04em;
          line-height: 1.2;
          text-transform: uppercase;
          vertical-align: 1px;
        }
        .calendar-tryout-label .tryout-mark {
          width: 8px;
          height: 8px;
        }
        .calendar-team-label {
          margin-right: 3px;
          border-radius: 3px;
          padding: 1px 3px;
          display: inline-flex;
          align-items: center;
          gap: 2px;
          background: linear-gradient(120deg, #CFF1EB, #D9E3FF);
          color: #245B72;
          font-size: 6px;
          font-weight: 800;
          letter-spacing: .04em;
          line-height: 1.2;
          text-transform: uppercase;
          vertical-align: 1px;
        }
        .calendar-team-label .team-mark {
          width: 8px;
          height: 8px;
        }
        .calendar-session-block .booked-snow-overlay {
          opacity: .3;
          transform: rotate(-9deg) scale(1.2);
        }
        .calendar-check {
          width: 11px;
          height: 11px;
          margin-top: 1px;
          border: 1.25px solid currentColor;
          border-radius: 3px;
          display: flex;
          align-items: center;
          justify-content: center;
          flex: 0 0 11px;
          font-size: 8px;
          font-weight: 800;
          line-height: 1;
        }
        .calendar-session-copy {
          width: 100%;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .calendar-session-time {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .calendar-session-time {
          font-size: 9px;
          font-weight: 700;
        }
        .calendar-session-status {
          margin-top: 1px;
          font-size: 8px;
          font-weight: 700;
          line-height: 1.15;
          opacity: .88;
          overflow: visible;
          white-space: normal;
        }
        .calendar-session-meta {
          margin-top: 2px;
          font-size: 7px;
          line-height: 1.15;
          opacity: .74;
          overflow: visible;
          white-space: normal;
        }
        @keyframes showSessionGlow {
          0%, 100% {
            background-position: 0 0, 0% 50%;
            box-shadow: 0 0 7px rgba(101, 202, 219, .2), 0 0 11px rgba(132, 118, 225, .18);
          }
          50% {
            background-position: 0 0, 100% 50%;
            box-shadow: 0 0 10px rgba(101, 202, 219, .34), 0 0 17px rgba(174, 112, 220, .3);
          }
        }
        @keyframes showRowGlow {
          0%, 100% {
            box-shadow:
              inset 4px 0 0 #67C9DA,
              inset -2px 0 0 #A58BE8,
              0 0 8px rgba(126, 143, 229, .18);
          }
          50% {
            box-shadow:
              inset 4px 0 0 #67C9DA,
              inset -2px 0 0 #A58BE8,
              0 0 15px rgba(153, 112, 222, .3);
          }
        }
        @media (prefers-reduced-motion: reduce) {
          .show-session { animation: none !important; }
        }
        @media (max-width: 900px) {
          .dashboard-hero {
            grid-template-columns: 1fr !important;
            gap: 16px !important;
          }
        }
        @media (max-width: 680px) {
          .dashboard-grid {
            grid-template-columns: 1fr !important;
            padding: 18px 18px 80px !important;
          }
          .dashboard-hero-shell { padding: 30px 18px 0 !important; }
          .dashboard-title { white-space: normal; }
          .booking-rules {
            gap: 5px;
            font-size: 10.5px;
          }
          .dashboard-nav-email { display: none; }
          .dashboard-nav-actions { gap: 7px !important; }
          .dashboard-profile-spacer { display: none; }
          .session-card-header {
            align-items: flex-start !important;
            gap: 10px;
          }
          .session-view-actions {
            align-items: flex-end;
            flex-direction: column;
            gap: 6px;
          }
          .session-select-hint { display: none; }
          .calendar-toolbar { min-height: 64px; padding: 11px 12px; }
          .calendar-month-title { font-size: 15px; }
          .calendar-nav-button { width: 32px; height: 32px; }
          .calendar-weekday { padding: 7px 1px; font-size: 8px; letter-spacing: 0; }
          .calendar-day { min-height: 76px; padding: 5px 3px; }
          .calendar-day-number { margin: 0 1px 4px; font-size: 9px; }
          .calendar-session-block { padding: 4px 3px; gap: 3px; }
          .calendar-check { width: 9px; height: 9px; flex-basis: 9px; border-radius: 2px; }
          .calendar-session-time { font-size: 8px; }
          .calendar-session-status { font-size: 7px; }
          .calendar-session-meta { font-size: 6.5px; }
        }
      `}</style>
    </div>
  );
}
