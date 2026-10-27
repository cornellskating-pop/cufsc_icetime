"use client";

import { useMemo, useState } from "react";
import { CALENDAR_TIME_ZONE, easternDateKey, monthDays, shiftMonth } from "./adminCalendar";

export type CalendarSession = {
  id: string; label: string | null; start_time: string; end_time: string;
  release_at: string | null; capacity: number; spots_left?: number;
};

export function AdminSessionCalendar({ sessions, nowMs, onEdit, onAdd, onRestore, onDelete }: {
  sessions: CalendarSession[]; nowMs: number;
  onEdit: (session: CalendarSession) => void; onAdd: (day: string) => void; onRestore: (session: CalendarSession) => void; onDelete: (session: CalendarSession) => void;
}) {
  const [month, setMonth] = useState(() => easternDateKey(new Date(nowMs)).slice(0, 7));
  const days = monthDays(month);
  const today = easternDateKey(new Date(nowMs));
  const byDay = useMemo(() => {
    const grouped = new Map<string, CalendarSession[]>();
    for (const session of [...sessions].sort((a, b) => a.start_time.localeCompare(b.start_time) || a.id.localeCompare(b.id))) {
      const key = easternDateKey(session.start_time);
      grouped.set(key, [...(grouped.get(key) ?? []), session]);
    }
    return grouped;
  }, [sessions]);
  const monthLabel = new Date(`${month}-01T12:00:00Z`).toLocaleDateString("en-US", { timeZone: "UTC", month: "long", year: "numeric" });
  const time = (value: string) => new Date(value).toLocaleTimeString("en-US", { timeZone: CALENDAR_TIME_ZONE, hour: "numeric", minute: "2-digit" });
  const count = sessions.filter(session => easternDateKey(session.start_time).startsWith(month)).length;

  return <section className="admin-calendar" aria-label="Session calendar">
    <div className="admin-calendar-toolbar">
      <div><h2 aria-live="polite">{monthLabel}</h2><span>{count} sessions · All times Eastern · Select a session to edit</span></div>
      <div className="admin-calendar-controls">
        <button type="button" className="btn-ghost" onClick={() => setMonth(value => shiftMonth(value, -1))} aria-label="Previous month">←</button>
        <button type="button" className="btn-ghost" onClick={() => setMonth(today.slice(0, 7))}>Today</button>
        <button type="button" className="btn-ghost" onClick={() => setMonth(value => shiftMonth(value, 1))} aria-label="Next month">→</button>
        <input type="month" className="input" aria-label="Go to month" value={month} onChange={event => { if (/^\d{4}-\d{2}$/.test(event.target.value)) setMonth(event.target.value); }} />
      </div>
    </div>
    {!count && <p role="status" className="admin-calendar-empty">No sessions this month. Use + on a date to add one.</p>}
    <div className="admin-calendar-scroll" tabIndex={0} aria-label="Monthly calendar; scroll horizontally on small screens">
      <div className="admin-calendar-grid">
        {["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"].map(day => <div className="admin-calendar-weekday" key={day}>{day}</div>)}
        {days.map(day => <div key={day.key} className={`admin-calendar-day${day.inMonth ? "" : " outside"}${day.key === today ? " today" : ""}`}>
          <div className="admin-calendar-date"><time dateTime={day.key} aria-current={day.key === today ? "date" : undefined}>{day.day}</time><button type="button" className="btn-link" aria-label={`Add session on ${day.key}`} onClick={() => onAdd(day.key)}>+</button></div>
          {(byDay.get(day.key) ?? []).map(session => {
            const cancelled = session.label?.startsWith("Cancelled: ");
            const practice = session.label?.toLowerCase().startsWith("show practice:");
            const ended = new Date(session.end_time).getTime() <= nowMs;
            const ongoing = !ended && new Date(session.start_time).getTime() <= nowMs;
            return <div key={session.id} className="admin-calendar-entry"><button type="button" className={`admin-calendar-session${cancelled ? " cancelled" : practice ? " practice" : ""}`}
              onClick={() => cancelled ? onRestore(session) : onEdit(session)} title={`${session.id} · ${cancelled ? "View restoration options" : "Edit session"}`}>
              <strong>{time(session.start_time)} – {time(session.end_time)}</strong>
              {easternDateKey(session.end_time) !== day.key && <span>Ends {easternDateKey(session.end_time)}</span>}
              <span className="admin-calendar-label">{session.label || "Ice session"}</span>
              <span>{cancelled ? "Cancelled · Restore options" : `${session.capacity - (session.spots_left ?? session.capacity)} / ${session.capacity} booked${ongoing ? " · In progress" : ended ? " · Ended" : ""}`}</span>
            </button>
              <button type="button" className="btn-danger" aria-label={`Delete session ${session.label || session.id} (${session.id})`} onClick={() => onDelete(session)}>Delete session</button>
            </div>;
          })}
        </div>)}
      </div>
    </div>
    <style>{`
      .admin-calendar { min-height: calc(100dvh - 200px); display: flex; flex-direction: column; }
      .admin-calendar-toolbar { display:flex; justify-content:space-between; align-items:center; gap:16px; flex-wrap:wrap; margin-bottom:18px; }
      .admin-calendar-toolbar h2 { margin:0 0 5px; font-size:24px; font-family:'Syne',sans-serif; }
      .admin-calendar-toolbar span { font-size:12px; color:var(--muted); }
      .admin-calendar-controls { display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
      .admin-calendar-controls input { width:160px; }
      .admin-calendar-scroll { overflow:auto; border:1px solid var(--border); border-radius:14px; background:white; flex:1; }
      .admin-calendar-grid { display:grid; grid-template-columns:repeat(7,minmax(0,1fr)); min-width:980px; min-height:100%; }
      .admin-calendar-weekday { background:var(--ink); color:white; padding:12px; font-size:11px; font-weight:700; }
      .admin-calendar-day { min-height:145px; padding:8px; border-right:1px solid var(--border); border-bottom:1px solid var(--border); }
      .admin-calendar-day.outside { background:#f4f4f4; }
      .admin-calendar-day.today { background:var(--red-light); box-shadow:inset 0 0 0 2px var(--red); }
      .admin-calendar-date { display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; font-size:12px; font-weight:700; }
      .admin-calendar-date button { padding:4px 8px; font-size:20px; }
      .admin-calendar-entry { margin-bottom:12px; }
      .admin-calendar-session { display:flex; flex-direction:column; gap:5px; width:100%; text-align:left; margin-bottom:7px; padding:10px; background:#fff7f7; border:1px solid #e9c8c8; border-left:3px solid var(--red); border-radius:8px; color:var(--ink); cursor:pointer; font:inherit; overflow-wrap:anywhere; }
      .admin-calendar-session strong { font-size:11px; }
      .admin-calendar-session span { font-size:10px; }
      .admin-calendar-session .admin-calendar-label { font-size:12px; font-weight:600; }
      .admin-calendar-session.practice { background:#f4edff; border-color:#b99ada; }
      .admin-calendar-session.cancelled { background:#eee; border-color:#aaa; color:#666; }
      .admin-calendar-session:hover { box-shadow:0 3px 10px #0002; }
      .admin-calendar-session:focus-visible { outline:2px solid var(--red); outline-offset:2px; }
      .admin-calendar-empty { font-size:13px; color:var(--muted); }
      @media(min-width:1400px) { .admin-calendar-day { min-height:170px; } }
    `}</style>
  </section>;
}
