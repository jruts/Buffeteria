#!/usr/bin/env bash
set -euo pipefail

if [[ ! ${CF_PROJECT_ID:-} =~ ^[1-9][0-9]*$ ]]; then
  echo '::error::Set the repository Actions variable CF_PROJECT_ID to your CurseForge project ID. See RELEASING.md.'
  exit 1
fi
if [[ -z ${CF_API_KEY:-} ]]; then
  echo '::error::Set the repository Actions secret CF_API_KEY to your CurseForge upload API token. See RELEASING.md.'
  exit 1
fi

case "${RELEASE_TYPE:-}" in
  alpha|beta|release) ;;
  *) echo '::error::The packager did not provide a valid release type.'; exit 1 ;;
esac
# The GitHub prerelease switch also works with a plain version tag.
if [[ ${IS_PRERELEASE:-false} == true && $RELEASE_TYPE == release ]]; then
  RELEASE_TYPE=beta
fi

# Match the TOC exactly. The packager's built-in uploader currently classifies
# interface 16001 as Retail and can silently fall back to another version.
interface=$(sed -n 's/^## Interface: *\([0-9]*\).*/\1/p' Buffeteria.toc | tr -d '\r')
if [[ ! $interface =~ ^[0-9]+$ ]]; then
  echo '::error::Buffeteria.toc must contain a numeric Interface value.'
  exit 1
fi
game_version="$((10#$interface / 10000)).$((10#$interface / 100 % 100)).$((10#$interface % 100))"
api='https://wow.curseforge.com/api'
versions=$(curl --fail-with-body --silent --show-error --max-time 60 \
  -H "X-Api-Token: $CF_API_KEY" "$api/game/versions")
version_ids=$(jq -ce --arg version "$game_version" \
  '[.[] | select(.name == $version) | .id] | if length == 1 then . else error("Expected exactly one matching game version") end' <<< "$versions") || {
  echo "::error::CurseForge has no unique match for $game_version. Check the supported versions; no fallback will be uploaded."
  exit 1
}

metadata=$(jq -n --arg name "$(basename "$ARCHIVE_PATH" .zip)" \
  --argjson versions "$version_ids" --arg type "$RELEASE_TYPE" \
  --rawfile changelog CHANGELOG.md \
  '{displayName: $name, gameVersions: $versions, releaseType: $type, changelog: $changelog, changelogType: "markdown"}')
echo "Uploading $(basename "$ARCHIVE_PATH") for WoW $game_version ($RELEASE_TYPE)."
# Do not automatically retry POST: an uncertain response could create duplicate files.
result=$(curl --fail-with-body --silent --show-error --max-time 120 \
  -H "X-Api-Token: $CF_API_KEY" \
  --form-string "metadata=$metadata" --form "file=@$ARCHIVE_PATH" \
  "$api/projects/$CF_PROJECT_ID/upload-file")
file_id=$(jq -er '.id | select(type == "number" and . > 0)' <<< "$result")
echo "CurseForge accepted file $file_id. Public availability is subject to moderation."
