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
  [CurseForge API Tokens](https://authors.curseforge.com/#/user/api-tokens).
  Use the author upload token, not a third-party download API key.
  Paste it directly into GitHub; do not commit it or put it in chat.

The GitHub token is supplied automatically by Actions. No additional GitHub secret
is needed. Without the CurseForge settings, a published release still gets its ZIP,
but the CurseForge step fails with setup instructions. After adding the missing
settings, rerun the failed job. Manual **Run workflow** builds only and never uploads.

## Publish each release

1. Add the version's notes at the top of `CHANGELOG.md` and push the code to GitHub.
2. Open [GitHub Releases](https://github.com/jruts/Buffeteria/releases) and click
   **Draft a new release**. Choose or create a version tag, for example `v0.5.0`,
   targeting the commit containing your changes.
3. Add a title and release notes, then click **Publish release**.
4. Watch **Actions > Release**. A successful run means CurseForge accepted the
   upload; its moderation process determines when the file becomes public.

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
