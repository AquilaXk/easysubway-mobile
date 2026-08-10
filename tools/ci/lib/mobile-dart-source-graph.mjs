import { createHash } from "node:crypto";
import path from "node:path";

const CONTROL = /[\u0000-\u001f\u007f]/u;
const IDENTIFIER_START = /[A-Za-z_$]/u;
const IDENTIFIER_PART = /[A-Za-z0-9_$]/u;

function compare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function normalizedPath(value, label = "Dart source path") {
  if (typeof value !== "string" || value.length === 0 || CONTROL.test(value) || value.includes("\\")) {
    throw new Error(`invalid ${label}`);
  }
  if (value.startsWith("/") || /^[A-Za-z]:\//u.test(value)) throw new Error(`invalid ${label}`);
  const pieces = value.split("/");
  if (pieces.some((piece) => piece === "" || piece === "." || piece === "..")) throw new Error(`invalid ${label}`);
  return value;
}

function skipBlockComment(source, state) {
  state.index += 2;
  let depth = 1;
  while (state.index < source.length && depth > 0) {
    if (source.startsWith("/*", state.index)) {
      depth += 1;
      state.index += 2;
    } else if (source.startsWith("*/", state.index)) {
      depth -= 1;
      state.index += 2;
    } else {
      state.index += 1;
    }
  }
  if (depth !== 0) state.malformed = true;
}

function skipInterpolation(source, state) {
  let depth = 1;
  while (state.index < source.length && depth > 0) {
    if (source.startsWith("//", state.index)) {
      const newline = source.indexOf("\n", state.index + 2);
      state.index = newline === -1 ? source.length : newline + 1;
      continue;
    }
    if (source.startsWith("/*", state.index)) {
      skipBlockComment(source, state);
      continue;
    }
    const character = source[state.index];
    const raw = (character === "r" || character === "R") && ["'", '"'].includes(source[state.index + 1]);
    if (raw || character === "'" || character === '"') {
      const quote = raw ? source[state.index + 1] : character;
      if (raw) state.index += 1;
      scanString(source, state, raw, quote);
      continue;
    }
    if (character === "{") depth += 1;
    if (character === "}") depth -= 1;
    state.index += 1;
  }
  if (depth !== 0) state.malformed = true;
}

function scanString(source, state, raw, quote) {
  const triple = source.startsWith(quote.repeat(3), state.index);
  const delimiter = triple ? quote.repeat(3) : quote;
  state.index += delimiter.length;
  const contentStart = state.index;
  let literal = true;
  let closingStart = -1;
  while (state.index < source.length) {
    if (source.startsWith(delimiter, state.index)) {
      closingStart = state.index;
      state.index += delimiter.length;
      break;
    }
    const character = source[state.index];
    if (!raw && character === "\\") {
      literal = false;
      state.index += 1;
      if (state.index >= source.length) break;
      state.index += 1;
      continue;
    }
    if (!raw && character === "$") {
      literal = false;
      state.index += 1;
      if (source[state.index] === "{") {
        state.index += 1;
        skipInterpolation(source, state);
      } else if (IDENTIFIER_START.test(source[state.index] ?? "")) {
        state.index += 1;
        while (IDENTIFIER_PART.test(source[state.index] ?? "")) state.index += 1;
      } else {
        state.malformed = true;
      }
      continue;
    }
    if (!triple && (character === "\n" || character === "\r")) {
      state.malformed = true;
      break;
    }
    state.index += 1;
  }
  if (closingStart === -1) state.malformed = true;
  return {
    type: "string",
    value: closingStart === -1 ? "" : source.slice(contentStart, closingStart),
    literal: literal && closingStart > contentStart,
  };
}

function nextToken(source, state) {
  while (state.index < source.length) {
    const character = source[state.index];
    if (/\s/u.test(character)) {
      state.index += 1;
      continue;
    }
    if (state.index === 0 && source.startsWith("#!", state.index)) {
      const newline = source.indexOf("\n", 2);
      state.index = newline === -1 ? source.length : newline + 1;
      continue;
    }
    if (source.startsWith("//", state.index)) {
      const newline = source.indexOf("\n", state.index + 2);
      state.index = newline === -1 ? source.length : newline + 1;
      continue;
    }
    if (source.startsWith("/*", state.index)) {
      skipBlockComment(source, state);
      continue;
    }
    const raw = (character === "r" || character === "R") && ["'", '"'].includes(source[state.index + 1]);
    if (raw || character === "'" || character === '"') {
      const quote = raw ? source[state.index + 1] : character;
      if (raw) state.index += 1;
      return scanString(source, state, raw, quote);
    }
    if (IDENTIFIER_START.test(character)) {
      const start = state.index;
      state.index += 1;
      while (IDENTIFIER_PART.test(source[state.index] ?? "")) state.index += 1;
      return { type: "identifier", value: source.slice(start, state.index) };
    }
    state.index += 1;
    return { type: "symbol", value: character };
  }
  return null;
}

function directiveBody(source, state) {
  const body = [];
  let parenDepth = 0;
  while (true) {
    const token = nextToken(source, state);
    if (token === null || state.malformed) return null;
    if (token.value === "(" || token.value === "[") parenDepth += 1;
    if (token.value === ")" || token.value === "]") parenDepth -= 1;
    if (parenDepth < 0) return null;
    if (token.value === ";" && parenDepth === 0) return body;
    body.push(token);
  }
}

function parseUriBody(body, kind) {
  if (body.length === 0 || body[0].type !== "string" || !body[0].literal) return { uncertain: true, directives: [] };
  const directives = [{ kind, uri: body[0].value, conditional: false }];
  let index = 1;
  while (index < body.length) {
    const token = body[index];
    if (token.type !== "identifier") return { uncertain: true, directives };
    if (token.value === "if") {
      if (body[index + 1]?.value !== "(") return { uncertain: true, directives };
      let depth = 1;
      let hasCondition = false;
      index += 2;
      while (index < body.length && depth > 0) {
        if (body[index].value === "(") depth += 1;
        else if (body[index].value === ")") depth -= 1;
        else if (depth > 0) hasCondition = true;
        index += 1;
      }
      const uri = body[index];
      if (depth !== 0 || !hasCondition || uri?.type !== "string" || !uri.literal) return { uncertain: true, directives };
      directives.push({ kind, uri: uri.value, conditional: true });
      index += 1;
      continue;
    }
    if (kind === "IMPORT" && token.value === "deferred") {
      index += 1;
      continue;
    }
    if (kind === "IMPORT" && token.value === "as") {
      if (body[index + 1]?.type !== "identifier") return { uncertain: true, directives };
      index += 2;
      continue;
    }
    if (token.value === "show" || token.value === "hide") {
      index += 1;
      let expectIdentifier = true;
      while (index < body.length && (body[index].type === "identifier" || body[index].value === ",")) {
        if (expectIdentifier !== (body[index].type === "identifier")) return { uncertain: true, directives };
        expectIdentifier = !expectIdentifier;
        index += 1;
      }
      if (expectIdentifier) return { uncertain: true, directives };
      continue;
    }
    return { uncertain: true, directives };
  }
  return { uncertain: false, directives };
}

function parsePartBody(body) {
  if (body.length === 0) return { uncertain: true, directives: [] };
  if (body[0].type === "identifier" && body[0].value === "of") {
    const remainder = body.slice(1);
    if (remainder.length === 1 && remainder[0].type === "string" && remainder[0].literal) {
      return { uncertain: false, directives: [{ kind: "PART_OF", uri: remainder[0].value, conditional: false }] };
    }
    const validName = remainder.length > 0 && remainder[0].type === "identifier" && remainder.every((token, index) => (
      index % 2 === 0 ? token.type === "identifier" : token.value === "."
    ));
    return validName
      ? { uncertain: false, directives: [{ kind: "NAMED_PART_OF", uri: remainder.map((token) => token.value).join(""), conditional: false }] }
      : { uncertain: true, directives: [] };
  }
  return body.length === 1 && body[0].type === "string" && body[0].literal
    ? { uncertain: false, directives: [{ kind: "PART", uri: body[0].value, conditional: false }] }
    : { uncertain: true, directives: [] };
}

function skipMetadata(source, state) {
  const name = nextToken(source, state);
  if (name?.type !== "identifier") return false;
  let token = nextToken(source, state);
  while (token?.value === ".") {
    if (nextToken(source, state)?.type !== "identifier") return false;
    token = nextToken(source, state);
  }
  if (token?.value !== "(") {
    state.pending = token;
    return true;
  }
  let depth = 1;
  while (depth > 0) {
    token = nextToken(source, state);
    if (token === null || state.malformed) return false;
    if (token.value === "(") depth += 1;
    if (token.value === ")") depth -= 1;
  }
  return true;
}

function parseDartDirectives(source) {
  if (typeof source !== "string") return { directives: [], uncertain: true };
  const state = { index: 0, malformed: false, pending: null };
  const directives = [];
  let uncertain = false;
  while (!state.malformed) {
    const token = state.pending ?? nextToken(source, state);
    state.pending = null;
    if (token === null) break;
    if (token.value === "@") {
      if (!skipMetadata(source, state)) uncertain = true;
      continue;
    }
    if (token.type !== "identifier") break;
    if (token.value === "library") {
      const body = directiveBody(source, state);
      const validName = body !== null && (body.length === 0 || (body[0]?.type === "identifier" && body.every((entry, index) => (
        index % 2 === 0 ? entry.type === "identifier" : entry.value === "."
      ))));
      if (!validName) uncertain = true;
      continue;
    }
    if (!["import", "export", "part"].includes(token.value)) break;
    const body = directiveBody(source, state);
    if (body === null) {
      uncertain = true;
      break;
    }
    const parsed = token.value === "part"
      ? parsePartBody(body)
      : parseUriBody(body, token.value.toUpperCase());
    directives.push(...parsed.directives);
    uncertain ||= parsed.uncertain;
  }
  return { directives, uncertain: uncertain || state.malformed };
}

function resolveUri(uri, source, files, packageName) {
  if (typeof uri !== "string" || uri.length === 0 || CONTROL.test(uri) || /[\\?#]/u.test(uri)) return { uncertain: true };
  if (uri.startsWith("dart:")) return { external: true, uriKind: "DART_EXTERNAL" };
  if (uri.startsWith("package:")) {
    const prefix = `package:${packageName}/`;
    if (!uri.startsWith(prefix)) return { external: true, uriKind: "OTHER_PACKAGE_EXTERNAL" };
    const suffix = uri.slice(prefix.length);
    if (suffix.length === 0 || suffix.split("/").some((piece) => piece === "" || piece === "." || piece === "..")) {
      return { uncertain: true };
    }
    const target = path.posix.normalize(`apps/mobile/lib/${suffix}`);
    if (!target.startsWith("apps/mobile/lib/") || !Object.hasOwn(files, target)) return { uncertain: true };
    return { target, uriKind: "OWN_PACKAGE" };
  }
  if (uri.startsWith("/") || uri.includes(":")) return { uncertain: true };
  const target = path.posix.normalize(path.posix.join(path.posix.dirname(source), uri));
  if (!target.startsWith("apps/mobile/") || !Object.hasOwn(files, target)) return { uncertain: true };
  return { target, uriKind: "RELATIVE" };
}

function edgeKey(edge) {
  return [edge.source, edge.target ?? "", edge.kind, edge.uri, edge.uriKind, String(edge.conditional)].join("\0");
}

export function buildImmutableDartSourceGraph({ files, packageName = "easysubway_mobile" }) {
  if (packageName !== "easysubway_mobile") throw new Error("mobile package identity mismatch");
  if (!files || typeof files !== "object" || Array.isArray(files)) throw new Error("Dart files must be an object");
  const normalizedFiles = {};
  for (const [file, source] of Object.entries(files)) {
    if (file.includes("\\") && Object.hasOwn(normalizedFiles, file.replaceAll("\\", "/"))) {
      throw new Error("duplicate normalized immutable Dart graph key");
    }
    const normalized = normalizedPath(file);
    if (Object.hasOwn(normalizedFiles, normalized)) throw new Error("duplicate normalized immutable Dart graph key");
    if (typeof source !== "string") throw new Error("Dart source must be UTF-8 text");
    normalizedFiles[normalized] = source;
  }

  const graph = new Map();
  const uncertainty = new Set();
  const edges = [];
  const partBacklinks = new Map();
  const namedParts = [];
  for (const source of Object.keys(normalizedFiles).sort(compare)) {
    graph.set(source, new Set());
    const parsed = parseDartDirectives(normalizedFiles[source]);
    if (parsed.uncertain) uncertainty.add(source);
    for (const directive of parsed.directives) {
      if (directive.kind === "NAMED_PART_OF") {
        namedParts.push({ source, uri: directive.uri });
        continue;
      }
      const resolved = resolveUri(directive.uri, source, normalizedFiles, packageName);
      if (resolved.uncertain) {
        uncertainty.add(source);
        continue;
      }
      const edge = {
        source,
        target: resolved.target ?? null,
        kind: directive.kind,
        uri: directive.uri,
        uriKind: resolved.uriKind,
        conditional: directive.conditional,
      };
      edges.push(edge);
      if (resolved.target) graph.get(source).add(resolved.target);
      if (directive.kind === "PART" && resolved.target) {
        partBacklinks.set(resolved.target, new Set([...(partBacklinks.get(resolved.target) ?? []), source]));
      }
    }
  }
  for (const named of namedParts) {
    const libraries = partBacklinks.get(named.source) ?? new Set();
    if (libraries.size !== 1) {
      uncertainty.add(named.source);
      continue;
    }
    const target = [...libraries][0];
    edges.push({ source: named.source, target, kind: "PART_OF", uri: named.uri, uriKind: "NAMED_PART", conditional: false });
    graph.get(named.source).add(target);
  }

  edges.sort((a, b) => compare(edgeKey(a), edgeKey(b)));
  const exactEdges = new Set();
  const normalizedTargets = new Set();
  for (const edge of edges) {
    const exact = edgeKey(edge);
    const normalizedTarget = [edge.source, edge.target ?? "", edge.kind].join("\0");
    if (exactEdges.has(exact) || (edge.target && normalizedTargets.has(normalizedTarget))) uncertainty.add(edge.source);
    exactEdges.add(exact);
    if (edge.target) normalizedTargets.add(normalizedTarget);
  }
  const stableGraph = new Map([...graph.entries()].map(([source, targets]) => [source, [...targets].sort(compare)]));
  const reverse = new Map();
  for (const [source, targets] of stableGraph) {
    for (const target of targets) reverse.set(target, [...new Set([...(reverse.get(target) ?? []), source])].sort(compare));
  }
  return {
    sources: Object.keys(normalizedFiles).sort(compare).map((source) => ({ path: source, blobSha256: sha256(normalizedFiles[source]) })),
    edges,
    graph: stableGraph,
    reverse,
    uncertainty: [...uncertainty].sort(compare).map((source) => ({ path: source, code: "GRAPH_UNCERTAINTY" })),
  };
}

export function buildImmutableDartGraph(options) {
  const { graph, reverse, uncertainty } = buildImmutableDartSourceGraph(options);
  return { graph, reverse, uncertainty };
}

export function reverseConsumerFanout(graph, changedPaths) {
  const queue = changedPaths.map((value) => normalizedPath(value, "changed graph path"));
  const seen = new Set(queue);
  const consumers = new Set();
  while (queue.length > 0) {
    for (const consumer of graph.reverse.get(queue.shift()) ?? []) {
      if (seen.has(consumer)) continue;
      seen.add(consumer);
      consumers.add(consumer);
      queue.push(consumer);
    }
  }
  return [...consumers].sort(compare);
}
