import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

import {
  analyzeGoldenParity,
  readTrackedGoldenFiles,
} from "./mobile-golden-parity.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);

const healthyFixture = () =>
  new Map([
    [
      "apps/mobile/test/features/example/example_golden_test.dart",
      "expect(widget, matchesGoldenFile('goldens/example.png'));\n",
    ],
    [
      "apps/mobile/test/features/example/goldens/example.png",
      Buffer.from("png"),
    ],
  ]);

test("current tracked golden tests and assets have exact parity", () => {
  const result = analyzeGoldenParity(readTrackedGoldenFiles(repositoryRoot));

  assert.equal(result.references.length > 0, true);
  assert.deepEqual(result.findings, []);
});

test("healthy fixture resolves a test-relative literal reference", () => {
  const result = analyzeGoldenParity(healthyFixture());

  assert.deepEqual(result, {
    tests: ["apps/mobile/test/features/example/example_golden_test.dart"],
    references: [
      {
        test: "apps/mobile/test/features/example/example_golden_test.dart",
        asset: "apps/mobile/test/features/example/goldens/example.png",
      },
    ],
    assets: ["apps/mobile/test/features/example/goldens/example.png"],
    findings: [],
  });
});

test("Dart comments and ordinary strings do not create golden references", () => {
  const fixture = healthyFixture();
  fixture.set(
    "apps/mobile/test/features/example/example_golden_test.dart",
    `// matchesGoldenFile('goldens/comment.png')
/* matchesGoldenFile('goldens/block-comment.png') */
const example = "matchesGoldenFile('goldens/string.png')";
expect(widget, matchesGoldenFile('goldens/example.png'));
`,
  );

  assert.deepEqual(analyzeGoldenParity(fixture).findings, []);
});

test("named versions resolve the comparator versioned asset", () => {
  const fixture = new Map([
    [
      "apps/mobile/test/features/example/example_golden_test.dart",
      `expect(
  widget,
  matchesGoldenFile('goldens/example.png', version: 2),
);
`,
    ],
    [
      "apps/mobile/test/features/example/goldens/example.2.png",
      Buffer.from("png"),
    ],
  ]);

  assert.deepEqual(analyzeGoldenParity(fixture), {
    tests: ["apps/mobile/test/features/example/example_golden_test.dart"],
    references: [
      {
        test: "apps/mobile/test/features/example/example_golden_test.dart",
        asset: "apps/mobile/test/features/example/goldens/example.2.png",
      },
    ],
    assets: ["apps/mobile/test/features/example/goldens/example.2.png"],
    findings: [],
  });
});

test("zero, missing, orphan, duplicate and ambiguous references fail closed", () => {
  assert.deepEqual(analyzeGoldenParity(new Map()).findings, [
    { code: "ZERO_GOLDEN_REFERENCE", path: "apps/mobile/test" },
  ]);

  const missing = healthyFixture();
  missing.delete("apps/mobile/test/features/example/goldens/example.png");
  assert.deepEqual(analyzeGoldenParity(missing).findings, [
    {
      code: "MISSING_GOLDEN_ASSET",
      path: "apps/mobile/test/features/example/goldens/example.png",
      test: "apps/mobile/test/features/example/example_golden_test.dart",
    },
  ]);

  const orphan = healthyFixture();
  orphan.set(
    "apps/mobile/test/features/example/goldens/orphan.png",
    Buffer.from("png"),
  );
  assert.deepEqual(analyzeGoldenParity(orphan).findings, [
    {
      code: "ORPHAN_GOLDEN_ASSET",
      path: "apps/mobile/test/features/example/goldens/orphan.png",
    },
  ]);

  const duplicate = healthyFixture();
  duplicate.set(
    "apps/mobile/test/features/example/second_golden_test.dart",
    "expect(widget, matchesGoldenFile('goldens/example.png'));\n",
  );
  assert.deepEqual(analyzeGoldenParity(duplicate).findings, [
    {
      code: "DUPLICATE_GOLDEN_REFERENCE",
      path: "apps/mobile/test/features/example/goldens/example.png",
      tests: [
        "apps/mobile/test/features/example/example_golden_test.dart",
        "apps/mobile/test/features/example/second_golden_test.dart",
      ],
    },
  ]);

  const ambiguous = healthyFixture();
  ambiguous.set(
    "apps/mobile/test/features/example/example_golden_test.dart",
    "expect(widget, matchesGoldenFile(assetPath));\n",
  );
  assert.deepEqual(analyzeGoldenParity(ambiguous).findings, [
    {
      code: "AMBIGUOUS_GOLDEN_REFERENCE",
      path: "apps/mobile/test/features/example/example_golden_test.dart",
    },
    {
      code: "ORPHAN_GOLDEN_ASSET",
      path: "apps/mobile/test/features/example/goldens/example.png",
    },
    { code: "ZERO_GOLDEN_REFERENCE", path: "apps/mobile/test" },
  ]);
});
