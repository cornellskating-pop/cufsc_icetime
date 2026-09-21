type Props = { startTime: string; endTime: string; label: string | null; count: number; capacity: number; isOpen: boolean; isPast?: boolean };

export function SessionBookingHeader({ startTime, endTime, label, count, capacity, isOpen, isPast = false }: Props) {
  const fmt = (d: string) => new Date(d).toLocaleString("en-US", {
    timeZone: "America/New_York", weekday: "short", month: "short",
    day: "numeric", hour: "numeric", minute: "2-digit",
  });

  return <>
    <div>
      <div style={{ fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 14, color: isPast ? "var(--ink)" : "white" }}>
        {fmt(startTime)}
        <span style={{ color: isPast ? "var(--muted)" : "#888", fontWeight: 400 }}>
          {" – "}{new Date(endTime).toLocaleString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" })}
        </span>
      </div>
      {label && <div style={{ fontSize: 11, color: isPast ? "var(--muted)" : "#888", marginTop: 2 }}>{label}</div>}
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
      <span style={{
        background: count > 0 ? "var(--red)" : "var(--border)",
        color: count > 0 ? "white" : "var(--muted)",
        fontFamily: "'Syne',sans-serif", fontWeight: 700, fontSize: 12,
        padding: "3px 10px", borderRadius: 100, whiteSpace: "nowrap",
      }}>
        {count} / {capacity}
      </span>
      <span style={{ color: isPast ? "var(--muted)" : "#666", fontSize: 12 }}>{isOpen ? "▲" : "▼"}</span>
    </div>
  </>;
}
