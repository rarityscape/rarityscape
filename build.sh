#!/usr/bin/env bash
# Usage: ./build.sh [version]
# Builds dist/rarityscape-<version>.zip, for both the Mod.io upload and testers: main.lua and
# plugin.json at the top level (Mod.io requires it), production API, trackingAccess and
# httpAccess required. The version (a release tag like v0.2.0 works too) is written into the
# zipped plugin.json and sync/api.lua; without one, plugin.json's version is used.
# Leaves out development files (dev/, .idea/, dist/, git files, this script, README.md) and the
# Mod.io listing (modio-description.md, art/). Testers extract it into dev_plugins\rarityscape
# (see README.md).
set -euo pipefail
cd "$(dirname "$0")"

version=${1:-$(jq -r .version plugin.json)}
version=${version#v}
[[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] \
    || { echo "version must be numbers and dots, like 0.2.0 (Mod.io requires it), got: $version" >&2; exit 1; }
grep -q '^local DEV_DUMP = nil' main.lua \
    || { echo "set DEV_DUMP = nil in main.lua: dev/ isn't shipped" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -r . "$stage"
rm -rf "$stage"/{.git,.github,.gitignore,.idea,dev,dist,art,build.sh,README.md,modio-description.md}
jq --arg version "$version" '.version = $version
    | .urls.api = "https://rarityscape.com"
    | .requiredPermissions = ["trackingAccess", "httpAccess"]
    | .optionalPermissions = []' plugin.json > "$stage/plugin.json"
sed -i "s/^local PLUGIN_VERSION = \".*\"/local PLUGIN_VERSION = \"$version\"/" "$stage/sync/api.lua"
grep -q "^local PLUGIN_VERSION = \"$version\"$" "$stage/sync/api.lua" \
    || { echo "couldn't set PLUGIN_VERSION in sync/api.lua" >&2; exit 1; }

zip="dist/rarityscape-$version.zip"
mkdir -p dist
rm -f dist/*.zip
(cd "$stage" && zip -qr - .) > "$zip"
unzip -l "$zip"
