"""Maintain one unpublished release and its changelog; never publish or push tags."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\Z")
HEADING = re.compile(r"^## (v\d+\.\d+\.\d+)[ \t]*$", re.MULTILINE)
NOTES_START = "<!-- buffeteria:auto-notes:start -->"
NOTES_END = "<!-- buffeteria:auto-notes:end -->"
DRAFT_START = "<!-- buffeteria:auto-release:start -->"
DRAFT_END = "<!-- buffeteria:auto-release:end -->"
COMMIT_PREFIX = "chore(release): prepare "


def run(*args, cwd=ROOT, input=None):
    result = subprocess.run(args, cwd=cwd, input=input, text=True, encoding="utf-8",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
            raise ValueError("Expected an owner/repository name")
        self.repository = repository

    def request(self, endpoint, method="GET", payload=None):
        args = ["gh", "api", "--method", method,
                f"repos/{self.repository}/{endpoint}"]
        if payload is not None:
            args += ["--input", "-"]
        return json.loads(run(*args, input=json.dumps(payload) if payload is not None else None))

    def releases(self):
        pages = json.loads(run("gh", "api", "--paginate", "--slurp",
                               f"repos/{self.repository}/releases?per_page=100"))
        return [release for page in pages for release in page]


def version(tag):
    match = VERSION.fullmatch(tag)
    return tuple(map(int, match.groups())) if match else None


def next_tag(base, bump):
    major, minor, patch = version(base)
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    elif bump == "patch":
        patch += 1
    else:
        raise ValueError(f"Unknown version bump: {bump}")
    return f"v{major}.{minor}.{patch}"


def release_plan(releases, bump, pending_tag=None):
    published = [r for r in releases if not r["draft"] and not r["prerelease"]
                 and version(r["tag_name"]) is not None]
    if not published:
        raise ValueError("Publish an initial stable vMAJOR.MINOR.PATCH release first")
    base = max(published, key=lambda r: version(r["tag_name"]))["tag_name"]
    managed = [r for r in releases if r["draft"] and DRAFT_START in (r["body"] or "")]
    if len(managed) > 1:
        raise ValueError("More than one automated draft exists; keep only one before rerunning")
    draft = managed[0] if managed else None
    if draft and (version(draft["tag_name"]) is None or
                  version(draft["tag_name"]) <= version(base)):
        raise ValueError("The automated draft is older than the latest stable release")
    if bump == "auto" and pending_tag and version(pending_tag) > version(base):
        # A previous run may have pushed the changelog before a GitHub API failure.
        tag = pending_tag
    else:
        tag = draft["tag_name"] if draft and bump == "auto" else next_tag(
            base, "patch" if bump == "auto" else bump)
    if any(r["tag_name"] == tag and (draft is None or r["id"] != draft["id"])
           for r in releases):
        raise ValueError(f"{tag} already has a release; resolve it before preparing this version")
    return base, tag, draft


def replace_block(text, start, end, content):
    block = f"{start}\n{content.strip()}\n{end}"
    if start not in text and end not in text:
        return text.rstrip() + ("\n\n" if text.strip() else "") + block
    if text.count(start) != 1 or text.count(end) != 1 or text.index(start) > text.index(end):
        raise ValueError("Malformed automatic notes markers; restore the matching start/end comments")
    first, rest = text.split(start)
    _, last = rest.split(end)
    return first + block + last


def changelog_section(text, tag):
    headings = list(HEADING.finditer(text))
    for index, heading in enumerate(headings):
        if heading.group(1) == tag:
            end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
            return text[heading.end():end].strip()
    return ""


def update_changelog(text, tag, notes, previous_tag=None):
    headings = list(HEADING.finditer(text))
    if len({h.group(1) for h in headings}) != len(headings):
        raise ValueError("Duplicate version headings in CHANGELOG.md")
    sections = {h.group(1): text[h.end():headings[i + 1].start() if i + 1 < len(headings)
                               else len(text)].strip() for i, h in enumerate(headings)}
    if previous_tag and previous_tag != tag:
        if tag in sections:
            raise ValueError(f"CHANGELOG.md already contains {tag}; resolve it before changing the draft version")
        sections[tag] = sections.pop(previous_tag, "")
    sections[tag] = replace_block(sections.get(tag, ""), NOTES_START, NOTES_END, notes)
    preamble = text[:headings[0].start()].rstrip() if headings else text.rstrip()
    # Pending release first; keep historical sections and their wording intact.
    ordered = [tag] + [h.group(1) for h in headings if h.group(1) not in (tag, previous_tag)]
    return preamble + "\n\n" + "\n\n".join(
        f"## {name}\n\n{sections[name]}" for name in ordered) + "\n"


def commit_notes(repo, base, repository):
    log = run("git", "log", "--reverse", "--format=%H%x00%s", f"{base}..HEAD", cwd=repo)
    notes = []
    for line in log.splitlines():
        sha, subject = line.split("\0", 1)
        if subject.startswith(COMMIT_PREFIX):
            continue
        subject = re.sub(r"([\\`*_{}\[\]<>])", r"\\\1", subject)
        notes.append(f"- {subject} ([{sha[:7]}](https://github.com/{repository}/commit/{sha}))")
    return "\n".join(notes)


def ensure_draft_available(api, tag, draft):
    # Never change an already-published release, or reuse somebody else's release.
    releases = api.releases()
    if draft:
        current = next((r for r in releases if r["id"] == draft["id"]), None)
        if not current or not current["draft"] or current.get("body") != draft.get("body"):
            raise ValueError("The draft was published, removed, or edited during preparation; rerun the workflow")
    if any(r["tag_name"] == tag and (draft is None or r["id"] != draft["id"])
           for r in releases):
        raise ValueError(f"{tag} was reserved during preparation; rerun the workflow")


def prepare(repo, api, bump="auto"):
    repo = Path(repo).resolve()
    if run("git", "status", "--porcelain", cwd=repo):
        raise ValueError("Release preparation requires a clean working tree")
    if run("git", "branch", "--show-current", cwd=repo) != "main":
        raise ValueError("Release preparation only runs on main")
    run("git", "fetch", "origin", "main", "--tags", cwd=repo)
    head = run("git", "rev-parse", "HEAD", cwd=repo)
    if head != run("git", "rev-parse", "origin/main", cwd=repo):
        raise ValueError("main changed during validation; rerun the workflow on its latest commit")
    path = repo / "CHANGELOG.md"
    original = path.read_text(encoding="utf-8")
    heading = HEADING.search(original)
    pending = heading.group(1) if heading and NOTES_START in changelog_section(
        original, heading.group(1)) else None
    base, tag, draft = release_plan(api.releases(), bump, pending)
    if pending and version(pending) <= version(base):
        pending = None
    run("git", "merge-base", "--is-ancestor", base, "HEAD", cwd=repo)
    if tag in run("git", "tag", "--list", cwd=repo).splitlines():
        raise ValueError(f"{tag} already exists as a Git tag; tags are never moved by this workflow")
    notes = commit_notes(repo, base, api.repository)
    if not notes:
        print(f"No new changes since {base}; no draft needed.")
        return None
    # Use the checked-in pending section during retries, even if the draft's tag
    # update failed after a minor/major override was committed.
    previous_tag = pending or (draft["tag_name"] if draft else None)
    changelog = update_changelog(original, tag, notes, previous_tag)
    section = changelog_section(changelog, tag).replace(NOTES_START + "\n", "").replace(
        "\n" + NOTES_END, "")
    compare = f"https://github.com/{api.repository}/compare/{base}...{tag}"
    body = replace_block((draft or {}).get("body") or "", DRAFT_START, DRAFT_END,
                         f"{section}\n\n[Full changelog]({compare})")
    ensure_draft_available(api, tag, draft)
    if changelog != original:
        path.write_text(changelog, encoding="utf-8", newline="\n")
        run("git", "add", "--", "CHANGELOG.md", cwd=repo)
        run("git", "commit", "-m", COMMIT_PREFIX + tag, cwd=repo)
        # A normal fast-forward push refuses concurrent changes; never force main.
        run("git", "push", "origin", "HEAD:refs/heads/main", cwd=repo)
    target = run("git", "rev-parse", "HEAD", cwd=repo)
    ensure_draft_available(api, tag, draft)
    payload = {"tag_name": tag, "target_commitish": target, "name": tag, "body": body}
    if draft:
        # Omit 'draft': never turn a release back into a draft in a publication race.
        result = api.request(f"releases/{draft['id']}", "PATCH", payload)
    else:
        result = api.request("releases", "POST", dict(payload, draft=True, prerelease=False))
    if not result["draft"]:
        raise ValueError("The release was published while preparation was running; check its target before uploading")
    print(f"Prepared {tag} at {target}: {result['html_url']} (unpublished)")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(f"Prepared [{tag}]({result['html_url']}) at `{target}`. "
                         "Test in-game, review the draft, then click **Publish release**.\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"), required=False)
    parser.add_argument("--bump", choices=("auto", "patch", "minor", "major"), default="auto",
                        help="auto keeps a pending draft's version, otherwise increments patch")
    args = parser.parse_args()
    if not args.repository:
        parser.error("--repository or GITHUB_REPOSITORY is required")
    prepare(ROOT, GitHub(args.repository), args.bump)


if __name__ == "__main__":
    main()
