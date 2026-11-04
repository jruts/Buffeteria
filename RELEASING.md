# Releasing Buffeteria

Publishing a GitHub release builds an installable ZIP, attaches it to that release,
and uploads the same ZIP to CurseForge. Pushing a tag or saving a draft does not
publish to CurseForge. Finish the one-time setup below before publishing.

## Create the CurseForge project

1. Sign in and open [Create Project](https://authors.curseforge.com/#/projects/create/choose-game).
2. Choose **World of Warcraft**, class **Addons**, and name **Buffeteria**.
3. Suggested summary: **Raid buff coordination for WoW Forever: rank your buffs,
   share assignments, and track missing buffs.** Use [README.md](README.md) as the
   description and mention that this targets **WoW Forever 1.60.1**.
4. Select suitable categories, such as Buffs & Debuffs and Raid. Choose your license
   in the project form; this repository does not currently declare a license.
5. Upload the initial ZIP under the project's **Files** tab, selecting **WoW
   Forever / 1.60.1** and the appropriate release type. You can get a ZIP without
   publishing a GitHub release: open [Actions > Release](https://github.com/jruts/Buffeteria/actions/workflows/release.yml),
   click **Run workflow**, then download the **Buffeteria** artifact from the
   completed run. Extract the artifact download once to get the actual add-on ZIP.
   Upload that inner ZIP to CurseForge.
6. The first file submits the project for moderation. Public availability depends
   on project and file approval. Copy the numeric **Project ID** from the dashboard.

See CurseForge's [project creation guide](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project)
for the current form and approval process.

## Connect GitHub to CurseForge

In [repository Actions settings](https://github.com/jruts/Buffeteria/settings/secrets/actions):

- Under **Variables**, create `CF_PROJECT_ID` with the numeric project ID.
- Under **Secrets**, create `CF_API_KEY` with an upload API token generated at
  [CurseForge API Tokens](https://authors.curseforge.com/#/settings/api-tokens).
  Use the author upload token, not a third-party download API key.
  Paste it directly into GitHub; do not commit it or put it in chat.

The GitHub token is supplied automatically by Actions. No additional GitHub secret
is needed. Without the CurseForge settings, a published release still gets its ZIP,
but the CurseForge step fails with setup instructions. After adding the missing
settings, rerun the failed job. **Release > Run workflow** builds only and never uploads.

## Publish each release

1. Push changes to `main`. **Actions > Prepare release** runs the add-on and release
   automation checks, calculates the next patch version from the highest published
   stable release, commits its entry to `CHANGELOG.md`, and prepares a GitHub draft.
   For example, `v0.6.13` becomes `v0.6.14`; no version editing is needed.
2. Test in-game, then open the draft in
   [GitHub Releases](https://github.com/jruts/Buffeteria/releases). Review its notes
   and click **Publish release** after **Prepare release** finishes successfully.
   The draft targets the exact checked commit, including its changelog entry.
3. Further pushes update the same draft and notes until you publish it. The next
   change after publication starts the next patch draft. A run with no changes
   since the published version does not create an empty release.
4. Watch **Actions > Release**. A successful run means CurseForge accepted the
   upload; its moderation process determines when the file becomes public.

For a larger release, open
[Actions > Prepare release](https://github.com/jruts/Buffeteria/actions/workflows/prepare-release.yml),
click **Run workflow** on `main`, and choose **minor** (for example, `0.6.13` to
`0.7.0`) or **major** (`1.0.0`). **auto** keeps an existing draft's version and
otherwise chooses patch; **patch** explicitly switches a pending override back to
the next patch version. Ordinary pushes retain the override until publication.

Notes list commit subjects and links automatically. Put player-facing summaries
above or below the `buffeteria:auto-notes` comments in the pending changelog
section; those additions survive regeneration. In the GitHub draft, put manual
text outside the `buffeteria:auto-release` comments. The text inside these blocks
is regenerated on each push. Old published changelog sections are preserved.

The workflow only manages the draft it created. It refuses conflicting releases,
existing Git tags, multiple automated drafts, or a checkout that changed during
validation. It never publishes a release, moves a tag, or force-pushes `main`.
It uses the built-in GitHub token with `contents: write`; no new secret is needed.
The changelog commit does not trigger another workflow run. Pull `main` before
your next local push to include that commit. If branch protection is introduced,
it must allow the automation's changelog commit or preparation will fail.

You can rerun **Prepare release** after a transient failure. It reuses the draft
and changelog entry instead of incrementing the version again. The separate
**Release > Run workflow** command still builds a ZIP only.

Tags containing `alpha` or `beta` upload as that type. A plain version tag uploads
as Release unless you check GitHub's **pre-release** option, which uploads as Beta.
Use a new tag/version for each release. A workflow rerun may create a second
CurseForge file if the earlier upload already succeeded; check Files first.

`## Version: @project-version@` is replaced in the ZIP from the checked-out version.
GitHub's automatic source archives are not the installable add-on ZIP.

## WoW Forever game version

`Buffeteria.toc` targets interface `16001`, corresponding to **1.60.1**.
The workflow uses the BigWigs packager to build, then the
[CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api)
to select that exact game version. The packager's v2.5.1 built-in uploader would
classify this interface as Retail and may fall back to an unrelated version, so it
is deliberately disabled. An absent or ambiguous exact match fails the upload.
When Forever updates, update the TOC after testing the add-on on that client.

The repository contains the supplied add-on source; packaging checks do not establish
that every feature works in-game. Test a release in WoW Forever before publishing.
