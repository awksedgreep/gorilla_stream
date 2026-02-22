#!/bin/bash
set -euo pipefail

VERSION=$(sed -n 's/.*@version "\(.*\)"/\1/p' mix.exs)
TAG="v${VERSION}"

echo "==> Releasing gorilla_stream ${TAG}"
echo ""

# Check that the tag exists on the remote
if ! git ls-remote --tags origin "refs/tags/${TAG}" | grep -q "${TAG}"; then
  echo "ERROR: Tag ${TAG} not found on remote."
  echo "Push it first:  git tag ${TAG} && git push origin ${TAG}"
  exit 1
fi

# Wait for CI precompile workflow to finish
echo "==> Waiting for precompile CI to finish for ${TAG}..."
RUN_ID=$(gh run list --workflow=precompile.yml --branch="${TAG}" --limit=1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
  echo "ERROR: No precompile workflow run found for ${TAG}."
  echo "Did you push the tag? The workflow triggers on v* tags."
  exit 1
fi

gh run watch "$RUN_ID" --exit-status
echo ""

# Verify release assets exist
echo "==> Checking release assets..."
ASSET_COUNT=$(gh release view "${TAG}" --json assets --jq '.assets | length')
if [ "$ASSET_COUNT" -eq 0 ]; then
  echo "ERROR: No assets found on release ${TAG}."
  echo "Check the CI run for failures: gh run view ${RUN_ID}"
  exit 1
fi
echo "    Found ${ASSET_COUNT} precompiled artifacts."
gh release view "${TAG}" --json assets --jq '.assets[].name' | sed 's/^/    /'
echo ""

# Generate checksums
echo "==> Generating checksums..."
MIX_ENV=prod mix elixir_make.checksum --all --ignore-unavailable
echo ""

# Verify checksum.exs is not empty
if grep -q '^%{}$' checksum.exs; then
  echo "ERROR: checksum.exs is empty. No artifacts were checksummed."
  exit 1
fi

CHECKSUM_COUNT=$(grep -c '=>' checksum.exs)
echo "    ${CHECKSUM_COUNT} checksums generated."
echo ""

# Publish
echo "==> Publishing to Hex..."
mix hex.publish
echo ""

# Clean up
rm -f checksum.exs
echo "==> Done! gorilla_stream ${TAG} published."
