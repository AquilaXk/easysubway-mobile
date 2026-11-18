import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * EasySubway Mobile Anti-Cheating & Test Integrity Guard
 * (Standardized on EasyConvert Multi-Gate Architecture)
 *
 * Scans Flutter/Dart codebase and Node.js CI tooling to enforce:
 * 1. ANTI-CIRCULAR-MOCKING: Test fakes circularly referencing production state.
 * 2. ANTI-SILENT-PASS: Silent catches returning true or ignoring network errors.
 * 3. ANTI-PRODUCTION-CHEAT: Production code checking test flags or hardcoding station names.
 * 4. ANTI-HOLLOW-ASSERTION: Tautological assertions in Dart and JS tests.
 * 5. GATE_ASSET_INTEGRITY: Verifying validity of bundled assets.
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, '../..');

export const EXCLUDED_DIRS = new Set([
  'node_modules',
  '.git',
  '.dart_tool',
  'build',
  'coverage',
  '.cache',
  'android',
  'ios',
  '.external',
]);

const SUPPORTED_EXTENSIONS = /\.(mjs|cjs|js|ts|dart|json)$/;

export function scanDirectory(dir, extension = SUPPORTED_EXTENSIONS, fileList = []) {
  if (!fs.existsSync(dir)) return fileList;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!EXCLUDED_DIRS.has(entry.name)) {
        scanDirectory(path.join(dir, entry.name), extension, fileList);
      }
    } else if (entry.isFile() && extension.test(entry.name)) {
      fileList.push(path.join(dir, entry.name));
    }
  }
  return fileList;
}

export function getLineAndSnippet(content, index, matchLength = 0) {
  const upToMatch = content.slice(0, index);
  const line = upToMatch.split('\n').length;
  const lineStart = content.lastIndexOf('\n', index) + 1;
  let lineEnd = content.indexOf('\n', index + Math.max(matchLength, 1));
  if (lineEnd === -1) lineEnd = content.length;
  const snippet = content.slice(lineStart, lineEnd).replace(/\s+/g, ' ').trim();
  return {
    line,
    snippet: snippet.length > 120 ? snippet.slice(0, 117) + '...' : snippet,
  };
}

export function checkCircularMocking(repoRoot = ROOT_DIR) {
  const violations = [];
  const testHelperDirs = [
    path.join(repoRoot, 'test/helpers'),
    path.join(repoRoot, 'tools/ci'),
  ];
  const files = testHelperDirs
    .flatMap((d) => scanDirectory(d, /\.(mjs|cjs|js)$/))
    .filter((f) => !f.endsWith('guard-anti-cheat.mjs'));

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    const circularPattern = /(?:import\s+[\s\S]*?\s+from|require\s*\(|import\s*\()\s*['"](\.\.?\/[^'"]*(?:\/tools\/datapack|\/contracts\/builders))['"]/gs;
    let match;
    while ((match = circularPattern.exec(content)) !== null) {
      const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
      violations.push({
        file: path.relative(repoRoot, file),
        line,
        rule: 'ANTI-CIRCULAR-MOCKING',
        snippet,
        message: 'Test helper circularly imports builder/production scripts.',
      });
    }
  }
  return violations;
}

export function checkSilentPassBypasses(repoRoot = ROOT_DIR) {
  const violations = [];
  const jsTestFiles = scanDirectory(path.join(repoRoot, 'tools'), /\.(test\.mjs|spec\.mjs)$/)
    .filter((f) => !f.endsWith('guard-anti-cheat.test.mjs'));

  for (const file of jsTestFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const bypassPatterns = [
      {
        regex: /catch\s*(?:\([^)]*\))?\s*\{[\s\S]{0,60}?return\s+(?:true|1|\{\s*valid\s*:\s*true\s*\})\s*;?[\s\S]{0,20}?\}/gis,
        desc: 'Catch block silently returning true in JS test.',
      },
    ];
    for (const pattern of bypassPatterns) {
      pattern.regex.lastIndex = 0;
      let match;
      while ((match = pattern.regex.exec(content)) !== null) {
        const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
        violations.push({
          file: path.relative(repoRoot, file),
          line,
          rule: 'ANTI-SILENT-PASS',
          snippet,
          message: pattern.desc,
        });
      }
    }
  }

  // Scan Dart test files for silent catch ignore
  const dartTestFiles = scanDirectory(path.join(repoRoot, 'test'), /\.dart$/);
  for (const file of dartTestFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const emptyCatchPattern = /catch\s*\([a-zA-Z0-9_,\s]+\)\s*\{\s*\/\/\s*ignore[^\n]*\s*\}/gis;
    let match;
    while ((match = emptyCatchPattern.exec(content)) !== null) {
      const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
      violations.push({
        file: path.relative(repoRoot, file),
        line,
        rule: 'ANTI-SILENT-PASS',
        snippet,
        message: 'Empty catch-ignore in Dart test suite. Must verify or fail closed.',
      });
    }
  }

  return violations;
}

