#!/usr/bin/env python3
"""Split the just-closed quarter's entries out of CHANGELOG.md / DECISIONS.md
into CHANGELOG-YYYY-QN.md / DECISIONS-YYYY-QN.md, leaving the live files
holding only the current quarter onward.

Usage:
    scripts/archive_quarter.py            # dry run, prints what would move
    scripts/archive_quarter.py --apply    # writes the files

Cutoff defaults to the start of the current real-world quarter (today's
date). Pass --cutoff YYYY-MM-DD to override (mainly for testing).
"""
import argparse
import datetime
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

CHANGELOG_DATE_RE = re.compile(r"^## (\d{4}-\d{2}-\d{2})\s*$")
DECISION_DATE_RE = re.compile(r"^## (\d+) — .+\((\d{4}-\d{2}-\d{2})\)\s*$")


def quarter_of(d: datetime.date) -> int:
    return (d.month - 1) // 3 + 1


def quarter_start(year: int, q: int) -> datetime.date:
    return datetime.date(year, 3 * (q - 1) + 1, 1)


def split_entries(body_lines, date_re, date_group):
    """Split a list of lines (after the '---' banner) into entries, each
    starting at a '## ...' header line and running up to (not including)
    the next '## ' header. Returns list of (date, lines). Any stray content
    before the first header (e.g. a blank line after the banner) is dropped."""
    entries = []
    current_date = None
    current_lines = []
    started = False
    for line in body_lines:
        m = date_re.match(line)
        if m:
            if started:
                entries.append((current_date, current_lines))
            current_date = datetime.date.fromisoformat(m.group(date_group))
            current_lines = [line]
            started = True
        elif started:
            current_lines.append(line)
    if started:
        entries.append((current_date, current_lines))
    return entries


def archive_file(live_path: Path, date_re, date_group, title, archive_header_fn, cutoff, apply_):
    text = live_path.read_text()
    lines = text.splitlines(keepends=True)

    # Find the first '---' banner — everything before it is the live header
    # (title, "Current quarter only..." line, etc.); everything after is entries.
    try:
        banner_idx = next(i for i, l in enumerate(lines) if l.strip() == "---")
    except StopIteration:
        print(f"ERROR: no '---' banner found in {live_path.name}", file=sys.stderr)
        return None

    header_lines = lines[: banner_idx + 1]
    body_lines = lines[banner_idx + 1 :]

    entries = split_entries(body_lines, date_re, date_group)
    to_archive = [(d, l) for d, l in entries if d is not None and d < cutoff]
    to_keep = [(d, l) for d, l in entries if d is None or d >= cutoff]

    if not to_archive:
        print(f"{live_path.name}: nothing older than {cutoff} — nothing to archive")
        return None

    archived_dates = [d for d, _ in to_archive]
    q_year, q = archived_dates[-1].year, quarter_of(archived_dates[-1])
    # Entries are reverse-chronological; archived ones are the oldest (tail), confirm
    # all archived entries share one quarter (expected for a quarterly cadence).
    quarters_seen = {(d.year, quarter_of(d)) for d in archived_dates}
    if len(quarters_seen) > 1:
        print(
            f"WARNING: {live_path.name} archive batch spans multiple quarters "
            f"{sorted(quarters_seen)} — probably more than one quarter behind. "
            f"Archiving all of it into {q_year} Q{q}; review the result.",
            file=sys.stderr,
        )

    archive_name = f"{live_path.stem}-{q_year}-Q{q}.md"
    archive_path = live_path.parent / archive_name

    if archive_path.exists():
        print(
            f"ERROR: {archive_name} already exists — refusing to overwrite. "
            f"Merge manually.",
            file=sys.stderr,
        )
        return None

    archive_body = "".join(l for _, lines_ in to_archive for l in lines_)
    archive_content = archive_header_fn(live_path.name, q_year, q, archived_dates) + archive_body
    if not archive_content.endswith("\n"):
        archive_content += "\n"

    # Rebuild live file: original header, with the "Prior quarters" line
    # updated to include the newly archived quarter, then kept entries.
    new_header = []
    prior_q_pattern = re.compile(r"(Prior quarters?: )(.*)")
    added_link = False
    for l in header_lines:
        m = prior_q_pattern.search(l)
        if m and not added_link:
            existing = m.group(2).rstrip(".\n")
            link = f"[{q_year} Q{q}]({archive_name})"
            new_list = f"{existing}, {link}" if existing.strip() else link
            l = prior_q_pattern.sub(lambda mm: mm.group(1) + new_list + ".", l.rstrip("\n")) + "\n"
            added_link = True
        new_header.append(l)

    live_body = "".join(l for _, lines_ in to_keep for l in lines_)
    new_live_content = "".join(new_header) + "\n" + live_body

    print(f"{live_path.name}: archiving {len(to_archive)} entries ({q_year} Q{q}) -> {archive_name}")
    print(f"  keeping {len(to_keep)} entries in {live_path.name}")

    if apply_:
        archive_path.write_text(archive_content)
        live_path.write_text(new_live_content)

    return archive_path


def changelog_header(live_name, year, q, dates):
    lo, hi = min(dates), max(dates)
    return (
        f"# Changelog — {year} Q{q} (archived)\n\n"
        f"Archived from `{live_name}` at {year} Q{q + 1 if q < 4 else 1} close. "
        f"Entries {lo.isoformat()} through {hi.isoformat()}. "
        f"See [{live_name}]({live_name}) for current entries.\n\n"
        f"Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).\n\n"
        f"---\n\n"
    )


def decision_header(live_name, year, q, dates):
    lo, hi = min(dates), max(dates)
    return (
        f"# Decision Log — {year} Q{q} (archived)\n\n"
        f"Archived from `{live_name}` at {year} Q{q + 1 if q < 4 else 1} close. "
        f"Entries {lo.isoformat()} – {hi.isoformat()}. "
        f"See [{live_name}]({live_name}) for current-quarter entries.\n\n"
        f"---\n\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write files (default: dry run)")
    parser.add_argument("--cutoff", type=str, help="override cutoff date YYYY-MM-DD (default: start of current quarter)")
    args = parser.parse_args()

    if args.cutoff:
        cutoff = datetime.date.fromisoformat(args.cutoff)
    else:
        today = datetime.date.today()
        cutoff = quarter_start(today.year, quarter_of(today))

    print(f"Cutoff: entries before {cutoff.isoformat()} will be archived\n")

    archive_file(
        REPO_ROOT / "CHANGELOG.md",
        CHANGELOG_DATE_RE,
        1,
        "Changelog",
        changelog_header,
        cutoff,
        args.apply,
    )
    print()
    archive_file(
        REPO_ROOT / "DECISIONS.md",
        DECISION_DATE_RE,
        2,
        "Decision Log",
        decision_header,
        cutoff,
        args.apply,
    )

    if not args.apply:
        print("\nDry run only — re-run with --apply to write files.")


if __name__ == "__main__":
    main()
