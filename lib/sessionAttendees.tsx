"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "./supabaseClient";
import { SessionBookingHeader } from "./sessionBookingHeader";

type SessionAttendance = {
  session_id: string;
  start_time: string;
  end_time: string;
  label: string | null;
  capacity: number;
  names: string[];
};

function FittedName({ name }: { name: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const full = name.trim().replace(/\s+/g, " ") || "—";
  const parts = full.split(" ");
  const abbreviated = parts.length > 1
    ? `${parts.slice(0, -1).join(" ")} ${Array.from(parts.at(-1)!)[0]}.`
    : full;
  const initials = parts.map(part => `${Array.from(part)[0]}.`).join("");

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const fit = () => {
      for (const candidate of [full, abbreviated, initials]) {
        element.textContent = candidate;
        if (element.scrollWidth <= element.clientWidth) break;
      }
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(element);
    let active = true;
    void document.fonts.ready.then(() => { if (active) fit(); });
    return () => { active = false; observer.disconnect(); };
  }, [full, abbreviated, initials]);

  return <span ref={ref} aria-label={full} title={full} style={{ display: "block", minWidth: 0, whiteSpace: "nowrap", overflow: "hidden" }}>{full}</span>;
}

export function SessionAttendees({ nowMs, bookings }: { nowMs: number; bookings: readonly unknown[] }) {
  const [groups, setGroups] = useState<SessionAttendance[] | null>(null);
  const [error, setError] = useState("");
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let active = true;
    const load = async () => {
      const { data, error } = await supabase.rpc("list_upcoming_session_attendees");
      if (!active) return;
      setError(error ? "Unable to load attendees. Please try again." : "");
      setGroups(error ? null : (data ?? []) as SessionAttendance[]);
    };
    void load();
    return () => { active = false; };
  }, [bookings, attempt]);

  if (error) return <div role="alert" style={{ padding: 20 }}>{error} <button type="button" onClick={() => setAttempt(value => value + 1)}>Retry</button></div>;
  if (!groups) return <div role="status" style={{ padding: 20 }}>Loading attendees…</div>;
  const upcoming = groups.filter(group => new Date(group.start_time).getTime() >= nowMs);
  if (!upcoming.length) return <div style={{ padding: 20, color: "var(--muted)" }}>No upcoming sessions.</div>;

  return <div style={{ padding: 12, display: "grid", gap: 12 }}>
    {upcoming.map(group => <details className="card attendance-session" key={group.session_id}>
      <summary style={{ padding: "14px 12px", cursor: "pointer", background: "var(--ink)", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
        <SessionBookingHeader startTime={group.start_time} endTime={group.end_time} label={group.label} count={group.names.length} capacity={group.capacity} isOpen={false} />
      </summary>
      {group.names.length === 0 ? <div style={{ padding: 16, fontSize: 13, color: "var(--muted)" }}>No bookings for this session.</div> :
        Array.from({ length: Math.ceil(group.names.length / 25) }, (_, page) => {
          const names = group.names.slice(page * 25, (page + 1) * 25);
          return <ol key={page} aria-label={`Attendees ${page * 25 + 1}–${page * 25 + names.length}`} start={page * 25 + 1} style={{ listStyle: "none", margin: 12, padding: 0, display: "grid", gridTemplateColumns: "repeat(5, minmax(0, 1fr))", gap: 4 }}>
            {names.map((name, index) => <li key={index} style={{ minWidth: 0, padding: "10px 4px", textAlign: "center", border: "1px solid var(--border)", borderRadius: 4, fontSize: 12 }}><FittedName name={name} /></li>)}
          </ol>;
        })}
    </details>)}
    <style>{`.attendance-session summary { list-style: none; } .attendance-session summary::-webkit-details-marker { display: none; } .attendance-session[open] summary > div:last-child > span:last-child { transform: rotate(180deg); }`}</style>
  </div>;
}