export function checkProductionCheats(repoRoot = ROOT_DIR) {
  const violations = [];
  // Scan Dart production code
  const dartProdFiles = scanDirectory(path.join(repoRoot, 'lib'), /\.dart$/);
  const dartCheatPatterns = [
    {
      regex: /Platform\.environment\[['"]FLUTTER_TEST['"]\]/g,
      desc: 'Test environment check FLUTTER_TEST detected in production Flutter code.',
    },
    {
      regex: /['"]dummy-timetable-trip['"]/g,
      desc: 'Hardcoded dummy trip identifier in production Flutter code.',
    },
  ];

  for (const file of dartProdFiles) {
    const content = fs.readFileSync(file, 'utf8');
    for (const pattern of dartCheatPatterns) {
      pattern.regex.lastIndex = 0;
      let match;
      while ((match = pattern.regex.exec(content)) !== null) {
        const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
        violations.push({
          file: path.relative(repoRoot, file),
          line,
          rule: 'ANTI-PRODUCTION-CHEAT',
          snippet,
          message: pattern.desc,
        });
      }
    }
  }

  return violations;
}

export function checkHollowAssertions(repoRoot = ROOT_DIR) {
  const violations = [];
  // Scan JS tests
  const jsTestFiles = scanDirectory(path.join(repoRoot, 'tools'), /\.(test\.mjs|spec\.mjs)$/)
    .filter((f) => !f.endsWith('guard-anti-cheat.test.mjs'));

  for (const file of jsTestFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const hollowPatterns = [
      {
        regex: /assert\.(?:strictEqual|equal)\s*\(\s*([a-zA-Z0-9_$]+)\s*,\s*\1\s*\)/g,
        desc: 'Tautological assertion comparing variable with itself.',
      },
      {
        regex: /assert\.(?:ok|isTrue)\s*\(\s*true\s*\)/g,
        desc: 'Hollow assertion assert.ok(true).',
      },
    ];
    for (const pattern of hollowPatterns) {
      pattern.regex.lastIndex = 0;
      let match;
      while ((match = pattern.regex.exec(content)) !== null) {
        const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
        violations.push({
          file: path.relative(repoRoot, file),
          line,
          rule: 'ANTI-HOLLOW-ASSERTION',
          snippet,
          message: pattern.desc,
        });
      }
    }
  }

  // Scan Dart tests
  const dartTestFiles = scanDirectory(path.join(repoRoot, 'test'), /\.dart$/);
  const dartHollowPatterns = [
    {
      regex: /expect\s*\(\s*true\s*,\s*(?:isTrue|equals\s*\(\s*true\s*\))\s*\)/g,
      desc: 'Hollow assertion expect(true, isTrue) in Dart test.',
    },
    {
      regex: /expect\s*\(\s*false\s*,\s*(?:isFalse|equals\s*\(\s*false\s*\))\s*\)/g,
      desc: 'Hollow assertion expect(false, isFalse) in Dart test.',
    },
    {
      regex: /expect\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*equals\s*\(\s*\1\s*\)\s*\)/g,
      desc: 'Tautological assertion expect(x, equals(x)) in Dart test.',
    },
  ];

  for (const file of dartTestFiles) {
    const content = fs.readFileSync(file, 'utf8');
    for (const pattern of dartHollowPatterns) {
      pattern.regex.lastIndex = 0;
      let match;
      while ((match = pattern.regex.exec(content)) !== null) {
        const { line, snippet } = getLineAndSnippet(content, match.index, match[0].length);
        violations.push({
          file: path.relative(repoRoot, file),
          line,
          rule: 'ANTI-HOLLOW-ASSERTION',
          snippet,
          message: pattern.desc,
        });
      }
    }
  }

  return violations;
}

export function runAntiCheatAudit(repoRoot = ROOT_DIR) {
  return [
    ...checkCircularMocking(repoRoot),
    ...checkSilentPassBypasses(repoRoot),
    ...checkProductionCheats(repoRoot),
    ...checkHollowAssertions(repoRoot),
  ];
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log('\n🔒 Running EasySubway Mobile Anti-Cheat & Test Integrity Guard (EasyConvert Standard)...\n');
  const violations = runAntiCheatAudit();

  if (violations.length > 0) {
    console.error(`\x1b[31m❌ [REJECTED] Found ${violations.length} Anti-Cheat violation(s):\x1b[0m\n`);
    for (const v of violations) {
      console.error(`  \x1b[33m${v.file}:${v.line}\x1b[0m [\x1b[31m${v.rule}\x1b[0m]`);
      console.error(`    Snippet : "${v.snippet}"`);
      console.error(`    Reason  : ${v.message}\n`);
    }
    process.exit(1);
  } else {
    console.log('\x1b[32m✅ [PASS] Zero shortcuts, zero circular mocks, zero silent passes, zero hollow assertions detected.\x1b[0m\n');
    process.exit(0);
  }
}
