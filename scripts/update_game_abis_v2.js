#!/usr/bin/env node
/**
 * update_game_abis_v2.js
 *
 * Adds KaijuOracle and ForecasterLeaderboard ABIs to game-abis.ts,
 * adds clashWinners to kaijuLeagueABI, updates GameSlug type,
 * GAME_META, and gameContracts addresses.
 *
 * Run from autoloop/ directory:
 *   node scripts/update_game_abis_v2.js
 */

const fs = require("fs");
const path = require("path");

const DASHBOARD_DIR = path.join(
  __dirname,
  "..",
  "..",
  "autoloop-dashboard-v2",
  "src",
  "lib"
);
const FILE = path.join(DASHBOARD_DIR, "game-abis.ts");

const OUT_DIR = path.join(__dirname, "..", "out");

function loadAbi(contractPath, contractName) {
  const filePath = path.join(OUT_DIR, contractPath, `${contractName}.json`);
  const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  return data.abi;
}

function abiToTs(abi) {
  return JSON.stringify(abi, null, 2)
    .split("\n")
    .map((line) => "  " + line)
    .join("\n");
}

// Load ABIs from build artifacts
const kaijuOracleAbi = loadAbi("KaijuOracle.sol", "KaijuOracle");
const forecasterLeaderboardAbi = loadAbi(
  "ForecasterLeaderboard.sol",
  "ForecasterLeaderboard"
);
const kaijuLeagueAbi = loadAbi("KaijuLeague.sol", "KaijuLeague");

// Read current file
let content = fs.readFileSync(FILE, "utf-8");

// ================================================================
// 1. Add clashWinners to kaijuLeagueABI
// ================================================================
const clashWinnersEntry = {
  type: "function",
  name: "clashWinners",
  inputs: [{ name: "", type: "uint256", internalType: "uint256" }],
  outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
  stateMutability: "view",
};

// Find if clashWinners is already in the kaijuLeagueABI section of the file
if (!content.includes('"clashWinners"')) {
  // Find the currentClashId entry in kaijuLeagueABI and add clashWinners after it
  const marker = '"currentClashId"';
  const kaijuSection = content.indexOf("// KaijuLeague");
  if (kaijuSection === -1) {
    console.error("Could not find KaijuLeague ABI section");
    process.exit(1);
  }
  // Find the currentClashId entry within the kaijuLeague section
  const currentClashIdIdx = content.indexOf(marker, kaijuSection);
  if (currentClashIdIdx === -1) {
    console.error("Could not find currentClashId in kaijuLeagueABI");
    process.exit(1);
  }
  // Find the end of that entry (next opening brace at the same depth)
  // Navigate to end of this function entry block
  let depth = 0;
  let i = currentClashIdIdx;
  // Go back to find the opening { of this entry
  while (i > kaijuSection && content[i] !== "{") i--;
  let entryStart = i;
  for (i = entryStart; i < content.length; i++) {
    if (content[i] === "{") depth++;
    if (content[i] === "}") { depth--; if (depth === 0) break; }
  }
  let entryEnd = i + 1;
  // Insert after the closing brace + comma
  // Find the comma after the entry
  let insertAt = entryEnd;
  while (insertAt < content.length && /[ \t]/.test(content[insertAt])) insertAt++;
  if (content[insertAt] === ",") insertAt++;

  const newEntry = `
  {
    "type": "function",
    "name": "clashWinners",
    "inputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
    "outputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
    "stateMutability": "view"
  },`;

  content = content.slice(0, insertAt) + newEntry + content.slice(insertAt);
  console.log("Added clashWinners to kaijuLeagueABI");
} else {
  console.log("clashWinners already present in kaijuLeagueABI");
}

// ================================================================
// 2. Add KaijuOracle ABI before the GameSlug section
// ================================================================
const gameslugMarker = "// =================================================================\n\nexport type GameSlug";
const gameslugIdx = content.indexOf(gameslugMarker);
if (gameslugIdx === -1) {
  console.error("Could not find GameSlug marker");
  process.exit(1);
}

if (!content.includes("kaijuOracleABI")) {
  const kaijuOracleTs = `
// KaijuOracle (${kaijuOracleAbi.length} entries)
export const kaijuOracleABI = ${abiToTs(kaijuOracleAbi)} as const satisfies Abi;

`;
  content = content.slice(0, gameslugIdx) + kaijuOracleTs + content.slice(gameslugIdx);
  console.log("Added kaijuOracleABI");
} else {
  console.log("kaijuOracleABI already present");
}

// Re-find gameslugIdx after insertion
const gameslugIdx2 = content.indexOf(gameslugMarker);

if (!content.includes("forecasterLeaderboardABI")) {
  const forecasterTs = `
// ForecasterLeaderboard (${forecasterLeaderboardAbi.length} entries)
export const forecasterLeaderboardABI = ${abiToTs(forecasterLeaderboardAbi)} as const satisfies Abi;

`;
  content =
    content.slice(0, gameslugIdx2) +
    forecasterTs +
    content.slice(gameslugIdx2);
  console.log("Added forecasterLeaderboardABI");
} else {
  console.log("forecasterLeaderboardABI already present");
}

