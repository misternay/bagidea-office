"use strict";
// Cross-platform runtime hook wiring for the daemon (issue #15, Bug 4).
//
// The committed workspace/.claude/settings.json is a placeholder — it carries
// no absolute path because the dev machine's path means nothing on anyone
// else's box. The installer's wire-hooks.{sh,ps1} rewrite this file at build
// and update time, but those only fire on `bagidea update` / build scripts.
// If a user clones and runs the daemon directly (dev workflow, `node
// server.js`), the placeholder is used as-is and the Security Center never
// fires.
//
// This module is the safety net: the daemon rewrites settings.json on every
// start, pointing at THIS install's perm hook via __dirname (runtime-absolute,
// same on macOS/Linux/Windows). It mirrors wire-hooks.sh's format exactly so
// nothing downstream breaks. Idempotent — only writes when the content changes.
const fs = require("fs");
const path = require("path");

// Build the {workspace}/.claude/settings.json content for a PreToolUse hook
// pointing at perm.js. Pure function — testable without touching disk.
function buildWorkspaceSettings(permJsAbsPath) {
  return JSON.stringify({
    hooks: {
      PreToolUse: [
        { hooks: [ { type: "command", command: `node ${JSON.stringify(permJsAbsPath)}`, timeout: 60 } ] }
      ]
    }
  }, null, 2);
}

// Rewrite {workspaceDir}/.claude/settings.json so it resolves to this install.
// Returns true if a write happened (or was needed and failed loudly), false if
// the file already matched.
function wireWorkspaceSettings(workspaceDir, daemonDir) {
  const permJs = path.join(daemonDir, "perm.js");
  const cfgDir = path.join(workspaceDir, ".claude");
  const cfgFile = path.join(cfgDir, "settings.json");
  const want = buildWorkspaceSettings(permJs) + "\n";
  try { if (fs.readFileSync(cfgFile, "utf8") === want) return false; } catch {}
  try { fs.mkdirSync(cfgDir, { recursive: true }); } catch {}
  fs.writeFileSync(cfgFile, want);
  return true;
}

module.exports = { buildWorkspaceSettings, wireWorkspaceSettings };
