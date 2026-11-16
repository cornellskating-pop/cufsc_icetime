"use client";

import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";

type History = {
  strikes: { id: string; marked_date: string; reason: string }[];
  restriction: { blocked: boolean; marks: number; remaining_days: number };
};

export function MemberStrikes() {
  const [history, setHistory] = useState<History | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    const load = async () => {
      const { data, error } = await supabase.rpc("my_infractions");
      if (!active) return;
      setError(!!error);
      setHistory(error ? null : data as History);
    };
    void load();
    const timer = window.setInterval(() => void load(), 30_000);
    return () => { active = false; window.clearInterval(timer); };
  }, []);
  return <section aria-label="My strikes" style={{ marginTop: 16, fontSize: 12 }}>
    <strong>Strikes</strong>
    {error ? <p>Strike history could not be loaded. Please reload the page.</p> : !history ? <p>Loading strikes…</p> : <>
      <p>{history.restriction.marks} strike(s) this semester · {history.restriction.blocked ? `${history.restriction.remaining_days} session day(s) remaining in your restriction` : "No active booking restriction"}</p>
      <details><summary>View active strikes ({history.strikes.length})</summary>
        {history.strikes.length ? <ul style={{ paddingLeft: 18 }}>{history.strikes.map(s => <li key={s.id}>{s.marked_date}: {s.reason === "manual" ? "Manual strike" : s.reason === "no_show" ? "Historical absence strike" : "Skating without signing up"}</li>)}</ul> : <p>No active strikes.</p>}
      </details>
    </>}
  </section>;
}
