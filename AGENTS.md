# Buffeteria agent instructions

These instructions apply to the entire repository.

## Project

Buffeteria is a Lua 5.1 add-on for World of Warcraft: Forever, targeting interface
`16001` (client `1.60.1`). Keep code compatible with this client. Read `README.md`
for feature behavior and code organization. `Buffeteria.toc` defines runtime file
load order; add new runtime files there after their dependencies.

## Required: update the installed add-on after every change

**Changing this repository is not enough. Before reporting a change as complete,
overwrite the installed Buffeteria add-on with the current workspace's runtime
files. This is a required part of every change, so the user can test it in-game
with `/reload`.**

The WoW Forever installation used on this machine loads Buffeteria from:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Buffeteria
```

The repository and installed add-on are separate directories. Do not assume
changes in the repository reach the game automatically.

1. Complete the edits and run checks appropriate to the change. For runtime Lua
   changes, run `python tests/test_addon.py` (requires `lupa` with Lua 5.1).
2. Back up installed files that will be overwritten to a unique directory under
   `.release/local-backups/`. That directory is ignored by Git.
3. Copy the current runtime files into the installation above, **overwriting
   existing copies**, and preserve their relative paths. Include
   `Buffeteria.toc`, `Bindings.xml`, and the `App`, `Shared`, `Features`, and `Media`
   directories. Include any additional runtime assets introduced by the change.
   Do not copy `.git`, `.github`, `.release`, tests, or agent instruction files.
4. Verify the installed runtime files match the workspace, using file hashes.
   Do not report installation as successful unless this verification passes.
5. Tell the user the updated add-on is installed and that `/reload` loads the
   changes. Mention the relevant tab or command when useful.

Updating this local Buffeteria installation is part of the requested development
work; do not ask for an additional confirmation to perform this step. Preserve
other add-ons and the game's `WTF` directory, including saved variables. Never
delete or replace the entire `AddOns` directory.

If the installation is missing or cannot be written, report the exact limitation
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
