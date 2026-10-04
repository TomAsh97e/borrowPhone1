import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import native from 'libentry.so';
import { analyzeRequest, interpretOutput, RangeProposal, rejectMessage } from '../model/TextRange';

// Bundled as a raw file (tools/fetch_model.sh --bundle) and copied once into the app sandbox,
// because llama.cpp loads models from a file path. HAPs built without it use a model pushed into
// the sandbox (tools/push_model.sh), e.g. on the emulator whose data partition is too small.
const MODEL_RAWFILE = 'models/range-parser.gguf';
const MODEL_FILE = 'range-parser.gguf';

export class AssistantResult {
  proposal: RangeProposal | null;
  message: string;

  constructor(proposal: RangeProposal | null, message: string) {
    this.proposal = proposal;
    this.message = message;
  }
}

let installing: Promise<string> | null = null;

async function installModel(context: common.UIAbilityContext): Promise<string> {
  const destination = `${context.filesDir}/${MODEL_FILE}`;
  let raw: resourceManager.RawFileDescriptor;
  try {
    raw = await context.resourceManager.getRawFd(MODEL_RAWFILE);
  } catch (error) {
    if (fileIo.accessSync(destination)) {
      return destination;
    }
    throw new Error('model not installed');
  }
  try {
    if (fileIo.accessSync(destination) && fileIo.statSync(destination).size === raw.length) {
      return destination;
    }
    await native.installModel(raw.fd, raw.offset, raw.length, destination);
    return destination;
  } finally {
    await context.resourceManager.closeRawFd(MODEL_RAWFILE);
  }
}

function modelPath(context: common.UIAbilityContext): Promise<string> {
  if (installing === null) {
    installing = installModel(context);
    installing.catch(() => {
      installing = null;
    });
  }
  return installing;
}

// Request gate → on-device model (grammar limited to grounded values) → validation. The returned
// proposal changes nothing by itself; the owner has to approve it.
export async function proposeRange(context: common.UIAbilityContext, text: string, now: number):
  Promise<AssistantResult> {
  const analysis = analyzeRequest(text, now);
  if (!analysis.ok) {
    return new AssistantResult(null, rejectMessage(analysis.reason ?? 'invalid_output', analysis.word));
  }
  let output = '';
  try {
    output = await native.parseRange(await modelPath(context), analysis.text, analysis.grammar);
  } catch (error) {
    hilog.warn(0x0000, 'SafeShare', 'range assistant unavailable: %{public}s', `${error}`);
    return new AssistantResult(null, rejectMessage('unavailable', ''));
  }
  const proposal = interpretOutput(output, analysis, now);
  return proposal.ok ? new AssistantResult(proposal, '') :
    new AssistantResult(null, rejectMessage(proposal.reason ?? 'invalid_output', ''));
}

export function releaseAssistant(): void {
  native.releaseModel();
}
