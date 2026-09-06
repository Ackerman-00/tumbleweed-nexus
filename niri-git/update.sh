#!/bin/bash

SPEC_FILE="niri-git.spec"
CHANGES_FILE="niri-git.changes"
GITHUB_REPO="niri-wm/niri"
PACKAGER="Ackerman-00 <quietcraft@gmail.com>"

echo "🔍 Checking for upstream commits on $GITHUB_REPO..."

if [ -n "$GITHUB_TOKEN" ]; then
    API_RESPONSE=$(curl -sL -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPO/commits/main")
else
    API_RESPONSE=$(curl -sL "https://api.github.com/repos/$GITHUB_REPO/commits/main")
fi

LATEST_COMMIT=$(echo "$API_RESPONSE" | jq -r '.sha')
LATEST_DATE_RAW=$(echo "$API_RESPONSE" | jq -r '.commit.committer.date')

if [ -z "$LATEST_COMMIT" ] || [ "$LATEST_COMMIT" == "null" ]; then
    echo "❌ Error: Failed to fetch Niri commit from GitHub. Check API limits or connection."
    exit 1
fi

CURRENT_COMMIT=$(grep -E "^%global commit" "$SPEC_FILE" | awk '{print $3}')
SHORT_COMMIT=${LATEST_COMMIT:0:7}
LATEST_DATE=$(echo "$LATEST_DATE_RAW" | sed 's/[-T:Z]//g')

if [ "$CURRENT_COMMIT" == "$LATEST_COMMIT" ]; then
    echo "✅ Package is already at the latest commit ($SHORT_COMMIT). No update needed."
    exit 0
fi

echo "🚀 Update found: ${CURRENT_COMMIT:0:7} -> $SHORT_COMMIT"

# 0. Download and VERIFY the source tarball BEFORE touching the spec. If the
#    download fails, we exit non-zero with zero file changes so neither git nor
#    OBS ever receives a spec pointing at a missing tarball (the workflow's
#    sync step would otherwise delete the previous good tarball from OBS).
echo "📦 Downloading source tarball..."
rm -f "niri-$SHORT_COMMIT.tar.gz"
curl -fsSL --retry 3 --connect-timeout 20 "https://github.com/$GITHUB_REPO/archive/$LATEST_COMMIT.tar.gz" -o "niri-$SHORT_COMMIT.tar.gz" \
    || { echo "❌ Download failed; OBS sources left untouched."; exit 1; }
if ! [ -s "niri-$SHORT_COMMIT.tar.gz" ] || ! tar -tzf "niri-$SHORT_COMMIT.tar.gz" > /dev/null 2>&1; then
    echo "❌ Downloaded tarball is empty or corrupt; OBS sources left untouched."
    exit 1
fi
echo "✅ Source tarball verified: $(du -h "niri-$SHORT_COMMIT.tar.gz" | cut -f1)"

# 1. Generate the Rust vendor tarball (BEFORE any spec/changes edit, so a
#    failure anywhere leaves git and OBS untouched)
echo "📦 Extracting source and generating Rust vendor tarball..."
rm -f vendor.tar.xz cargo_config
tar -xzf "niri-$SHORT_COMMIT.tar.gz"
cd "niri-$LATEST_COMMIT" || exit 1

echo "⚙️  Vendoring cargo dependencies (This might take a minute)..."
if ! cargo vendor > ../cargo_config.tmp 2> /tmp/cargo-vendor.err; then
    cat /tmp/cargo-vendor.err
    echo "❌ cargo vendor failed; OBS sources left untouched."
    exit 1
fi
# cargo 1.98 prints "Updating crates.io index" to stdout when cache is cold (corrupts config)
# Ensure cargo_config is valid TOML starting with [source]
if ! head -1 ../cargo_config.tmp | grep -q "^\[source"; then
    sed -n '/^\[source/,$p' ../cargo_config.tmp > ../cargo_config
else
    mv ../cargo_config.tmp ../cargo_config
fi
rm -f ../cargo_config.tmp

echo "🗜️  Compressing vendor tarball..."
tar -cJf ../vendor.tar.xz vendor
cd ..
rm -rf "niri-$LATEST_COMMIT"

if ! [ -s vendor.tar.xz ] || ! [ -s cargo_config ]; then
    echo "❌ Vendor tarball/config missing; OBS sources left untouched."
    exit 1
fi

# 2. Update the spec file globals natively (Version is compiled dynamically in the spec now)
sed -i -E "s/^%global commit.*/%global commit          $LATEST_COMMIT/" "$SPEC_FILE"
sed -i -E "s/^%global shortcommit.*/%global shortcommit     $SHORT_COMMIT/" "$SPEC_FILE"
sed -i -E "s/^%global gitdate.*/%global gitdate         $LATEST_DATE/" "$SPEC_FILE"
sed -i -E "s/^Release:.*/Release:        0/" "$SPEC_FILE"

# Keep the Version prefix in sync with upstream's calendar-version scheme
# (Cargo.toml "26.4.0" -> tag v26.04 - minor zero-padded, trailing .0 dropped)
UPSTREAM_VERSION=$(curl -fsSL --retry 3 --connect-timeout 20 "https://raw.githubusercontent.com/$GITHUB_REPO/$LATEST_COMMIT/Cargo.toml" | grep -A8 "^\[workspace.package\]" | grep -m1 "^version" | sed 's/version *= *"\([^"]*\)".*/\1/')
if [ -n "$UPSTREAM_VERSION" ]; then
    PREFIX=$(echo "$UPSTREAM_VERSION" | awk -F. '{m=$2+0; buf=sprintf("%d.%02d", $1, m); if ($3 != "" && $3+0 != 0) buf=buf "." $3; print buf}')
    sed -i -E "s/^Version:[[:space:]]+.*/Version:        ${PREFIX}+git%{gitdate}.%{shortcommit}/" "$SPEC_FILE"
    echo "Version prefix synced to upstream $PREFIX"
fi

# 3. Generate OBS Changes File
echo "📝 Generating OBS changes file..."
FORMATTED_DATE=$(LC_ALL=C date +"%a %b %d %T UTC %Y")
NEW_CHANGELOG_ENTRY="-------------------------------------------------------------------\n$FORMATTED_DATE - $PACKAGER\n\n- Nightly sync with upstream main branch (Commit: $SHORT_COMMIT)\n\n"

if [ -f "$CHANGES_FILE" ]; then
    echo -e "$NEW_CHANGELOG_ENTRY$(cat $CHANGES_FILE)" > "$CHANGES_FILE"
else
    echo -e "$NEW_CHANGELOG_ENTRY" > "$CHANGES_FILE"
fi

echo "🎉 Success! Niri updated to $SHORT_COMMIT. Ready for OBS sync."