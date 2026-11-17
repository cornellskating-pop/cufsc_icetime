export function strikeCategory(reason: string): string {
  if (reason === "manual") return "Manual strike";
  if (reason === "no_show") return "Historical absence strike";
  if (reason === "unregistered") return "Skating without signing up";
  return "Strike";
}

export function strikeReason(strike: { reason: string; justification?: string | null }): string {
  return strike.justification?.trim() || `${strikeCategory(strike.reason)} — no written reason recorded (legacy strike).`;
}
