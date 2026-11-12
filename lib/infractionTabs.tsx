"use client";

import { useState } from "react";
import { InfractionPanel } from "./infractionPanel";
import { NoShowPanel } from "./noShowPanel";

export function InfractionTabs() {
  const [tab, setTab] = useState("unregistered");
  return <div className="card" style={{ marginBottom: 24 }}>
    <div role="tablist" aria-label="Report skating infractions" style={{ display: "flex", flexWrap: "wrap", gap: 8, padding: "12px 20px", borderBottom: "1px solid var(--border)" }}>
      {[["unregistered", "Skating without signing up"], ["no-show", "Booked but absent"]].map(([id, label]) => <button
        key={id} id={`infraction-tab-${id}`} role="tab" type="button" aria-selected={tab === id} aria-controls={`infraction-panel-${id}`} tabIndex={tab === id ? 0 : -1}
        className={tab === id ? "btn-primary" : "btn-ghost"}
        onClick={() => setTab(id)}
        onKeyDown={e => {
          if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
          e.preventDefault();
          const next = e.key === "Home" ? "unregistered" : e.key === "End" ? "no-show" : tab === "unregistered" ? "no-show" : "unregistered";
          setTab(next); document.getElementById(`infraction-tab-${next}`)?.focus();
        }}
      >{label}</button>)}
    </div>
    <div id="infraction-panel-unregistered" role="tabpanel" aria-labelledby="infraction-tab-unregistered" hidden={tab !== "unregistered"}>
      {tab === "unregistered" && <InfractionPanel embedded />}
    </div>
    <div id="infraction-panel-no-show" role="tabpanel" aria-labelledby="infraction-tab-no-show" hidden={tab !== "no-show"}>
      {tab === "no-show" && <NoShowPanel />}
    </div>
  </div>;
}
