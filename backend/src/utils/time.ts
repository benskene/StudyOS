const DAY_MS = 24 * 60 * 60 * 1000;

function pad(n: number): string {
  return n.toString().padStart(2, "0");
}

function parseDayKey(dayKey: string): Date {
  const [year, month, day] = dayKey.split("-").map((x) => Number(x));
  return new Date(Date.UTC(year, (month || 1) - 1, day || 1));
}

export function dayKeyInTimeZone(date: Date, timeZone: string): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });
  return fmt.format(date);
}

export function addDaysDayKey(dayKey: string, days: number): string {
  const date = parseDayKey(dayKey);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function weekDayKeys(weekStart: string): string[] {
  return Array.from({ length: 7 }, (_, i) => addDaysDayKey(weekStart, i));
}

export function dayLabel(dayKey: string): string {
  const date = parseDayKey(dayKey);
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    timeZone: "UTC"
  }).format(date);
}

export function parseCursor(raw: unknown): number {
  if (typeof raw !== "string" && typeof raw !== "number") {
    return 0;
  }
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    return 0;
  }
  return Math.floor(value);
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function isBeforeNow(dateIso: string): boolean {
  return new Date(dateIso).getTime() < Date.now();
}

export const ONE_DAY_MS = DAY_MS;
