// End-to-end check of the text-to-period pipeline on the host:
//   node tests/ai/run_eval.mjs <range_eval binary> <model.gguf>
// Request gate and validation run in TextRange.ts; the model runs in the same C++ code as the app.
import '../ts_resolve.mjs';
import { spawnSync } from 'node:child_process';
import { NOW, REJECT, VALID } from './cases.mjs';

const { analyzeRequest, interpretOutput } = await import('../../entry/src/main/ets/model/TextRange.ts');
const [binary, model] = process.argv.slice(2);
if (!binary || !model) {
  console.error('usage: node tests/ai/run_eval.mjs <range_eval> <model.gguf>');
  process.exit(2);
}

const now = new Date(NOW).getTime();
const day = (time) => {
  const date = new Date(time);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
};

const requests = [...VALID.map((item) => item[0]), ...REJECT];
const analyses = requests.map((text) => analyzeRequest(text, now));
const forModel = analyses.map((analysis, index) => ({ analysis, index })).filter((item) => item.analysis.ok);
const input = forModel.map((item) => `${item.analysis.text}\n${item.analysis.grammar}\n%%\n`).join('');
const started = Date.now();
const run = spawnSync(binary, [model], { input, encoding: 'utf8', maxBuffer: 1 << 20 });
if (run.status !== 0) {
  console.error(run.stderr);
  process.exit(1);
}
const outputs = run.stdout.trim().split('\n');
const modelOutput = new Map(forModel.map((item, position) => [item.index, outputs[position]]));

let validPassed = 0;
let rejectPassed = 0;
requests.forEach((text, index) => {
  const output = modelOutput.get(index) ?? '(not sent to model)';
  const proposal = interpretOutput(modelOutput.get(index) ?? '', analyses[index], now);
  const result = proposal.ok ? `${day(proposal.range.start)}..${day(proposal.range.end)} ${proposal.kinds.join(',')}` :
    `reject:${proposal.reason}`;
  let pass;
  if (index < VALID.length) {
    pass = result === `${VALID[index][1]}..${VALID[index][2]} ${VALID[index][3] ?? 'photo'}`;
    validPassed += pass ? 1 : 0;
  } else {
    pass = !proposal.ok;
    rejectPassed += pass ? 1 : 0;
  }
  const label = text.length > 60 ? `${text.slice(0, 57)}...` : text;
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${label.padEnd(60)} ${result.padEnd(42)} ${output}`);
});
console.log(`\nvalid requests: ${validPassed}/${VALID.length} correct`);
console.log(`rejections:     ${rejectPassed}/${REJECT.length} rejected`);
console.log(`model calls:    ${forModel.length} in ${Date.now() - started} ms`);
process.exit(rejectPassed === REJECT.length ? 0 : 1);
