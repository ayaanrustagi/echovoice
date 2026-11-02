#!/usr/bin/env python3
"""Regenerate CAC_CODE_ATTRIBUTION.md: credit every current line of Swift to
the commit that last changed it (git blame), grouped for the CAC AI disclosure.

Run from anywhere inside the repository:  python3 EchoVoice-iOS/Scripts/code_attribution.py
"""
import collections
import subprocess
from datetime import date
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
OUT = ROOT / "CAC_CODE_ATTRIBUTION.md"

# Commits that predate the first recorded AI use (Aug 14, 2026).
BASELINE = {"f2ccada", "704260c"}
# Bundles Claude (Sep 5), Codex (Aug 14, Sep 19-26), and student edits.
MIXED = {"86760ea"}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True)


def claude_commits():
    log = git("log", "--format=%h%x00%b%x01")
    return {
        entry.split("\0", 1)[0].strip()
        for entry in log.split("\x01")
        if "Co-Authored-By: Claude" in entry
    }


def blame_counts(path, short):
    counts = collections.Counter()
    for line in git("blame", "--line-porcelain", "--", path).splitlines():
        head = line.split(" ", 1)[0]
        if len(head) == 40 and all(c in "0123456789abcdef" for c in head):
            current = head[:short]
        elif line.startswith("\t"):
            counts[current] += 1
    return counts


def main():
    claude = claude_commits()
    short = len(next(iter(claude))) if claude else 7
    files = git("ls-files", "EchoVoice-iOS/EchoVoice/*.swift", "EchoVoice-iOS/Tests/*.swift").split()

    rows = []
    totals = collections.Counter()
    for path in files:
        counts = blame_counts(path, short)
        row = collections.Counter()
        for commit, n in counts.items():
            if commit in BASELINE:
                row["baseline"] += n
            elif commit in MIXED:
                row["mixed"] += n
            elif commit in claude:
                row["claude"] += n
            else:
                row["other"] += n
        row["total"] = sum(counts.values())
        totals.update(row)
        rows.append((path.replace("EchoVoice-iOS/", ""), row))

    def pct(part, whole):
        return f"{round(100 * part / whole)}%" if whole else "0%"

    rows.sort(key=lambda r: (-r[1]["baseline"] / max(r[1]["total"], 1), r[0]))
    table = "\n".join(
        f"| `{name}` | {r['total']} | {pct(r['baseline'], r['total'])} | {pct(r['mixed'], r['total'])} "
        f"| {pct(r['claude'], r['total'])} | {pct(r['other'], r['total'])} |"
        for name, r in rows
    )
    t = totals
    OUT.write_text(f"""# EchoVoice — Code Attribution (for the CAC AI disclosure)

Generated {date.today():%B %-d, %Y} by `EchoVoice-iOS/Scripts/code_attribution.py`
(`git blame` on the current branch). Each current line of Swift is credited to
the commit that last changed it.

- **Baseline (Jul 28)** — commits `f2ccada`, `704260c`: the app as first tracked,
  before the first AI use recorded in `CAC_AI_DISCLOSURE.md` (Aug 14).
- **Sep 26 (mixed)** — commit `86760ea`: bundles Claude's Sep 5 work, Codex's
  Aug 14 and Sep 19–26 work, and any of the student's own edits from that
  period. Git cannot separate these; the student should mark which parts are
  theirs.
- **Claude** — commits with a `Co-Authored-By: Claude` trailer.
- **Other** — any other commit (for example, the student's own commits from
  here on).

A line last edited by a later commit is credited to that commit even if it
was originally written earlier, so "Baseline" is a lower bound on original
student code.

**Totals: {t['total']} lines — baseline {pct(t['baseline'], t['total'])}, Sep 26 mixed
{pct(t['mixed'], t['total'])}, Claude {pct(t['claude'], t['total'])}, other {pct(t['other'], t['total'])}.**

| File | Lines | Baseline | Sep 26 mixed | Claude | Other |
|---|---:|---:|---:|---:|---:|
{table}
""")
    print(f"{OUT.name}: {t['total']} lines, baseline {pct(t['baseline'], t['total'])}, "
          f"mixed {pct(t['mixed'], t['total'])}, claude {pct(t['claude'], t['total'])}, other {pct(t['other'], t['total'])}")


if __name__ == "__main__":
    main()
