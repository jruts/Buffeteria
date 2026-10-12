# Buffeteria agent instructions

These instructions apply to the entire repository.

## Project

Buffeteria is a Lua 5.1 add-on for World of Warcraft: Forever, targeting interface
`16001` (client `1.60.1`). Keep code compatible with this client. Read `README.md`
for feature behavior and code organization. `Buffeteria.toc` defines runtime file
load order; add new runtime files there after their dependencies.

## Required: update the installed development add-on after every change

**Changing this repository is not enough. Before reporting a change as complete,
overwrite the installed Buffeteria-Dev add-on with the current workspace's runtime
files. This is a required part of every change, so the user can test it in-game
with `/reload`.**

The WoW Forever installation used on this machine loads development changes from:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Buffeteria-Dev
```

The repository and installed add-on are separate directories. Do not assume
changes in the repository reach the game automatically. The sibling `Buffeteria`
directory belongs to the published release (for example, installed by CurseForge).
Never deploy workspace changes there. The user compares Live and Dev by enabling
one at a time in the AddOns menu.

1. Complete the edits and run checks appropriate to the change. For runtime Lua
   changes, run `python tests/test_addon.py` (requires `lupa` with Lua 5.1).
2. Run `python tools/deploy_dev.py`. This is the required deployment command. It
   verifies the existing `Interface/AddOns` path, builds a Dev copy under
   `.release/dev-builds/`, backs up every installed file it will overwrite to a
   unique directory under `.release/local-backups/`, then **overwrites** the Dev
   runtime files and verifies their SHA-256 hashes. These directories are ignored
   by Git. It can create the `Buffeteria-Dev` folder on the first deployment.
3. The deployment includes `App`, `Shared`, `Features`, `Media`, `Bindings.xml`,
   and additional runtime files listed in the TOC. It derives `Buffeteria-Dev.toc`
   from `Buffeteria.toc` with Dev title, version, saved variables, compartment
   callback, and icon path. Only this manifest and the bindings are transformed;
   Lua and media files must match the workspace byte for byte. Do not rename the
   repository's release TOC or deploy `.git`, `.github`, `.release`, tests, tools,
   or agent instruction files. Include new runtime assets in the deployment
   script when they are outside the existing directories and TOC file list.
4. Do not report installation as successful unless hash verification passes.
   The script records the build path and installed hashes in the backup's
   `deployment.json`; generated TOC and bindings must match the Dev build.
5. Tell the user the updated **Buffeteria-Dev** add-on is installed and that
   `/reload` loads updates when Dev is enabled. Use `/buffdev` for Dev commands
   and Settings > AddOns > Buffeteria-Dev. If the new folder does not appear in
   the AddOns menu on first installation, restart the client.

Updating this local Buffeteria installation is part of the requested development
work; do not ask for an additional confirmation to perform this step. Preserve
the published `Buffeteria` folder, other add-ons, and the game's `WTF` directory,
including saved variables. Never delete or replace the entire `AddOns` directory.
Dev saves to `BuffeteriaDevCharDB`; Live keeps `BuffeteriaCharDB`. Do not copy or
rename the user's saved-variable files as part of deployment. Dev retains the
release communication protocol so it can be tested with the group's normal
Buffeteria users; enable only one copy at a time to avoid conflicting broadcasts.

If the game's `Interface/AddOns` directory is missing or cannot be written, report the exact limitation
and identify the installation step as unfinished. Do not silently skip deployment
or imply that `/reload` will show workspace changes. If a different installation
is requested, verify its path before copying files.

## Working conventions

- Keep feature logic and views in their owning `Features` directory. Reuse the
  existing feature namespaces and `ns.Events` notifications.
- Preserve unrelated local changes. Do not reset or clean the working tree.
- Update user documentation when behavior or controls change.
- Mock tests cannot verify artwork, layout, or protected casting in the actual
  client. Clearly distinguish automated checks from in-game verification.
- Local installation does not publish a release. Follow `RELEASING.md` only when
  release work is requested.
