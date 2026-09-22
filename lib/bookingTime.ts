type FreeBookingSession = { start_time: string; release_at: string | null; capacity: number; spots_left: number };

export function formatCountdownAmount(remainingMs: number) {
  if (remainingMs >= 48 * 60 * 60 * 1000) {
    return `${Math.ceil(remainingMs / (24 * 60 * 60 * 1000))}d`;
  }
  if (remainingMs >= 60 * 60 * 1000) {
    return `${Math.ceil(remainingMs / (60 * 60 * 1000))}h`;
  }
  return `${Math.max(1, Math.ceil(remainingMs / (60 * 1000)))}m`;
}

export function freeBookingIndicator(session: FreeBookingSession, nowMs: number) {
  const start = new Date(session.start_time).getTime();
  if (session.capacity <= 0 || nowMs >= start) return null;
  const opens = Math.max(start - 60 * 60 * 1000, session.release_at ? new Date(session.release_at).getTime() : 0);
  if (nowMs < opens) return `No-credit booking in ${formatCountdownAmount(opens - nowMs)}`;
  return session.spots_left > 0 ? "No-credit booking now" : "No-credit window · full";
}

