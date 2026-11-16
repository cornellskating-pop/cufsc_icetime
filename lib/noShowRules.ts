export type NoShowRules = {
  delay_minutes: number;
  version: number;
  updated_at: string;
};

export function noShowRuleDescription(rules: Pick<NoShowRules, "delay_minutes">) {
  return `Removal opens ${rules.delay_minutes} minute${rules.delay_minutes === 1 ? "" : "s"} after start for all sessions. No strikes are applied.`;
}
