"""Build and install Buffeteria-Dev without touching the release add-on."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ADDONS = Path(r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns")
DEV_NAME = "Buffeteria-Dev"
RUNTIME_DIRS = ("App", "Shared", "Features", "Media")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dev_toc(source):
    headers = {
        "Title": DEV_NAME,
        "Version": "local-dev",
        "SavedVariablesPerCharacter": "BuffeteriaDevCharDB",
        "AddonCompartmentFunc": "BuffeteriaDev_OnAddonCompartmentClick",
        "IconTexture": r"Interface\AddOns\Buffeteria-Dev\Media\Icon",
    }
    for key, value in headers.items():
        source, count = re.subn(r"^## " + key + r":[^\r\n]*", lambda _: "## " + key + ": " + value,
                                source, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"Expected exactly one {key} header in Buffeteria.toc")
    return source


def runtime_sources(repo):
    sources = {Path("Bindings.xml"): repo / "Bindings.xml"}
    for directory in RUNTIME_DIRS:
        root = repo / directory
        if not root.is_dir():
            raise FileNotFoundError(f"Missing runtime directory: {root}")
        for path in root.rglob("*"):
            if path.is_file():
                sources[path.relative_to(repo)] = path
    # Include additional runtime files explicitly added to the manifest.
    for line in (repo / "Buffeteria.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        relative = Path(line.replace("\\", "/"))
        path = (repo / relative).resolve()
        if not path.is_relative_to(repo) or relative.parts[0] in (
                ".git", ".github", ".release", "tests", "tools") or relative.name in ("AGENTS.md", "CLAUDE.md"):
            raise ValueError(f"Invalid runtime path: {line}")
        sources[relative] = path
    return sources


def dev_bindings(source):
    if source.count("Buffeteria_CastButton") != 1 or source.count('header="BUFFETERIA"') != 1:
        raise ValueError("Expected the Buffeteria cast binding and header in Bindings.xml")
    return source.replace("Buffeteria_CastButton", "BuffeteriaDev_CastButton").replace(
        'header="BUFFETERIA"', 'header="BUFFETERIADEV"')


def build_dev(repo, stage):
    """Copy source bytes unchanged, except the Dev manifest and bindings."""
    sources = runtime_sources(repo)
    for relative, source in sources.items():
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    bindings = dev_bindings((stage / "Bindings.xml").read_text(encoding="utf-8"))
    (stage / "Bindings.xml").write_text(bindings, encoding="utf-8")
    toc = dev_toc((repo / "Buffeteria.toc").read_text(encoding="utf-8"))
    (stage / (DEV_NAME + ".toc")).write_text(toc, encoding="utf-8")
    for relative, source in sources.items():
        if relative != Path("Bindings.xml") and digest(source) != digest(stage / relative):
            raise RuntimeError(f"Build differs from workspace: {relative}")


def deploy(addons_dir=DEFAULT_ADDONS, repo=ROOT):
    repo = repo.resolve()
    addons_dir = addons_dir.resolve(strict=True)
    if not addons_dir.is_dir() or addons_dir.name != "AddOns" or addons_dir.parent.name != "Interface":
        raise ValueError(f"Expected an existing Interface/AddOns directory: {addons_dir}")
    destination = addons_dir / DEV_NAME
    # Refuse links/junctions that would redirect the deployment into Live or elsewhere.
    if destination.resolve() != destination:
        raise ValueError(f"Dev destination resolves outside its expected path: {destination}")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8]
    stage = repo / ".release" / "dev-builds" / run_id / DEV_NAME
    build_dev(repo, stage)
    files = sorted(path.relative_to(stage) for path in stage.rglob("*") if path.is_file())
    backup = repo / ".release" / "local-backups" / run_id
    backup.mkdir(parents=True)
    # Finish all backups before overwriting any installed file.
    for relative in files:
        target = destination / relative
        if target.resolve() != target:
            raise ValueError(f"Installed file resolves outside its expected path: {target}")
        if target.exists():
            saved = backup / DEV_NAME / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
            if digest(saved) != digest(target):
                raise RuntimeError(f"Backup verification failed: {relative}")
    hashes = {str(relative): digest(stage / relative) for relative in files}
    (backup / "deployment.json").write_text(json.dumps({
        "destination": str(destination), "build": str(stage), "sha256": hashes,
    }, indent=2), encoding="utf-8")
    for relative in files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stage / relative, target)
    for relative in files:
        if digest(destination / relative) != hashes[str(relative)]:
            raise RuntimeError(f"Installed hash differs from Dev build: {relative}")
    # Check against the current workspace as well as the staged Dev build.
    for relative, source in runtime_sources(repo).items():
        if relative != Path("Bindings.xml") and digest(source) != digest(destination / relative):
            raise RuntimeError(f"Installed hash differs from workspace: {relative}")
    if (destination / (DEV_NAME + ".toc")).read_text(encoding="utf-8") != dev_toc(
            (repo / "Buffeteria.toc").read_text(encoding="utf-8")):
        raise RuntimeError("Installed Dev manifest differs from current workspace metadata")
    if (destination / "Bindings.xml").read_text(encoding="utf-8") != dev_bindings(
            (repo / "Bindings.xml").read_text(encoding="utf-8")):
        raise RuntimeError("Installed Dev bindings differ from current workspace bindings")
    return destination, backup, len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addons-dir", type=Path, default=DEFAULT_ADDONS,
                        help="Existing Interface/AddOns directory (default: local WoW Forever install)")
    args = parser.parse_args()
    destination, backup, count = deploy(args.addons_dir)
    print(f"Installed {destination}; SHA-256 verified {count} runtime files.")
    print(f"Backup and deployment hashes: {backup}")
    print("Enable only Buffeteria-Dev in the AddOns menu. /reload loads updates; /buffdev opens options.")


if __name__ == "__main__":
    main()
