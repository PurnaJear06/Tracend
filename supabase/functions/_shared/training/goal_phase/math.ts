// Small shared helpers of the goal phase review.

export function round(value: number, decimals: number): number {
  const sign = value < 0 ? -1 : 1;
  const rounded = Number(Math.round(Number(`${Math.abs(value)}e${decimals}`)) + `e-${decimals}`);
  return rounded === 0 ? 0 : sign * rounded;
}

/** Days since the epoch for a YYYY-MM-DD date, or null when it is not a real date. */
export function dayIndex(date: unknown): number | null {
  if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const [year, month, day] = date.split("-").map(Number);
  const time = Date.UTC(year, month - 1, day);
  const parsed = new Date(time);
  if (parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) return null;
  return time / 86_400_000;
}

export function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
