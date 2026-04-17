// Local JavaScript action — zero dependencies so we never need a runtime
// `npm install`. The Actions runner provides a recent Node 20.
//
// Reads INPUT_PAYLOAD, writes a reversed string to GITHUB_OUTPUT and a
// summary block to GITHUB_STEP_SUMMARY.

const fs = require("fs");
const os = require("os");

const payload = process.env.INPUT_PAYLOAD ?? "";
const reversed = [...payload].reverse().join("");

const outPath = process.env.GITHUB_OUTPUT;
if (outPath) {
  fs.appendFileSync(outPath, `reversed=${reversed}${os.EOL}`);
}

const summaryPath = process.env.GITHUB_STEP_SUMMARY;
if (summaryPath) {
  fs.appendFileSync(
    summaryPath,
    `## javascript-smoke${os.EOL}` +
      `- payload: \`${payload}\`${os.EOL}` +
      `- reversed: \`${reversed}\`${os.EOL}` +
      `- node: \`${process.version}\`${os.EOL}` +
      `- platform: \`${process.platform}/${process.arch}\`${os.EOL}`,
  );
}

console.log(`javascript-smoke: ${payload} -> ${reversed}`);
