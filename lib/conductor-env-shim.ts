/**
 * Conductor workspaces don't inherit the user's interactive shell env, so the
 * canonical ANTHROPIC_API_KEY / OPENAI_API_KEY may be missing while
 * Conductor's ZSTACK_-prefixed forms are present. Promote the ZSTACK_ form to
 * canonical when canonical is empty, so subprocesses (gbrain embed,
 * @anthropic-ai/claude-agent-sdk, etc) pick it up.
 *
 * Import this for its side effect: `import "../lib/conductor-env-shim";`
 */
export function promoteConductorEnv(): void {
  for (const key of ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"] as const) {
    if (!process.env[key] && process.env[`ZSTACK_${key}`]) {
      process.env[key] = process.env[`ZSTACK_${key}`];
    }
  }
}

promoteConductorEnv();
