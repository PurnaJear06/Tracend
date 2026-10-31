// A duration stored in minutes, as the people who read it say it. Coach is shown the stored figure
// and, next to it, the same time as hours and minutes (the app's own split, recovery_readout_card.dart
// `_formatMinutes`: whole hours, then the rest) and as hours to one decimal. Both are records (the
// same value, written by the renderer, not worked out by the model), so "you slept 5.7 h" and "5 h
// 41 min" rest on a "341 min" row, where the numbers check, which never converts units, would have
// refused them. Under an hour nothing is added: minutes are what is said.
const rounded = (minutes: number) => Math.round(minutes);

/** "5 h 41 min; 5.7 h" for 341, "7 h" for 420, null under an hour or when it is not a number. */
export function hoursNote(minutes: unknown): string | null {
  if (typeof minutes !== "number" || !Number.isFinite(minutes) || minutes < 60) return null;
  const total = rounded(minutes);
  const hours = Math.floor(total / 60);
  const rest = total % 60;
  if (rest === 0) return `${hours} h`;
  return `${hours} h ${rest} min; ${(Math.round(minutes / 6) / 10).toFixed(1)} h`;
}

/** "341 min (5 h 41 min; 5.7 h)"; the value alone, with its unit, under an hour. */
export function minutesText(value: unknown, shown: string = String(value)): string {
  const note = hoursNote(value);
  return note === null ? `${shown} min` : `${shown} min (${note})`;
}

/** The same for a table cell that already carries the unit in its header: "341 (5 h 41 min; 5.7 h)". */
export function minutesCell(value: unknown, shown: string = String(value)): string {
  const note = hoursNote(value);
  return note === null ? shown : `${shown} (${note})`;
}
