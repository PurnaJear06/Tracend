// Counts what makes Claude's structured-output grammar expensive to compile: optional properties
// and unions (coach_chat_schema_test.ts tells the 2026-10-18 story). Used by the schema tests of
// every feature that sends Claude a schema.

type Node = Record<string, unknown>;

const isNode = (value: unknown): value is Node =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Every property of every object that its `required` list does not name. */
export function optionalProperties(node: unknown, path = "$"): string[] {
  if (Array.isArray(node)) {
    return node.flatMap((item, i) => optionalProperties(item, `${path}[${i}]`));
  }
  if (!isNode(node)) return [];
  const found: string[] = [];
  if (isNode(node.properties)) {
    const required = new Set(Array.isArray(node.required) ? node.required : []);
    for (const name of Object.keys(node.properties)) {
      if (!required.has(name)) found.push(`${path}.${name}`);
    }
  }
  for (const [key, value] of Object.entries(node)) {
    found.push(...optionalProperties(value, `${path}.${key}`));
  }
  return found;
}

/**
 * Every union: `anyOf`, `oneOf`, a `type` list (such as ["string", "null"]) and `nullable`. A
 * property named `anyOf` is not a keyword, so only schema positions count.
 */
export function unions(node: unknown, path = "$"): string[] {
  if (Array.isArray(node)) return node.flatMap((item, i) => unions(item, `${path}[${i}]`));
  if (!isNode(node)) return [];
  const found: string[] = [];
  for (const keyword of ["anyOf", "oneOf", "allOf"]) {
    if (keyword in node) found.push(`${path}.${keyword}`);
  }
  if (Array.isArray(node.type) || node.nullable !== undefined) found.push(`${path}.type`);
  for (const [key, value] of Object.entries(node)) {
    if (key === "properties" && isNode(value)) {
      for (const [name, item] of Object.entries(value)) {
        found.push(...unions(item, `${path}.${name}`));
      }
    } else {
      found.push(...unions(value, `${path}.${key}`));
    }
  }
  return found;
}

/** Every enum in the schema, in order. */
export function enums(node: unknown): unknown[][] {
  if (Array.isArray(node)) return node.flatMap(enums);
  if (!isNode(node)) return [];
  return [
    ...(Array.isArray(node.enum) ? [node.enum as unknown[]] : []),
    ...Object.values(node).flatMap(enums),
  ];
}
