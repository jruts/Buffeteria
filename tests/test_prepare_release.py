"""Release automation checks; local Git repositories and an in-memory GitHub API."""
import contextlib
import copy
import io
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from prepare_release import (COMMIT_PREFIX, DRAFT_END, DRAFT_START, NOTES_END, NOTES_START,
                             changelog_section, next_tag, prepare, release_plan, run,
                             update_changelog)


def release(tag="v0.6.13", draft=False, body="", id=1, prerelease=False):
    return dict(id=id, tag_name=tag, draft=draft, prerelease=prerelease, body=body,
                html_url=f"https://github.com/example/addon/releases/{id}")


def managed(tag="v0.6.14"):
    return release(tag, True, f"{DRAFT_START}\nOld notes\n{DRAFT_END}", id=2)


class FakeGitHub:
    repository = "example/addon"

    def __init__(self):
        self.items = [release()]
        self.calls = []
        self.fail_write = False

    def releases(self):
        return copy.deepcopy(self.items)

    def request(self, endpoint, method="GET", payload=None):
        self.calls.append((endpoint, method, copy.deepcopy(payload)))
        if self.fail_write:
            raise RuntimeError("Simulated GitHub outage")
        if method == "POST":
            item = release(id=max(r["id"] for r in self.items) + 1)
            item.update(payload)
            self.items.append(item)
        elif method == "PATCH":
            item = next(r for r in self.items if endpoint == f"releases/{r['id']}")
            item.update(payload)
        else:
            raise AssertionError(f"Unexpected API request: {endpoint} {method}")
        return copy.deepcopy(item)


class VersionTests(unittest.TestCase):
    def test_patch_minor_major_rollovers(self):
        self.assertEqual(next_tag("v0.6.13", "patch"), "v0.6.14")
        self.assertEqual(next_tag("v0.6.13", "minor"), "v0.7.0")
        self.assertEqual(next_tag("v0.6.13", "major"), "v1.0.0")

    def test_numerical_order_ignores_prereleases_and_unpublished_versions(self):
        releases = [release("v0.6.9"), release("v0.6.13"),
                    release("v1.0.0-beta.1", prerelease=True),
                    release("v2.0.0", prerelease=True), release("v8.0.0", draft=True)]
        self.assertEqual(release_plan(releases, "auto")[:2], ("v0.6.13", "v0.6.14"))

    def test_auto_keeps_minor_draft_and_explicit_patch_replaces_it(self):
        releases = [release(), managed("v0.7.0")]
        self.assertEqual(release_plan(releases, "auto")[1], "v0.7.0")
        self.assertEqual(release_plan(releases, "patch")[1], "v0.6.14")

    def test_initial_release_is_required(self):
        with self.assertRaisesRegex(ValueError, "initial stable"):
            release_plan([], "auto")

    def test_unrelated_draft_is_not_adopted(self):
        with self.assertRaisesRegex(ValueError, "already has a release"):
            release_plan([release(), release("v0.6.14", draft=True, id=3)], "auto")

    def test_multiple_managed_drafts_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "More than one"):
            release_plan([release(), managed(), managed("v0.7.0")], "auto")

    def test_stale_managed_draft_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "older than"):
            release_plan([release(), managed("v0.6.12")], "auto")


