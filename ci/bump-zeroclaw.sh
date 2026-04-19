#!/bin/bash -e
# Check upstream for a newer zeroclaw prerelease (beta). If newer than
# what debian/changelog declares, bump the version + SHA256s and commit
# — the subsequent pipeline rebuilds the deb and publish-to-apt ships it.

REPO="zeroclaw-labs/zeroclaw"
CUR=$(dpkg-parsechangelog -l zeroclaw/debian/changelog -S Version | sed 's|-.*||; s|~|-|')
LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
    | jq -r '[.[] | select(.prerelease) | .tag_name] | .[0]' \
    | sed 's|^v||')

if [ "$CUR" = "$LATEST" ]; then
    echo "zeroclaw already at latest beta: $LATEST"
    exit 0
fi

echo "Bumping zeroclaw $CUR -> $LATEST"

SHA_ARM64=$(curl -fsSL "https://github.com/${REPO}/releases/download/v${LATEST}/SHA256SUMS" \
    | awk '/zeroclaw-aarch64-unknown-linux-gnu.tar.gz/ {print $1}')
SHA_AMD64=$(curl -fsSL "https://github.com/${REPO}/releases/download/v${LATEST}/SHA256SUMS" \
    | awk '/zeroclaw-x86_64-unknown-linux-gnu.tar.gz/ {print $1}')

if [ -z "$SHA_ARM64" ] || [ -z "$SHA_AMD64" ]; then
    echo "Failed to fetch SHA256 for $LATEST" >&2
    exit 1
fi

cd zeroclaw
sed -i "s|^ZEROCLAW_VERSION = .*|ZEROCLAW_VERSION = ${LATEST}|" debian/rules
sed -i "s|^ZEROCLAW_SHA256_ARM64 = .*|ZEROCLAW_SHA256_ARM64 = ${SHA_ARM64}|" debian/rules
sed -i "s|^ZEROCLAW_SHA256_AMD64 = .*|ZEROCLAW_SHA256_AMD64 = ${SHA_AMD64}|" debian/rules

# Debian version: 0.7.3-beta.1051 -> 0.7.3~beta.1051-1
DEB_VERSION=$(echo "$LATEST" | sed 's|-beta|~beta|')-1
dch -v "$DEB_VERSION" --distribution=trixie "Track upstream master: v${LATEST}"

cd ..
git add zeroclaw/debian/rules zeroclaw/debian/changelog
git commit -m "zeroclaw: track upstream v${LATEST}" \
           -m "Auto-bumped by track-zeroclaw CI job."
git push "https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" HEAD:master
