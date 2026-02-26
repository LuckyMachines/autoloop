#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = process.cwd();
const NPMRC_PATH = path.join(ROOT, ".npmrc");

const DEFAULTS = {
  local: process.env.LM_REGISTRY_LOCAL_URL || "http://localhost:4873",
  staging:
    process.env.LM_REGISTRY_STAGING_URL ||
    "https://staging-packages.luckymachines.io",
  prod:
    process.env.LM_REGISTRY_PROD_URL || "https://packages.luckymachines.io",
};

function usage() {
  console.log(
    "Usage: node scripts/registry-config.cjs [show|ping|local|staging|prod|custom <url>]"
  );
}

function parseRegistryFromNpmrc() {
  if (!fs.existsSync(NPMRC_PATH)) return null;
  const text = fs.readFileSync(NPMRC_PATH, "utf8");
  const line = text
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.startsWith("registry="));
  return line ? line.slice("registry=".length).trim() : null;
}

function writeNpmrc(registry) {
  const strictSsl = registry.startsWith("https://") ? "true" : "false";
  const lines = [
    `registry=${registry}`,
    `@luckymachines:registry=${registry}`,
    "omit-lockfile-registry-resolved=true",
    `strict-ssl=${strictSsl}`,
  ];
  fs.writeFileSync(NPMRC_PATH, `${lines.join("\n")}\n`, "utf8");
  console.log(`Updated .npmrc -> ${registry}`);
}

function runNpmPing(registry) {
  const result = spawnSync("npm", ["ping", "--registry", registry], {
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  if (typeof result.status === "number") {
    process.exit(result.status);
  }
  process.exit(1);
}

const mode = (process.argv[2] || "show").toLowerCase();

if (mode === "show") {
  const registry = parseRegistryFromNpmrc() || "(not configured)";
  console.log(registry);
  process.exit(0);
}

if (mode === "ping") {
  const registry = parseRegistryFromNpmrc();
  if (!registry) {
    console.error("No registry configured. Run registry:set first.");
    process.exit(1);
  }
  runNpmPing(registry);
}

if (mode === "custom") {
  const custom = process.argv[3];
  if (!custom) {
    usage();
    process.exit(1);
  }
  writeNpmrc(custom);
  process.exit(0);
}

if (!Object.prototype.hasOwnProperty.call(DEFAULTS, mode)) {
  usage();
  process.exit(1);
}

writeNpmrc(DEFAULTS[mode]);
