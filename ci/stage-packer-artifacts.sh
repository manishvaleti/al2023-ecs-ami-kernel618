#!/usr/bin/env bash
# Run ONCE from a machine that has outbound internet (or wire this into the
# org's artifact-mirroring pipeline). Downloads the exact Packer binary and
# amazon plugin used by this repo and uploads them to the org S3 bucket that
# the CI image build reads from.
#
# The bucket itself is managed by IaC at org level - this script only puts
# objects into the agreed prefix.
set -euo pipefail

PACKER_VERSION="${PACKER_VERSION:-1.11.2}"
AMAZON_PLUGIN_VERSION="${AMAZON_PLUGIN_VERSION:-1.2.8}"   # must match required_plugins in variables.pkr.hcl
AMAZON_PLUGIN_API="${AMAZON_PLUGIN_API:-x5.0}"
ARCH="${ARCH:-amd64}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-triage}"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-packer}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

packer_zip="packer_${PACKER_VERSION}_linux_${ARCH}.zip"
plugin_zip="packer-plugin-amazon_v${AMAZON_PLUGIN_VERSION}_${AMAZON_PLUGIN_API}_linux_${ARCH}.zip"

echo "Downloading ${packer_zip}"
curl -fLsS -o "${packer_zip}"      "https://releases.hashicorp.com/packer/${PACKER_VERSION}/${packer_zip}"
curl -fLsS -o "${packer_zip}.sums" "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS"
grep " ${packer_zip}\$" "${packer_zip}.sums" | sha256sum -c -

echo "Downloading ${plugin_zip}"
base="https://github.com/hashicorp/packer-plugin-amazon/releases/download/v${AMAZON_PLUGIN_VERSION}"
curl -fLsS -o "${plugin_zip}"   "${base}/${plugin_zip}"
curl -fLsS -o "SHA256SUMS"      "${base}/packer-plugin-amazon_v${AMAZON_PLUGIN_VERSION}_SHA256SUMS"
grep " ${plugin_zip}\$" "SHA256SUMS" | sha256sum -c -

echo "Uploading to s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/"
aws s3 cp "${packer_zip}" "s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/${packer_zip}"
aws s3 cp "${plugin_zip}" "s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/${plugin_zip}"

echo "Done. Staged:"
echo "  s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/${packer_zip}"
echo "  s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/${plugin_zip}"
