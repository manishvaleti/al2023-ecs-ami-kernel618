# CI executor image: Alpine + Packer + the pinned amazon plugin, all pulled
# from the org S3 bucket (no curl / no GitHub / no HashiCorp releases at build time).
#
# Assumptions (per environment):
#   - Base image already has: aws-cli, unzip, bash, ca-certificates, git.
#   - The image builder (BuildKit / kaniko runner) has AWS credentials via an
#     instance/task role that can s3:GetObject on the artifact bucket.
#     If you must pass static creds instead, use a BuildKit secret mount -
#     see the commented `--mount` line below.
#
# Artifacts expected in S3 (staged once by ci/stage-packer-artifacts.sh):
#   s3://$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/packer_${PACKER_VERSION}_linux_amd64.zip
#   s3://$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/packer-plugin-amazon_v${AMAZON_PLUGIN_VERSION}_x5.0_linux_amd64.zip

ARG BASE_IMAGE=alpine:3.20
FROM ${BASE_IMAGE}

ARG PACKER_VERSION=1.11.2
ARG AMAZON_PLUGIN_VERSION=1.2.8
ARG AMAZON_PLUGIN_API=x5.0
ARG TARGETARCH=amd64
ARG ARTIFACT_BUCKET=triage
ARG ARTIFACT_PREFIX=packer

# System-wide plugin dir so `packer validate` / `packer build` never need `packer init`.
ENV PACKER_PLUGIN_PATH=/usr/local/share/packer/plugins

# Uncomment if the base image lacks these:
# RUN apk add --no-cache aws-cli unzip bash ca-certificates git

# RUN --mount=type=secret,id=aws_creds,target=/root/.aws/credentials \
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    mkdir -p "${PACKER_PLUGIN_PATH}"; \
    \
    # --- Packer binary (static Go, runs fine on musl/Alpine) ---
    aws s3 cp "s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/packer_${PACKER_VERSION}_linux_${TARGETARCH}.zip" "${tmp}/packer.zip"; \
    unzip -o "${tmp}/packer.zip" -d /usr/local/bin/; \
    chmod +x /usr/local/bin/packer; \
    \
    # --- amazon plugin, installed into PACKER_PLUGIN_PATH with the SHA256SUM sidecar ---
    aws s3 cp "s3://${ARTIFACT_BUCKET}/${ARTIFACT_PREFIX}/packer-plugin-amazon_v${AMAZON_PLUGIN_VERSION}_${AMAZON_PLUGIN_API}_linux_${TARGETARCH}.zip" "${tmp}/amazon.zip"; \
    unzip -o "${tmp}/amazon.zip" -d "${tmp}/amazon"; \
    packer plugins install --path "${tmp}/amazon/packer-plugin-amazon_v${AMAZON_PLUGIN_VERSION}_${AMAZON_PLUGIN_API}_linux_${TARGETARCH}" "github.com/hashicorp/amazon"; \
    \
    rm -rf "${tmp}"; \
    packer version; \
    packer plugins installed

# Sanity: this must list github.com/hashicorp/amazon v1.2.8 and exit 0.
RUN packer plugins installed | grep -q "hashicorp/amazon"
