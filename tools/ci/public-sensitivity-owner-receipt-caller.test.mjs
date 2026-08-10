import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const callerPath = path.join(
  repositoryRoot,
  ".github/workflows/public-sensitivity-owner-receipt-caller.yml",
);
const ciPath = path.join(repositoryRoot, ".github/workflows/ci.yml");
const callerWorkflow = `name: Public Sensitivity Owner Receipt Caller

on:
  workflow_dispatch:

permissions:
  contents: read
  actions: read

jobs:
  receipt:
    uses: AquilaXk/easysubway/.github/workflows/public-sensitivity-owner-receipt.yml@3d1590baa98c929ceabd0d2d44414cebcc643c6f
    secrets:
      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}
`;

test("public sensitivity owner receipt caller는 고정된 최소 reusable workflow 계약만 사용한다", async () => {
  assert.equal(await readFile(callerPath, "utf8"), callerWorkflow);
});

test("Mobile CI는 owner receipt caller contract test를 한 번 발견한다", async () => {
  const ci = await readFile(ciPath, "utf8");
  const discoveryLine =
    "            tools/ci/public-sensitivity-owner-receipt-caller.test.mjs";

  assert.equal(ci.split(discoveryLine).length - 1, 1);
});
