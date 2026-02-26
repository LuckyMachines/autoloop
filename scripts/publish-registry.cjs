#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const NPMRC_PATH = path.join(process.cwd(), ".npmrc");

function resolveRegistry() {
  if (process.env.LM_REGISTRY_URL) {
    return process.env.LM_REGISTRY_URL;
  }

  if (!fs.existsSync(NPMRC_PATH)) {
    return null;
  }

  const text = fs.readFileSync(NPMRC_PATH, "utf8");
  const line = text
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.startsWith("registry="));
  return line ? line.slice("registry=".length).trim() : null;
}

const registry = resolveRegistry();
if (!registry) {
  console.error("No registry configured. Set LM_REGISTRY_URL or run registry:set.");
  process.exit(1);
}

const args = ["publish", "--registry", registry, ...process.argv.slice(2)];
const result = spawnSync("npm", args, {
  stdio: "inherit",
  shell: process.platform === "win32",
});

if (typeof result.status === "number") {
  process.exit(result.status);
}
process.exit(1);
