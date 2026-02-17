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

function extractAllowlistKeys(luaText) {
  // We only care about keys explicitly set to true in tables.
  const out = new Set();
  const re1 = /\[['"]([^'"]+)['"]\]\s*=\s*true/g;
  let m;
  while ((m = re1.exec(luaText))) out.add(m[1]);
  return out;
}

function extractSchemaKeys(luaText) {
  // Keys assigned to a table literal: ['event'] = { ... }
  const out = new Set();
  const re = /\[['"]([^'"]+)['"]\]\s*=\s*{\s*/g;
  let m;
  while ((m = re.exec(luaText))) out.add(m[1]);
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
  const allowlist = extractAllowlistKeys(firewallTxt);
  const schemas = extractSchemaKeys(firewallTxt);

  const actionEvents = [...registered].filter((e) => e.startsWith("lyxpanel:action:"));
  const missingAllowlist = actionEvents.filter((e) => !allowlist.has(e));
  const missingSchema = actionEvents.filter((e) => !schemas.has(e));

  // Also catch allowlisted actions without schemas (should not happen in hardened mode).
  const allowlistedActions = [...allowlist].filter((e) => e.startsWith("lyxpanel:action:"));
  const allowlistedWithoutSchema = allowlistedActions.filter((e) => !schemas.has(e));

  const issues = [];
  if (missingAllowlist.length) issues.push({ title: "Missing allowlist entries", items: missingAllowlist });
  if (missingSchema.length) issues.push({ title: "Missing schema entries", items: missingSchema });
  if (allowlistedWithoutSchema.length)
    issues.push({ title: "Allowlisted actions without schema", items: allowlistedWithoutSchema });

  if (!issues.length) {
    console.log("[OK] lyxpanel:action:* allowlist + schema coverage looks complete.");
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

