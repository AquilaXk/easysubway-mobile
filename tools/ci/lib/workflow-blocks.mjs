import assert from "node:assert/strict";

const JOB_INDENT = 2;
const STEP_INDENT = 6;
const RUN_BODY_INDENT = 10;

// 2칸 들여쓰기 job 키부터 다음 job 키나 다음 job 앞 주석(2칸 들여쓰기)까지가 한 job이다. job 내부는 4칸 이상이다.
export function jobBlock(workflow, id) {
  const lines = workflow.split("\n");
  const jobsStart = lines.indexOf("jobs:");
  assert.notEqual(jobsStart, -1, "jobs: section is missing");
  const start = lines.indexOf(`${" ".repeat(JOB_INDENT)}${id}:`, jobsStart);
  assert.notEqual(start, -1, `job ${id} is missing`);
  const nextJob = new RegExp(`^ {${JOB_INDENT}}\\S`, "u");
  const end = lines.findIndex((line, index) => index > start && nextJob.test(line));
  return lines.slice(start, end === -1 ? undefined : end).join("\n");
}

export function stepBlock(job, name) {
  const header = `${" ".repeat(STEP_INDENT)}- name: ${name}`;
  const start = job.indexOf(`${header}\n`);
  assert.notEqual(start, -1, `step ${name} is missing`);
  const next = job.indexOf(`\n${" ".repeat(STEP_INDENT)}- name: `, start + header.length);
  return job.slice(start, next === -1 ? undefined : next);
}

export function runScript(step) {
  const lines = step.split("\n");
  const start = lines.indexOf(`${" ".repeat(STEP_INDENT + 2)}run: |`);
  assert.notEqual(start, -1, "run: | block is missing");
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && !line.startsWith(" ".repeat(RUN_BODY_INDENT))) break;
    body.push(line.slice(RUN_BODY_INDENT));
  }
  return `${body.join("\n").trimEnd()}\n`;
}
