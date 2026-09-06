#!/bin/bash

SPEC_FILE="matugen.spec"
CHANGES_FILE="matugen.changes"
REPO="InioX/matugen"
PACKAGER="Ackerman-00 <quietcraft@gmail.com>"

echo "🔍 Checking for updates..."

# Get latest release tag from GitHub API (authenticated to avoid rate limits).
# Retry on transient network/API failures so one hiccup does not stub the
# version and abort the whole update.
LATEST_TAG=""
for attempt in 1 2 3; do
    if [ -n "$GITHUB_TOKEN" ]; then
        RESP=$(curl -s --retry 3 --connect-timeout 15 -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/releases/latest")
    else
        RESP=$(curl -s --retry 3 --connect-timeout 15 "https://api.github.com/repos/$REPO/releases/latest")
    fi
    LATEST_TAG=$(echo "$RESP" | jq -r '.tag_name')
    if [ -n "$LATEST_TAG" ] && [ "$LATEST_TAG" != "null" ]; then
        break
    fi
    echo "   Retry $attempt: could not fetch latest tag from GitHub..."
    sleep 5
done
NEW_VER="${LATEST_TAG#v}"

if [ -z "$NEW_VER" ] || [ "$NEW_VER" == "null" ]; then
    echo "❌ Error: Could not fetch latest version."
    exit 1
fi

CURRENT_VER=$(grep "^Version:" "$SPEC_FILE" | awk '{print $2}')

echo "   📂 Current Local: $CURRENT_VER"
echo "   ☁️  Latest Online: $NEW_VER"

if [ "$NEW_VER" == "$CURRENT_VER" ]; then
    echo "✅ Package is already up to date."
    exit 0
fi

echo "🚀 New version found! Updating $SPEC_FILE..."

# 0. Download and VERIFY the source tarball BEFORE touching the spec.
echo "📦 Downloading source tarball..."
rm -f "matugen-$NEW_VER.tar.gz"
curl -fsSL --retry 3 --connect-timeout 20 "https://github.com/$REPO/archive/refs/tags/$LATEST_TAG.tar.gz" -o "matugen-$NEW_VER.tar.gz" \
    || { echo "❌ Download failed; spec left untouched."; exit 1; }
if ! [ -s "matugen-$NEW_VER.tar.gz" ] || ! tar -tzf "matugen-$NEW_VER.tar.gz" > /dev/null 2>&1; then
    echo "❌ Downloaded tarball is empty or corrupt; spec left untouched."
    exit 1
fi

echo "📦 Generating Rust vendor tarball..."

tar -xzf "matugen-$NEW_VER.tar.gz"
cd "matugen-$NEW_VER" || exit 1

# Generate vendor directory and config
echo "⚙️  Vendoring cargo dependencies..."
if ! cargo vendor > ../cargo_config.tmp 2> /tmp/cargo-vendor.err; then
    cat /tmp/cargo-vendor.err
    echo "❌ cargo vendor failed; spec left untouched."
    exit 1
fi
if ! head -1 ../cargo_config.tmp | grep -q "^\[source"; then
    sed -n '/^\[source/,$p' ../cargo_config.tmp > ../cargo_config
else
    mv ../cargo_config.tmp ../cargo_config
fi
rm -f ../cargo_config.tmp

# Compress the vendor directory
echo "🗜️  Compressing vendor tarball..."
tar -cJf ../vendor.tar.xz vendor

# Cleanup
cd ..
rm -rf "matugen-$NEW_VER"

if ! [ -s vendor.tar.xz ] || ! [ -s cargo_config ]; then
    echo "❌ Vendor tarball/config missing; spec left untouched."
    exit 1
fi

# Update the spec (last, so a failure above leaves git/OBS untouched)
sed -i "s|^Version:.*|Version:        $NEW_VER|" "$SPEC_FILE"
sed -i "s|^Release:.*|Release:        0|" "$SPEC_FILE"

echo "📝 Updating changelog..."
FORMATTED_DATE=$(LC_ALL=C date +"%a %b %d %T UTC %Y")
NEW_CHANGELOG_ENTRY="-------------------------------------------------------------------\n$FORMATTED_DATE - $PACKAGER\n\n- Update matugen to v$NEW_VER\n\n"

if [ -f "$CHANGES_FILE" ]; then
    echo -e "$NEW_CHANGELOG_ENTRY$(cat $CHANGES_FILE)" > "$CHANGES_FILE"
else
    echo -e "$NEW_CHANGELOG_ENTRY" > "$CHANGES_FILE"
fi

echo "🎉 Success! Git files updated to v$NEW_VER and tarballs generated. Ready for OBS sync."
