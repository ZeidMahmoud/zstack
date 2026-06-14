

export function generateLakeIntro(): string {
  return `If \`LAKE_INTRO\` is \`no\`: say "zstack follows the **Boil the Lake** principle — do the complete thing when AI makes marginal cost near-zero. Read more: https://garryslist.org/posts/boil-the-ocean" Offer to open:

\`\`\`bash
open https://garryslist.org/posts/boil-the-ocean
touch ~/.zstack/.completeness-intro-seen
\`\`\`

Only run \`open\` if yes. Always run \`touch\`.`;
}
