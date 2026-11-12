export type NoShowRules = {
  duration_boundary_minutes: number;
  short_delay_minutes: number;
  long_delay_minutes: number;
  version: number;
  updated_at: string;
};

export function noShowRuleDescription(rules: Pick<NoShowRules, "duration_boundary_minutes" | "short_delay_minutes" | "long_delay_minutes">) {
  const minutes = (n: number) => `${n} minute${n === 1 ? "" : "s"}`;
  return `Reporting opens ${minutes(rules.short_delay_minutes)} after start for sessions under ${minutes(rules.duration_boundary_minutes)}, or ${minutes(rules.long_delay_minutes)} after start for sessions of ${minutes(rules.duration_boundary_minutes)} or more.`;
}