// ================================================================
// 3. Update GameSlug type
// ================================================================
const oldSlugType = `export type GameSlug = "pitrow" | "gladiator-arena" | "mech-brawl" | "sorcerer-duel" | "kaiju-league" | "void-harvester" | "sponsor-auction" | "gladiator-oracle" | "oracle-run";`;
const newSlugType = `export type GameSlug = "pitrow" | "gladiator-arena" | "mech-brawl" | "sorcerer-duel" | "kaiju-league" | "void-harvester" | "sponsor-auction" | "gladiator-oracle" | "oracle-run" | "kaiju-oracle" | "forecaster-leaderboard";`;

if (content.includes(oldSlugType)) {
  content = content.replace(oldSlugType, newSlugType);
  console.log("Updated GameSlug type");
} else if (content.includes(newSlugType)) {
  console.log("GameSlug already updated");
} else {
  console.error("Could not find GameSlug type to update");
}

// ================================================================
// 4. Update GAME_META — add new entries
// ================================================================
const gamemetaEnd = `  "oracle-run": {
    name: "OracleRun",
    description: "Permadeath dungeon crawl with escalating difficulty. Characters roll against VRF-derived difficulty each floor — mempool snooping would break fairness.",
    type: "VRF",
    href: "/games/oracle-run",
  },
};`;

const newGamemetaEnd = `  "oracle-run": {
    name: "OracleRun",
    description: "Permadeath dungeon crawl with escalating difficulty. Characters roll against VRF-derived difficulty each floor — mempool snooping would break fairness.",
    type: "VRF",
    href: "/games/oracle-run",
  },
  "kaiju-oracle": {
    name: "KaijuOracle",
    description: "Predict which kaiju wins the next KaijuLeague clash. Commit your pick, reveal it, and split the pot if you called it right — cross-contract coordination that only AutoLoop can guarantee.",
    type: "Cross-contract",
    href: "/games/kaiju-oracle",
  },
  "forecaster-leaderboard": {
    name: "ForecasterLeaderboard",
    description: "Track prediction accuracy across KaijuOracle rounds. AutoLoop fires weekly to score accuracy, distribute prizes to top forecasters, and reset for the next season.",
    type: "3-contract chain",
    href: "/games/forecaster-leaderboard",
  },
};`;

if (content.includes(gamemetaEnd)) {
  content = content.replace(gamemetaEnd, newGamemetaEnd);
  console.log("Updated GAME_META");
} else if (content.includes('"kaiju-oracle"')) {
  console.log("GAME_META already has kaiju-oracle");
} else {
  console.error("Could not find GAME_META end marker");
}

// ================================================================
// 5. Update gameContracts addresses
// ================================================================
const oldContracts = `  11155111: {  // sepolia — redeployed 2026-04-12 (GladiatorOracle replaces PhantomDriver)
    "pitrow":           "0xCA4f1e0F14B8e328F6a588F42b70DDcFE2b3518C",
    "gladiator-arena":  "0x1036877C679d21ffdDc9D65CcbC482baA457b807",
    "mech-brawl":       "0x009B92a87aD918A7d4e61AD243C7A30e50F5144c",
    "sorcerer-duel":    "0x6BCafCF593e95d94B2c6764562B2f94c3d929ecd",
    "kaiju-league":     "0x023B005510380f5FE9B694D24e65621dF931d772",
    "void-harvester":   "0x1bE5229dF63401BD6EcDD5470D8087ab1BCFD320",
    "sponsor-auction":  "0xAF6754aFe774b58C61468b73D61069Adc7d68480",
    "gladiator-oracle": "0x4fcCC531e2D63197E99Db7D59b5a8105e3EB4204",
    "oracle-run":       "0xb908a279DA19AB2d52C53Caa83479b07e757e65d",
  },`;

const newContracts = `  11155111: {  // sepolia — redeployed 2026-04-12 (KaijuOracle + ForecasterLeaderboard added; all 11 contracts)
    "pitrow":                  "0xF4a14c3E110553Ef8e2Cc0F45C7E358BEA392f94",
    "gladiator-arena":         "0x40cB395f8326353502De2a9D253c2E8d270d2721",
    "mech-brawl":              "0x39A74f9EBA61eB3b20b9F7eF92260715d24e986F",
    "sorcerer-duel":           "0x9B24f3036cC2A815e0C3a2400269253219F73204",
    "kaiju-league":            "0x113a741b4c5e5334F408f04eAf4EEEc4D1F57d82",
    "void-harvester":          "0xF78F4e54306F2B589499284765baB86D3AbB3416",
    "sponsor-auction":         "0x9D58246ba447387D399BC2987630e7907911164c",
    "gladiator-oracle":        "0x1F89db70C8A928ce19f5953c1469dfE9ae3f40CE",
    "oracle-run":              "0x1826D2F9031A1879dEce75501FDbD577b2622DF7",
    "kaiju-oracle":            "0x2E5AC919980D42124eB54544060a819A45dBC5F7",
    "forecaster-leaderboard":  "0x6e956bD7e85C33Be09Ff913274896C6544285874",
  },`;

if (content.includes(oldContracts)) {
  content = content.replace(oldContracts, newContracts);
  console.log("Updated gameContracts addresses");
} else if (content.includes("0xF4a14c3E110553Ef8e2Cc0F45C7E358BEA392f94")) {
  console.log("gameContracts already updated with new addresses");
} else {
  console.error("Could not find gameContracts to update");
}

// Write file
fs.writeFileSync(FILE, content, "utf-8");
console.log("\nDone. File written:", FILE);
