// A small JSON Schema checker for model output. Providers constrain output to a schema, but
// an answer cut off at the token limit or a refusal does not match it, and some providers
// ignore keywords (Claude structured outputs drop length and numeric limits), so the gateway
// checks every JSON answer itself.
//
// Supported keywords: type, enum, const, properties, required, additionalProperties,
// items, minItems, maxItems, minLength, maxLength, pattern, minimum, maximum,
// exclusiveMinimum, exclusiveMaximum, anyOf. Annotations (description, title, $schema,
// default, examples, format) are ignored. Any other keyword makes the schema unsupported,
// and call() refuses it before sending, rather than paying for an answer it cannot check.

type Schema = Record<string, unknown>;

const constraintKeywords = new Set([
  "type",
  "enum",
  "const",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "minLength",
  "maxLength",
  "pattern",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "anyOf",
]);
const annotationKeywords = new Set([
  "description",
  "title",
  "$schema",
  "default",
  "examples",
  "format",
]);
const typeNames = new Set(["object", "array", "string", "number", "integer", "boolean", "null"]);

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isCount = (value: unknown) => Number.isInteger(value) && Number(value) >= 0;

export function isSupportedSchema(schema: unknown): boolean {
  if (!isObject(schema)) return false;
  for (const [key, value] of Object.entries(schema)) {
    if (annotationKeywords.has(key)) continue;
    if (!constraintKeywords.has(key)) return false;
    switch (key) {
      case "type": {
        const names = Array.isArray(value) ? value : [value];
        if (names.length === 0 || !names.every((name) => typeNames.has(String(name)))) {
          return false;
        }
        break;
      }
      case "enum":
        if (!Array.isArray(value)) return false;
        break;
      case "properties":
        if (!isObject(value) || !Object.values(value).every(isSupportedSchema)) return false;
        break;
      case "required":
        if (!Array.isArray(value) || !value.every((name) => typeof name === "string")) {
          return false;
        }
        break;
      case "additionalProperties":
        if (typeof value !== "boolean" && !isSupportedSchema(value)) return false;
        break;
      case "items":
        if (!isSupportedSchema(value)) return false;
        break;
      case "anyOf":
        if (!Array.isArray(value) || value.length === 0 || !value.every(isSupportedSchema)) {
          return false;
        }
        break;
      case "minItems":
      case "maxItems":
      case "minLength":
      case "maxLength":
        if (!isCount(value)) return false;
        break;
      case "minimum":
      case "maximum":
      case "exclusiveMinimum":
      case "exclusiveMaximum":
        if (typeof value !== "number" || !Number.isFinite(value)) return false;
        break;
      case "pattern":
        if (typeof value !== "string") return false;
        try {
          new RegExp(value, "u");
        } catch {
          return false;
        }
        break;
    }
  }
  return true;
}

function hasType(value: unknown, name: string): boolean {
  switch (name) {
    case "object":
      return isObject(value);
    case "array":
      return Array.isArray(value);
    case "string":
      return typeof value === "string";
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "integer":
      return Number.isInteger(value);
    case "boolean":
      return typeof value === "boolean";
    case "null":
      return value === null;
    default:
      return false;
  }
}

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((item, index) => deepEqual(item, b[index]));
  }
  if (isObject(a) && isObject(b)) {
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length &&
      keys.every((key) => Object.hasOwn(b, key) && deepEqual(a[key], b[key]));
  }
  return false;
}

/** True when value matches a schema that isSupportedSchema accepts. */
export function matchesSchema(value: unknown, schema: Schema): boolean {
  if (schema.type !== undefined) {
    const names = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!names.some((name) => hasType(value, String(name)))) return false;
  }
  if (Array.isArray(schema.enum) && !schema.enum.some((option) => deepEqual(option, value))) {
    return false;
  }
  if (Object.hasOwn(schema, "const") && !deepEqual(schema.const, value)) return false;
  if (
    Array.isArray(schema.anyOf) &&
    !schema.anyOf.some((option) => matchesSchema(value, option as Schema))
  ) return false;

  if (typeof value === "string") {
    const length = [...value].length;
    if (typeof schema.minLength === "number" && length < schema.minLength) return false;
    if (typeof schema.maxLength === "number" && length > schema.maxLength) return false;
    if (typeof schema.pattern === "string" && !new RegExp(schema.pattern, "u").test(value)) {
      return false;
    }
  }
  if (typeof value === "number") {
    if (typeof schema.minimum === "number" && value < schema.minimum) return false;
    if (typeof schema.maximum === "number" && value > schema.maximum) return false;
    if (typeof schema.exclusiveMinimum === "number" && value <= schema.exclusiveMinimum) {
      return false;
    }
    if (typeof schema.exclusiveMaximum === "number" && value >= schema.exclusiveMaximum) {
      return false;
    }
  }
  if (Array.isArray(value)) {
    if (typeof schema.minItems === "number" && value.length < schema.minItems) return false;
    if (typeof schema.maxItems === "number" && value.length > schema.maxItems) return false;
    if (isObject(schema.items)) {
      const items = schema.items;
      if (!value.every((item) => matchesSchema(item, items))) return false;
    }
  }
  if (isObject(value)) {
    const properties = isObject(schema.properties) ? schema.properties : {};
    if (Array.isArray(schema.required)) {
      if (!schema.required.every((name) => Object.hasOwn(value, String(name)))) return false;
    }
    for (const [key, item] of Object.entries(value)) {
      if (Object.hasOwn(properties, key)) {
        if (!matchesSchema(item, properties[key] as Schema)) return false;
      } else if (schema.additionalProperties === false) {
        return false;
      } else if (isObject(schema.additionalProperties)) {
        if (!matchesSchema(item, schema.additionalProperties)) return false;
      }
    }
  }
  return true;
}
