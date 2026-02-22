const fs = require("fs");
const path = require("path");

const contracts = [
    "AutoLoop",
    "AutoLoopRegistry",
    "AutoLoopRegistrar",
    "AutoLoopCompatibleInterface"
];

const outDir = path.join(__dirname, "..", "out");
const abiDir = path.join(__dirname, "..", "abi");

if (!fs.existsSync(abiDir)) {
    fs.mkdirSync(abiDir, { recursive: true });
}

for (const name of contracts) {
    const artifactPath = path.join(outDir, `${name}.sol`, `${name}.json`);
    if (!fs.existsSync(artifactPath)) {
        console.error(`Artifact not found: ${artifactPath}`);
        continue;
    }
    const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
    const abiPath = path.join(abiDir, `${name}.json`);
    fs.writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
    console.log(`Extracted ABI: ${name} -> ${abiPath}`);
}

console.log("ABI extraction complete.");
