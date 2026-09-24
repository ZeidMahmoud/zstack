/**
 * Host-neutral eval/harness model resolution (fork port wave 2, G cluster).
 *
 * Model IDs were hardcoded at six call sites across the eval helpers and the
 * distill bin, so an environment that pins a different model (CI cost
 * control, a model migration, an air-gapped proxy alias) had to patch source.
 * One resolution point, env-overridable:
 *
 *   ZSTACK_EVAL_MODEL_<KIND>  (e.g. ZSTACK_EVAL_MODEL_WARMUP) — per-kind
 *   ZSTACK_EVAL_MODEL                                        — global
 *   explicit argument                                        — caller wins
 *   per-kind default                                         — last resort
 *
 * Kinds and their defaults:
 *   capture — AskUserQuestion SDK capture runs: current frontier Claude model
 *   warmup  — PTY warm-up ping (cheapest thing that answers): haiku
 *   distill — free-text distillation (cheap, structured): haiku (pinned)
 *   judge   — LLM-judge rubric calls: current frontier Claude model
 */

export const CLAUDE_FRONTIER_EVAL_MODEL = "claude-fable-5-1";

// `as const satisfies` keeps EvalModelKind the literal union
// 'capture' | 'warmup' | 'distill' — a `Record<string, string>` annotation
// would widen it to string and let any typo through the type gate.
const DEFAULTS = {
  // Keep eval capture/judge on the current frontier Claude model by default.
  // Tests needing a cheaper or historical ruler pass it explicitly or set
  // ZSTACK_EVAL_MODEL_CAPTURE / ZSTACK_EVAL_MODEL_JUDGE / ZSTACK_EVAL_MODEL.
  capture: CLAUDE_FRONTIER_EVAL_MODEL,
  warmup: "claude-haiku-4-5",
  distill: "claude-haiku-4-5-20251001",
  judge: CLAUDE_FRONTIER_EVAL_MODEL,
} as const satisfies Record<string, string>;

export type EvalModelKind = keyof typeof DEFAULTS;

export function resolveEvalModel(
  kind: EvalModelKind,
  explicit?: string | null,
  env: NodeJS.ProcessEnv = process.env,
): string {
  if (explicit) return explicit;
  const perKind = env[`ZSTACK_EVAL_MODEL_${kind.toUpperCase()}`];
  if (perKind) return perKind;
  if (env.ZSTACK_EVAL_MODEL) return env.ZSTACK_EVAL_MODEL;
  const fallback = DEFAULTS[kind];
  if (!fallback) throw new Error(`resolveEvalModel: unknown kind "${kind}"`);
  return fallback;
}
