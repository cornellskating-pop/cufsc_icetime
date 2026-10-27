export const CALENDAR_TIME_ZONE = "America/New_York";

export function easternDateKey(value: Date | string) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: CALENDAR_TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(value));
  const get = (type: string) => parts.find(part => part.type === type)!.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export function monthDays(month: string) {
  const [year, number] = month.split("-").map(Number);
  const first = new Date(Date.UTC(year, number - 1, 1));
  const count = new Date(Date.UTC(year, number, 0)).getUTCDate();
  return Array.from({ length: Math.ceil((first.getUTCDay() + count) / 7) * 7 }, (_, index) => {
    const date = new Date(Date.UTC(year, number - 1, index - first.getUTCDay() + 1));
    return { key: date.toISOString().slice(0, 10), day: date.getUTCDate(), inMonth: date.getUTCMonth() === number - 1 };
  });
}

export function shiftMonth(month: string, offset: number) {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number - 1 + offset, 1)).toISOString().slice(0, 7);
}
