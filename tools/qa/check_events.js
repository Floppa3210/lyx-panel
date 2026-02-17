#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * LyxPanel QA - Offline event/schema coverage checker
 *
 * Goals:
 * - Ensure every `RegisterNetEvent('lyxpanel:action:*')` has:
 *   - allowlist entry in `server/event_firewall.lua`
 *   - schema entry in `server/event_firewall.lua`
 *
 * This is static analysis (no FiveM runtime required).
 */

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function listFilesRecursive(dir, predicate) {
  const out = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) out.push(...listFilesRecursive(full, predicate));
    else if (!predicate || predicate(full)) out.push(full);
  }
  return out;
}

function extractRegisterNetEvents(luaText) {
  const out = new Set();
  const re = /RegisterNetEvent\s*\(\s*['"]([^'"]+)['"]/g;
  let m;
  while ((m = re.exec(luaText))) out.add(m[1]);
  return out;
}

function extractLuaTableBlock(luaText, tableName) {
  // Very small Lua parser for `local <name> = { ... }` style tables.
  // Goal is to avoid false positives by only scanning the specific tables we care about.
  const re = new RegExp(`\\b${tableName}\\b\\s*=\\s*{`);
  const m = re.exec(luaText);
  if (!m) return null;

  let i = m.index + m[0].length - 1; // points to the opening "{"
  let depth = 0;
  let start = -1;
  let end = -1;

  let inSingle = false;
  let inDouble = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (; i < luaText.length; i++) {
    const ch = luaText[i];
    const next = i + 1 < luaText.length ? luaText[i + 1] : "";
    const next2 = i + 2 < luaText.length ? luaText[i + 2] : "";
    const next3 = i + 3 < luaText.length ? luaText[i + 3] : "";

    if (inLineComment) {
      if (ch === "\n") inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (ch === "]" && next === "]") {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (inSingle) {
      if (ch === "\\") {
        i++;
        continue;
      }
      if (ch === "'") inSingle = false;
      continue;
    }
    if (inDouble) {
      if (ch === "\\") {
        i++;
        continue;
      }
      if (ch === '"') inDouble = false;
      continue;
    }

    if (ch === "-" && next === "-") {
      if (next2 === "[" && next3 === "[") {
        inBlockComment = true;
        i += 3;
      } else {
        inLineComment = true;
        i++;
      }
      continue;
    }
    if (ch === "'") {
      inSingle = true;
      continue;
    }
    if (ch === '"') {
      inDouble = true;
      continue;
    }

    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
      continue;
    }
    if (ch === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
      continue;
    }
  }

  if (start === -1 || end === -1) return null;
  return luaText.slice(start, end + 1);
}

function extractAllowlistKeysFromBlock(luaBlockText) {
  const out = new Set();
  if (!luaBlockText) return out;
  const re = /\[['"]([^'"]+)['"]\]\s*=\s*true/g;
  let m;
  while ((m = re.exec(luaBlockText))) out.add(m[1]);
  return out;
}

function extractTableKeysFromBlock(luaBlockText) {
  const out = new Set();
  if (!luaBlockText) return out;
  const re = /\[['"]([^'"]+)['"]\]\s*=\s*{\s*/g;
  let m;
  while ((m = re.exec(luaBlockText))) out.add(m[1]);
  return out;
}

function main() {
  const serverDir = path.join(REPO_ROOT, "server");
  const firewallPath = path.join(serverDir, "event_firewall.lua");
  if (!fs.existsSync(firewallPath)) {
    console.error("Missing:", firewallPath);
    process.exit(2);
  }

  const luaFiles = listFilesRecursive(serverDir, (p) => p.endsWith(".lua"));
  const registered = new Set();
  for (const f of luaFiles) {
    const txt = readText(f);
    for (const e of extractRegisterNetEvents(txt)) registered.add(e);
  }

  const firewallTxt = readText(firewallPath);
  const allowlistBlock = extractLuaTableBlock(firewallTxt, "DefaultAllowlist");
  const schemasBlock = extractLuaTableBlock(firewallTxt, "DefaultSchemas");
  const protectedBlock = extractLuaTableBlock(firewallTxt, "DefaultProtectedEvents");

  const allowlist = extractAllowlistKeysFromBlock(allowlistBlock);
  const schemas = extractTableKeysFromBlock(schemasBlock);
  const protectedEvents = extractTableKeysFromBlock(protectedBlock);

  const actionEvents = [...registered].filter((e) => e.startsWith("lyxpanel:action:"));
  const missingAllowlist = actionEvents.filter((e) => !allowlist.has(e));
  const missingSchema = actionEvents.filter((e) => !schemas.has(e));

  // Also catch allowlisted actions without schemas (should not happen in hardened mode).
  const allowlistedActions = [...allowlist].filter((e) => e.startsWith("lyxpanel:action:"));
  const allowlistedWithoutSchema = allowlistedActions.filter((e) => !schemas.has(e));

  const mustBeProtected = [
    "lyxpanel:danger:approve",
    "lyxpanel:reports:claim",
    "lyxpanel:reports:resolve",
    "lyxpanel:reports:get",
    "lyxpanel:staffcmd:requestRevive",
    "lyxpanel:staffcmd:requestInstantRespawn",
    "lyxpanel:staffcmd:requestAmmoRefill",
  ];
  const missingProtected = mustBeProtected.filter((e) => !protectedEvents.has(e));
  const missingProtectedSchema = mustBeProtected.filter((e) => !schemas.has(e));

  // Ensure every protected event has an explicit schema (we want schema coverage for all sensitive events).
  const protectedWithoutSchema = [...protectedEvents].filter((e) => !schemas.has(e));

  // Strong mode: every lyxpanel:* server event should have a schema entry in DefaultSchemas.
  const lyxpanelServerEvents = [...registered].filter((e) => e.startsWith("lyxpanel:"));
  const missingSchemaLyxpanel = lyxpanelServerEvents.filter((e) => !schemas.has(e));

  const issues = [];
  if (missingAllowlist.length) issues.push({ title: "Missing allowlist entries", items: missingAllowlist });
  if (missingSchema.length) issues.push({ title: "Missing schema entries", items: missingSchema });
  if (allowlistedWithoutSchema.length)
    issues.push({ title: "Allowlisted actions without schema", items: allowlistedWithoutSchema });
  if (missingProtected.length)
    issues.push({ title: "Missing protected critical events", items: missingProtected });
  if (missingProtectedSchema.length)
    issues.push({ title: "Missing schema for critical protected events", items: missingProtectedSchema });
  if (protectedWithoutSchema.length)
    issues.push({ title: "Protected events without schema", items: protectedWithoutSchema });
  if (missingSchemaLyxpanel.length)
    issues.push({ title: "lyxpanel:* server events without schema", items: missingSchemaLyxpanel });

  if (!issues.length) {
    console.log("[OK] lyxpanel events: allowlist + schema + protected coverage look complete.");
    return;
  }

  console.error("[FAIL] Event/schema coverage issues found:\n");
  for (const g of issues) {
    console.error("==", g.title);
    for (const it of g.items.sort()) console.error("-", it);
    console.error("");
  }
  process.exit(1);
}

main();
