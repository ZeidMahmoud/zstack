

export function generateLakeIntro(): string {
  return `If \`LAKE_INTRO\` is \`no\`: say "zstack follows the **Boil the Lake** principle — do the complete thing when AI makes marginal cost near-zero." Then run:

\`\`\`bash
touch ~/.zstack/.completeness-intro-seen
\`\`\`

Always run \`touch\`.`;
}
