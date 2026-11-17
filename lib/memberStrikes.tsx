"use client";

import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { strikeReason } from "./strikeReason";

type History = {
  strikes: { id: string; marked_date: string; reason: string; justification: string | null }[];
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
        {history.strikes.length ? <ul style={{ paddingLeft: 18 }}>{history.strikes.map(s => <li key={s.id} style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{s.marked_date}: {strikeReason(s)}</li>)}</ul> : <p>No active strikes.</p>}
      </details>
    </>}
  </section>;
}
