// Test helper for the grounding declarations: change one declared field of a payload, keeping its
// type, and see what the text of a surface does. A field "is shown" when changing it changes the
// text; a marker string in a number or a date field would be read as something else (or not at
// all) by the code that formats it, so the change keeps the type: a number stays a number, a date
// a date, a flag the other flag, and only a word becomes another word.
const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const isoMoment = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;

/** Other values for a field of the same type as `value`; `seed` makes a sentinel unique. */
export function variantsOf(value: unknown, seed: number): unknown[] {
  if (typeof value === "number") return [value + 1, value + 17, 7_770_000 + seed];
  if (typeof value === "boolean") return [!value];
  if (typeof value === "string") {
    // The last shift is a season: a date shown only as its month changes the text with it.
    if (isoDate.test(value)) {
      return [3, 11, 75].map((days) => shiftDate(value, days));
    }
    if (isoMoment.test(value)) {
      return [3, 11, 75].map((days) => shiftDate(value.slice(0, 10), days) + value.slice(10));
    }
    return [`ZQ${seed}X`, `ZQ${seed}Y`];
  }
  return [`ZQ${seed}X`, 7_770_000 + seed];
}

function shiftDate(date: string, days: number): string {
  const moved = new Date(Date.parse(`${date}T00:00:00Z`) + days * 86_400_000);
  return moved.toISOString().slice(0, 10);
}

type Slot = readonly [Record<string | number, unknown>, string | number];

function slots(node: unknown, steps: string[]): Slot[] {
  if (node === null || typeof node !== "object" || Array.isArray(node)) return [];
  const [step, ...rest] = steps;
  const list = step.endsWith("[]");
  const key = list ? step.slice(0, -2) : step;
  const holder = node as Record<string | number, unknown>;
  if (!(key in holder)) return [];
  const child = holder[key];
  if (!list) return rest.length === 0 ? [[holder, key]] : slots(child, rest);
  if (!Array.isArray(child)) return [];
  const items = child as Record<string | number, unknown>[];
  return rest.length === 0
    ? items.map((_, index) => [items as unknown as Record<string | number, unknown>, index] as Slot)
    : items.flatMap((item) => slots(item, rest));
}

/** A copy of the payload with every field at `path` replaced by `next(value)`. */
export function changeAt<T>(payload: T, path: string, next: (value: unknown) => unknown): T {
  const copy = structuredClone(payload);
  for (const [holder, key] of slots(copy, path.split("."))) holder[key] = next(holder[key]);
  return copy;
}

/**
 * The paths a renderer reads in a payload, as the declarations write them (`a.b` for a field, `a[].b`
 * inside a list): `run` is given a copy of the payload that records every read of a plain value,
 * including a read of a field the payload does not have. Containers are not recorded, only the
 * fields a renderer takes values from, so a field it looks at (to show it, or to decide what to
 * show) is on the list whether or not the fixture's value made it appear in the text.
 */
export function pathsRead(payload: unknown, run: (spied: unknown) => void): Set<string> {
  const seen = new Set<string>();
  const wrap = (value: unknown, path: string): unknown => {
    if (value === null || typeof value !== "object") return value;
    return new Proxy(value, {
      get(target, key, receiver) {
        const read = Reflect.get(target, key, receiver);
        if (typeof key !== "string" || typeof read === "function") return read;
        const list = Array.isArray(target);
        if (list && !/^\d+$/.test(key)) return read;
        const child = list ? `${path}[]` : path === "" ? key : `${path}.${key}`;
        if (read === null || typeof read !== "object") seen.add(child);
        return wrap(read, child);
      },
    });
  };
  run(wrap(payload, ""));
  return seen;
}

/** The leaf paths of a payload that hold a value (not null) in at least one row. */
export function filledPaths(node: unknown, path = "", out = new Set<string>()): Set<string> {
  if (Array.isArray(node)) {
    for (const item of node) {
      if (item !== null && typeof item === "object") filledPaths(item, `${path}[]`, out);
      else if (item !== null && item !== undefined) out.add(`${path}[]`);
    }
    return out;
  }
  if (node !== null && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      filledPaths(value, path === "" ? key : `${path}.${key}`, out);
    }
    return out;
  }
  if (node !== null && node !== undefined) out.add(path);
  return out;
}
