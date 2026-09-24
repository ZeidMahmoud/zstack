#!/usr/bin/env python3
"""zstack-rebrand.py — stage a rebranded copy of an upstream gstack checkout.

Copies every git-tracked upstream file into STAGE_DIR, rewriting file names,
symlink targets and text contents with the zstack rebrand rules, drops the
upstream files zstack does not ship, and repins the sha256 digests that the
rewrite invalidated in test fixtures.

Usage: zstack-rebrand.py UPSTREAM_DIR STAGE_DIR

Rebrand rules (applied in order; see REWRITES):
  gstack/GSTACK/GStack/Gstack -> zstack/ZSTACK/ZStack/Zstack
  garrytan (GitHub owner)     -> zeidmahmoud   (lowercase: container image
                                 names must be lowercase, and GitHub owner
                                 names are case-insensitive)
  Garry Tan / Garry / garry   -> Zeid Mahmoud / Zeid / zeid
Kept verbatim:
  - EXTERNAL repos zstack downloads from their real owner (gbrain, ...):
    rewriting those URLs would point at repositories that do not exist.
  - VERBATIM files (LICENSE: MIT requires the original copyright notice).
"""
import hashlib, json, os, re, shutil, subprocess, sys

REWRITES = [
    ("gstack", "zstack"), ("GSTACK", "ZSTACK"), ("GStack", "ZStack"), ("Gstack", "Zstack"),
    ("garrytan", "zeidmahmoud"), ("GarryTan", "ZeidMahmoud"),
    ("Garry Tan", "Zeid Mahmoud"), ("GARRY", "ZEID"), ("Garry", "Zeid"), ("garry", "zeid"),
]
# Other projects by the upstream author that zstack installs or links to.
EXTERNAL = ["garrytan/gbrain", "garrytan/browserharness", "garrytan/prompt-injection-guard"]
VERBATIM = {"LICENSE"}
# Upstream files that only make sense for the upstream author (personal
# productivity claims and their screenshots). Rebranding them would put
# made-up claims in zstack's mouth, so they are not shipped.
DROP = {
    "docs/ON_THE_LOC_CONTROVERSY.md",
    "docs/images/github-2013.png",
    "docs/images/github-2026.png",
}


def rebrand(s):
    keep = {}
    for i, ext in enumerate(EXTERNAL):
        token = f"\0EXT{i}\0"
        keep[token] = ext
        s = s.replace(ext, token)
    for a, b in REWRITES:
        s = s.replace(a, b)
    for token, ext in keep.items():
        s = s.replace(token, ext)
    return s


def sha(b):
    return hashlib.sha256(b).hexdigest()


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield k
            yield from strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)


def read_text(path):
    raw = open(path, "rb").read()
    if b"\0" in raw[:8192]:
        return raw, None
    try:
        return raw, raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw, None


def stage(upstream, dest):
    files = subprocess.run(["git", "-C", upstream, "ls-files", "-z"], check=True,
                           capture_output=True).stdout.decode().split("\0")
    digests = {}  # upstream sha256 -> rebranded sha256, for test fixtures
    n = 0
    for f in filter(None, files):
        src = os.path.join(upstream, f)
        if f in DROP or not os.path.lexists(src):
            continue
        out = os.path.join(dest, rebrand(f))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        n += 1
        if os.path.islink(src):
            os.symlink(rebrand(os.readlink(src)), out)
            continue
        raw, text = read_text(src)
        if text is None or f in VERBATIM:
            shutil.copy2(src, out)
            continue
        new = rebrand(text)
        with open(out, "w", encoding="utf-8", newline="") as fh:
            fh.write(new)
        shutil.copymode(src, out)
        if new != text and f.startswith("test/"):
            digests[sha(raw)] = sha(new.encode("utf-8"))
            if f.endswith(".json"):
                try:
                    doc = json.loads(text)
                except ValueError:
                    doc = None
                for s in strings(doc):
                    r = rebrand(s)
                    if r != s:
                        digests[sha(s.encode("utf-8"))] = sha(r.encode("utf-8"))
    return n, digests


def repin(dest, digests):
    """Tests pin sha256 digests of fixture content (whole files, or string
    fields such as `screen` / `screenSha256`). Point them at the rebranded bytes."""
    pat = re.compile(r"\b[0-9a-f]{64}\b")
    changed = 0
    for root, _, names in os.walk(os.path.join(dest, "test")):
        for name in names:
            p = os.path.join(root, name)
            if os.path.islink(p):
                continue
            _, text = read_text(p)
            if text is None:
                continue
            new = pat.sub(lambda m: digests.get(m.group(0), m.group(0)), text)
            if new != text:
                with open(p, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new)
                changed += 1
    return changed


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    upstream, dest = sys.argv[1], sys.argv[2]
    n, digests = stage(upstream, dest)
    changed = repin(dest, digests)
    version = open(os.path.join(upstream, "VERSION")).read().strip() if os.path.exists(os.path.join(upstream, "VERSION")) else "?"
    print(f"staged {n} files from {upstream} ({version}); repinned {changed} test files")


if __name__ == "__main__":
    main()