class ChangelogTests(unittest.TestCase):
    original = "# Buffeteria\n\n## v0.6.13\n\n- Historical notes.\n"

    def test_add_update_and_idempotence_preserve_history(self):
        first = update_changelog(self.original, "v0.6.14", "- A new fix.")
        second = update_changelog(first, "v0.6.14", "- A newer fix.")
        self.assertEqual(update_changelog(second, "v0.6.14", "- A newer fix."), second)
        self.assertEqual(changelog_section(second, "v0.6.13"), "- Historical notes.")
        self.assertNotIn("A new fix.", second)
        self.assertEqual(second.count("## v0.6.14"), 1)

    def test_manual_notes_survive_updates_and_version_override(self):
        first = update_changelog(self.original, "v0.6.14", "- A fix.")
        first = first.replace(NOTES_START, "- Handwritten summary.\n\n" + NOTES_START)
        updated = update_changelog(first, "v0.7.0", "- More fixes.", "v0.6.14")
        self.assertNotIn("## v0.6.14", updated)
        self.assertIn("Handwritten summary.", changelog_section(updated, "v0.7.0"))
        self.assertEqual(changelog_section(updated, "v0.6.13"), "- Historical notes.")

    def test_existing_handwritten_pending_section_is_preserved(self):
        original = self.original.replace("## v0.6.13", "## v0.6.14\n\n- Authored notes.\n\n## v0.6.13")
        updated = update_changelog(original, "v0.6.14", "- Commit notes.")
        self.assertIn("- Authored notes.", changelog_section(updated, "v0.6.14"))

    def test_incomplete_markers_are_rejected(self):
        for text in (NOTES_START, NOTES_END, NOTES_END + NOTES_START):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "Malformed"):
                update_changelog(f"# Buffeteria\n\n## v0.6.14\n\n{text}", "v0.6.14", "notes")

    def test_conflicting_override_section_is_rejected(self):
        text = update_changelog(self.original, "v0.6.14", "notes")
        text = update_changelog(text, "v0.7.0", "other notes")
        with self.assertRaisesRegex(ValueError, "already contains"):
            update_changelog(text, "v0.7.0", "notes", "v0.6.14")

    def test_duplicate_sections_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            update_changelog(self.original + "\n## v0.6.13\n\nDuplicate\n", "v0.6.14", "notes")


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.remote = Path(self.temp.name) / "remote.git"
        self.repo.mkdir()
        run("git", "init", "--initial-branch=main", cwd=self.repo)
        run("git", "config", "user.name", "Release test", cwd=self.repo)
        run("git", "config", "user.email", "release@example.test", cwd=self.repo)
        (self.repo / "CHANGELOG.md").write_text(ChangelogTests.original, encoding="utf-8")
        (self.repo / "addon.lua").write_text("-- initial\n", encoding="utf-8")
        self.commit("Initial release")
        run("git", "tag", "v0.6.13", cwd=self.repo)
        run("git", "init", "--bare", str(self.remote), cwd=self.repo)
        run("git", "remote", "add", "origin", str(self.remote), cwd=self.repo)
        run("git", "push", "origin", "main", "--tags", cwd=self.repo)
        self.api = FakeGitHub()

    def commit(self, subject):
        run("git", "add", ".", cwd=self.repo)
        run("git", "commit", "-m", subject, cwd=self.repo)

    def change(self, subject="Fix buff tracking"):
        with (self.repo / "addon.lua").open("a", encoding="utf-8") as output:
            output.write("-- a change\n")
        self.commit(subject)
        run("git", "push", "origin", "main", cwd=self.repo)

    def prepare(self, bump="auto"):
        with contextlib.redirect_stdout(io.StringIO()):
            return prepare(self.repo, self.api, bump)

    def test_creates_unpublished_draft_with_committed_changelog_and_no_tag(self):
        self.change()
        result = self.prepare()
        self.assertTrue(result["draft"])
        self.assertFalse(result["prerelease"])
        self.assertEqual(result["tag_name"], "v0.6.14")
        self.assertIn("Fix buff tracking", result["body"])
        self.assertNotIn(NOTES_START, result["body"])
        target = result["target_commitish"]
        self.assertEqual(target, run("git", "rev-parse", "HEAD", cwd=self.repo))
        self.assertEqual(target, run("git", "rev-parse", "origin/main", cwd=self.repo))
        self.assertIn("## v0.6.14", run("git", "show", f"{target}:CHANGELOG.md", cwd=self.repo))
        self.assertNotIn("v0.6.14", run("git", "ls-remote", "--tags", "origin", cwd=self.repo))
        self.assertEqual(run("git", "status", "--porcelain", cwd=self.repo), "")

    def test_repeated_runs_update_same_draft_without_extra_commits(self):
        self.change()
        first = self.prepare()
        self.assertEqual(first["target_commitish"], self.prepare()["target_commitish"])
        self.change("Fix another issue")
        updated = self.prepare()
        self.assertEqual(updated["id"], first["id"])
        self.assertEqual(updated["tag_name"], first["tag_name"])
        self.assertIn("Fix another issue", updated["body"])
        self.assertNotIn(COMMIT_PREFIX, updated["body"])
        self.assertEqual(len(self.api.items), 2)

    def test_minor_override_persists_on_later_push_and_keeps_user_notes(self):
        self.change()
        self.prepare()
        self.api.items[-1]["body"] = "Manual release introduction.\n\n" + self.api.items[-1]["body"]
        text = (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        (self.repo / "CHANGELOG.md").write_text(text.replace(
            NOTES_START, "Manual changelog summary.\n\n" + NOTES_START), encoding="utf-8")
        self.commit("Clarify release notes")
        run("git", "push", "origin", "main", cwd=self.repo)
        self.assertEqual(self.prepare("minor")["tag_name"], "v0.7.0")
        self.change("Another improvement")
        result = self.prepare()
        self.assertEqual(result["tag_name"], "v0.7.0")
        self.assertTrue(result["body"].startswith("Manual release introduction."))
        self.assertIn("Manual changelog summary.", result["body"])
        text = (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertNotIn("## v0.6.14", text)
        self.assertEqual(text.count("## v0.7.0"), 1)

    def test_publishing_advances_next_draft_only_after_new_changes(self):
        self.change()
        first = self.prepare()
        run("git", "tag", "v0.6.14", first["target_commitish"], cwd=self.repo)
        run("git", "push", "origin", "v0.6.14", cwd=self.repo)
        self.api.items[-1]["draft"] = False
        self.assertIsNone(self.prepare())
        self.change("New patch")
        result = self.prepare()
        self.assertEqual(result["tag_name"], "v0.6.15")
        self.assertIn("New patch", result["body"])
        self.assertNotIn("Fix buff tracking", result["body"])
        text = (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("Fix buff tracking", changelog_section(text, "v0.6.14"))
        self.assertEqual(changelog_section(text, "v0.6.13"), "- Historical notes.")

    def test_no_changes_does_not_create_a_draft_or_commit(self):
        before = run("git", "rev-parse", "HEAD", cwd=self.repo)
        self.assertIsNone(self.prepare())
        self.assertEqual(run("git", "rev-parse", "HEAD", cwd=self.repo), before)
        self.assertEqual(self.api.calls, [])

    def test_existing_tag_is_never_moved(self):
        self.change()
        run("git", "tag", "v0.6.14", cwd=self.repo)
        run("git", "push", "origin", "v0.6.14", cwd=self.repo)
        with self.assertRaisesRegex(ValueError, "already exists as a Git tag"):
            self.prepare()
        self.assertEqual(self.api.calls, [])

    def test_dirty_tree_and_wrong_branch_are_rejected(self):
        (self.repo / "addon.lua").write_text("-- dirty\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "clean working tree"):
            self.prepare()
        self.commit("Save change")
        run("git", "checkout", "-b", "feature", cwd=self.repo)
        with self.assertRaisesRegex(ValueError, "only runs on main"):
            self.prepare()

    def test_unpushed_or_stale_checkout_is_rejected(self):
        (self.repo / "addon.lua").write_text("-- unpushed\n", encoding="utf-8")
        self.commit("Unpushed change")
        with self.assertRaisesRegex(ValueError, "changed during validation"):
            self.prepare()

    def test_api_outage_can_be_retried_after_changelog_commit(self):
        self.change()
        self.api.fail_write = True
        with self.assertRaisesRegex(RuntimeError, "Simulated GitHub outage"):
            self.prepare()
        target = run("git", "rev-parse", "HEAD", cwd=self.repo)
        self.api.fail_write = False
        self.assertEqual(self.prepare()["target_commitish"], target)

    def test_api_outage_after_initial_minor_override_keeps_version_on_auto_retry(self):
        self.change()
        self.api.fail_write = True
        with self.assertRaisesRegex(RuntimeError, "Simulated GitHub outage"):
            self.prepare("minor")
        target = run("git", "rev-parse", "HEAD", cwd=self.repo)
        self.api.fail_write = False
        result = self.prepare()
        self.assertEqual(result["tag_name"], "v0.7.0")
        self.assertEqual(result["target_commitish"], target)

    def test_api_outage_during_retag_keeps_version_and_notes_on_auto_retry(self):
        self.change()
        self.prepare()
        self.api.fail_write = True
        with self.assertRaisesRegex(RuntimeError, "Simulated GitHub outage"):
            self.prepare("major")
        target = run("git", "rev-parse", "HEAD", cwd=self.repo)
        self.api.fail_write = False
        result = self.prepare()
        self.assertEqual(result["tag_name"], "v1.0.0")
        self.assertEqual(result["target_commitish"], target)
        text = (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertNotIn("## v0.6.14", text)
        self.assertEqual(text.count("## v1.0.0"), 1)

    def test_concurrent_main_push_is_not_overwritten(self):
        self.change()
        before = run("git", "rev-parse", "HEAD", cwd=self.repo)
        clone = Path(self.temp.name) / "other"
        run("git", "clone", "--branch", "main", str(self.remote), str(clone), cwd=self.repo)
        run("git", "config", "user.name", "Another author", cwd=clone)
        run("git", "config", "user.email", "other@example.test", cwd=clone)
        (clone / "other.lua").write_text("-- concurrent change\n", encoding="utf-8")
        run("git", "add", ".", cwd=clone)
        run("git", "commit", "-m", "Concurrent change", cwd=clone)
        other_head = run("git", "rev-parse", "HEAD", cwd=clone)
        original = self.api.releases
        calls = 0

        def push_during_preparation():
            nonlocal calls
            calls += 1
            if calls == 2:
                run("git", "push", "origin", "main", cwd=clone)
            return original()

        self.api.releases = push_during_preparation
        with self.assertRaisesRegex(RuntimeError, "git failed"):
            self.prepare()
        self.assertNotEqual(before, other_head)
        self.assertIn(other_head, run("git", "ls-remote", "origin", "refs/heads/main", cwd=self.repo))
        self.assertEqual(self.api.calls, [])

    def test_draft_published_during_run_is_not_modified(self):
        self.change()
        self.prepare()
        self.change("Another fix")
        original = self.api.releases
        calls = 0

        def publish_during_preparation():
            nonlocal calls
            calls += 1
            if calls == 2:
                self.api.items[-1]["draft"] = False
            return original()

        self.api.releases = publish_during_preparation
        before = len(self.api.calls)
        with self.assertRaisesRegex(ValueError, "published, removed, or edited"):
            self.prepare()
        self.assertEqual(len(self.api.calls), before)


if __name__ == "__main__":
    unittest.main()
