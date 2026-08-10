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
    inputs:
      observed_at:
        required: true
        type: string

permissions:
  contents: read
  actions: read

jobs:
  receipt:
    uses: AquilaXk/easysubway/.github/workflows/public-sensitivity-owner-receipt.yml@fa2f2602573651af6694e7f56077414b685987b9
    with:
      observed_at: \${{ inputs.observed_at }}
    secrets:
      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}
`;

function assertExactCallerWorkflow(workflow) {
  assert.equal(workflow, callerWorkflow);
}

test("public sensitivity owner receipt caller는 고정된 최소 reusable workflow 계약만 사용한다", async () => {
  assertExactCallerWorkflow(await readFile(callerPath, "utf8"));
});

test("public sensitivity owner receipt caller는 observed_at 및 최소 호출 계약의 변이를 거부한다", () => {
  const mutations = [
    ["missing observed_at input", "    inputs:\n      observed_at:\n        required: true\n        type: string\n"],
    ["wrong observed_at type", "type: string", "type: boolean"],
    [
      "default observed_at",
      "        required: true\n        type: string",
      "        required: true\n        default: 2026-08-10T00:00:00Z\n        type: string",
    ],
    [
      "missing observed_at forwarding",
      "    with:\n      observed_at: \${{ inputs.observed_at }}\n",
    ],
    [
      "extra observed_at forwarding",
      "      observed_at: \${{ inputs.observed_at }}",
      "      observed_at: \${{ inputs.observed_at }}\n      extra: value",
    ],
    [
      "wrong observed_at forwarding",
      "      observed_at: \${{ inputs.observed_at }}",
      "      observed_at: \${{ github.event.inputs.observed_at }}",
    ],
    [
      "old reusable workflow pin",
      "@fa2f2602573651af6694e7f56077414b685987b9",
      "@3d1590baa98c929ceabd0d2d44414cebcc643c6f",
    ],
    ["mutable reusable workflow pin", "@fa2f2602573651af6694e7f56077414b685987b9", "@main"],
    [
      "extra secret",
      "    secrets:\n",
      "    secrets:\n      EXTRA_SECRET: \${{ secrets.EXTRA_SECRET }}\n",
    ],
    ["extra permission", "  actions: read", "  actions: read\n  issues: read"],
    [
      "extra job",
      "      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}\n",
      "      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}\n\n  audit:\n    runs-on: ubuntu-latest\n",
    ],
  ];

  for (const [name, search, replacement = ""] of mutations) {
    const mutated = callerWorkflow.replace(search, replacement);

    assert.notEqual(mutated, callerWorkflow, `${name} mutation must change fixture`);
    assert.throws(() => assertExactCallerWorkflow(mutated), { name: "AssertionError" });
  }
});

test("Mobile CI는 owner receipt caller contract test를 한 번 발견한다", async () => {
  const ci = await readFile(ciPath, "utf8");
  const discoveryLine =
    "            tools/ci/public-sensitivity-owner-receipt-caller.test.mjs";

  assert.equal(ci.split(discoveryLine).length - 1, 1);
});
