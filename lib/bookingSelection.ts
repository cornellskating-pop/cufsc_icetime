type CreditSession = { id: string; start_time: string };
export function selectionCost(sessions: CreditSession[], ids: readonly string[], nowMs: number, approvalOnly = false) {
  if (approvalOnly) return 0;
  const selected = new Set(ids);
  return sessions.filter(session => selected.has(session.id) && new Date(session.start_time).getTime() - nowMs > 60 * 60 * 1000).length;
}
export function canSelectSession(sessions: CreditSession[], ids: readonly string[], id: string, credits: number, nowMs: number, approvalOnly = false) {
  return ids.includes(id) || selectionCost(sessions, [...ids, id], nowMs, approvalOnly) <= Math.max(0, credits);
}
