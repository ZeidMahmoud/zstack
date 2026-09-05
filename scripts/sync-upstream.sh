#!/usr/bin/env bash
# sync-upstream.sh — rebuild the zstack tree from an upstream gstack checkout.
#
# zstack is a mechanical rebrand of gstack (gstack→zstack in file names, paths
# and file contents, four case variants) plus a small overlay of hand edits
# (persona removal, LICENSE, README install URLs). Merging upstream with git is
# hopeless because the rebrand touches every file, so instead this script
# regenerates the whole tree from upstream and re-applies the overlay:
#
#   1. stage   — copy every git-tracked upstream file into a staging dir,
#                renaming paths and rewriting contents
#   2. replace — drop every tracked file in this repo except the preserved
#                set (ZSTACK.md, claude-extras/, scripts/sync-upstream.sh,
#                zstack-overlay/) and copy the staged tree in
#   3. overlay — `git apply --3way` each patch in zstack-overlay/*.patch;
#                hunks that no longer apply are reported, never silently lost
#   4. regen   — rebuild generated SKILL.md files from their .tmpl sources
#                (bun run gen:skill-docs) when bun is available
#   5. version — copy upstream VERSION into VERSION and package.json
#
# Usage:
#   scripts/sync-upstream.sh [--upstream DIR] [--stage-only DIR] [--no-regen]
#
#   --upstream DIR    upstream gstack checkout (default ~/.claude/skills/gstack)
#   --stage-only DIR  only run step 1 into DIR and exit (used by the self-test)
#   --no-regen        skip step 4
#
# Review `git status` / `git diff --stat` afterwards, run the tests, then
# commit. Nothing here commits or pushes.
set -euo pipefail

UPSTREAM="${HOME}/.claude/skills/gstack"
STAGE_ONLY=""
REGEN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --upstream)   UPSTREAM="$2"; shift 2 ;;
    --stage-only) STAGE_ONLY="$2"; shift 2 ;;
    --no-regen)   REGEN=0; shift ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PRESERVE_RE='^(ZSTACK\.md|claude-extras/|scripts/sync-upstream\.sh|zstack-overlay/)'

[ -d "$UPSTREAM/.git" ] || [ -f "$UPSTREAM/.git" ] || { echo "not a git checkout: $UPSTREAM" >&2; exit 1; }

# ─── rebrand helpers ─────────────────────────────────────────────
rebrand_path() {
  printf '%s' "$1" | sed 's/gstack/zstack/g; s/GSTACK/ZSTACK/g; s/GStack/ZStack/g; s/Gstack/Zstack/g'
}
rebrand_file() { # src dst
  if [ -s "$1" ] && grep -Iq . "$1"; then
    sed 's/gstack/zstack/g; s/GSTACK/ZSTACK/g; s/GStack/ZStack/g; s/Gstack/Zstack/g' "$1" > "$2"
    chmod --reference="$1" "$2"
  else
    cp -p "$1" "$2"
  fi
}

# ─── 1. stage ────────────────────────────────────────────────────
stage() { # dest
  local dest="$1" f out n=0
  mkdir -p "$dest"
  while IFS= read -r f; do
    [ -e "$UPSTREAM/$f" ] || continue
    out="$dest/$(rebrand_path "$f")"
    mkdir -p "$(dirname "$out")"
    if [ -L "$UPSTREAM/$f" ]; then
      ln -s "$(rebrand_path "$(readlink "$UPSTREAM/$f")")" "$out"
    else
      rebrand_file "$UPSTREAM/$f" "$out"
    fi
    n=$((n+1))
  done < <(git -C "$UPSTREAM" ls-files)
  echo "staged $n files from $UPSTREAM ($(cat "$UPSTREAM/VERSION" 2>/dev/null || echo '?'))"
}

if [ -n "$STAGE_ONLY" ]; then
  stage "$STAGE_ONLY"
  exit 0
fi

cd "$REPO"
if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; commit or stash first" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/zstack-stage-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
stage "$STAGE"

# ─── 2. replace ──────────────────────────────────────────────────
# (grep -v exits 1 when it filters everything out; that is not an error here)
git ls-files -z | { grep -zEv "$PRESERVE_RE" || true; } | xargs -0 -r git rm -q --cached --
git ls-files -z --others --exclude-standard | { grep -zEv "$PRESERVE_RE" || true; } | xargs -0 -r rm -f --
find . -mindepth 1 -type d -empty -not -path './.git*' -delete 2>/dev/null || true
cp -a "$STAGE"/. .
# -f: upstream's own .gitignore (bin/gstack-global-discover*) would otherwise
# hide the renamed bin/zstack-global-discover.ts, which setup needs.
git add -Af .
echo "replaced tree ($(git diff --cached --stat | tail -1))"

# ─── 3. overlay ──────────────────────────────────────────────────
FAILED=0
if [ -d zstack-overlay ]; then
  for p in zstack-overlay/*.patch; do
    [ -e "$p" ] || continue
    echo "overlay: $p"
    if git apply --3way --index "$p" 2>&1 | sed 's/^/  /'; then
      :
    else
      FAILED=1
      echo "  !! some hunks did not apply; conflict markers are in the tree" >&2
    fi
  done
fi

# ─── 4. regen ────────────────────────────────────────────────────
if [ "$REGEN" -eq 1 ] && command -v bun >/dev/null 2>&1; then
  echo "regenerating SKILL.md from templates"
  [ -d node_modules ] || bun install --frozen-lockfile >/dev/null 2>&1 || bun install >/dev/null 2>&1 || true
  bun run gen:skill-docs >/dev/null 2>&1 && git add -A . || echo "  gen:skill-docs failed; run it by hand" >&2
fi

# ─── 5. version ──────────────────────────────────────────────────
VER="$(cat "$UPSTREAM/VERSION")"
echo "$VER" > VERSION
sed -i "s/\"version\": \"[0-9.]*\"/\"version\": \"$VER\"/" package.json
git add VERSION package.json

echo
echo "synced to upstream $VER"
[ "$FAILED" -eq 0 ] || { echo "resolve conflicts (grep -rl '<<<<<<<' .), then commit" >&2; exit 3; }
echo "review with: git status; git diff --cached --stat | tail -1"
