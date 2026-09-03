# AL2023 x86_64 ECS-optimized AMI — kernel 6.18, GitLab CI

Self-contained subset of [`aws/amazon-ecs-ami`](https://github.com/aws/amazon-ecs-ami)
that builds **one** AMI: Amazon Linux 2023, `x86_64`, ECS-optimized, on **kernel 6.18**
instead of the upstream default kernel 6.1. Everything else (ECS agent, Docker,
containerd, runc, ECS exec, EFS/SSM/Service Connect, cleanup) matches the upstream
`20260901` release.

## What changed vs upstream

| | Upstream | Here |
|---|---|---|
| Base AMI | `al2023-ami-minimal-...-kernel-6.1-x86_64` | `al2023-ami-minimal-2023.*-kernel-6.18-x86_64` |
| Architectures | x86_64 + arm64 + GPU + Neuron | x86_64 only |
| Driver | `make` from a laptop | GitLab CI/CD pipeline (`.gitlab-ci.yml`) |

The kernel is **not** swapped in a provisioner — AWS publishes a kernel-6.18
minimal AMI, so we just point `source_ami_al2023` at it (see
`release-al2023.auto.pkrvars.hcl`). `packer build` runs `dnf update --releasever=latest`
then reboots, so the image ships the latest 6.18 patch level.

## Files

```
al2023.pkr.hcl                     source + build definition (x86 only)
variables.pkr.hcl                  variable declarations + required_plugins
release-al2023.auto.pkrvars.hcl    pinned versions + kernel-6.18 base AMI
scripts/ files/ additional-packages/ amazon-ecs-logs-collector/
                                   only the provisioner assets this build uses
.gitlab-ci.yml                     validate + build pipeline
ci/Dockerfile                      Alpine CI executor: packer + amazon plugin from S3
ci/stage-packer-artifacts.sh       one-time: mirror packer + plugin into the org S3 bucket
```

## Air-gapped CI image (no curl at build time)

The GitLab runner image is built from [`ci/Dockerfile`](ci/Dockerfile) on Alpine.
Instead of downloading Packer from `releases.hashicorp.com` and the plugin via
`packer init` (both blocked), it `aws s3 cp`s two pre-staged artifacts from the
org bucket and installs them:

| Artifact | S3 key (`s3://$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/`) |
|---|---|
| Packer binary | `packer_1.11.2_linux_amd64.zip` |
| amazon plugin (pinned to `required_plugins`) | `packer-plugin-amazon_v1.2.8_x5.0_linux_amd64.zip` |

1. **Stage the artifacts once** from a networked host (or the org mirror pipeline):
   ```bash
   ARTIFACT_BUCKET=triage ci/stage-packer-artifacts.sh
   ```
   The bucket is IaC-managed at org level; this only puts objects under the prefix.
2. **Build the CI image.** The image builder needs `s3:GetObject` on the bucket via
   an instance/task role (or pass static creds with a BuildKit
   `--mount=type=secret,id=aws_creds` — see the commented line in the Dockerfile):
   ```bash
   docker build -t $CI_REGISTRY_IMAGE/al2023-ami-builder:latest \
     --build-arg ARTIFACT_BUCKET=triage ci/
   docker push $CI_REGISTRY_IMAGE/al2023-ami-builder:latest
   ```
3. `packer plugins install --path` drops the plugin into
   `PACKER_PLUGIN_PATH=/usr/local/share/packer/plugins` **with its `_SHA256SUM`
   sidecar**, so `packer validate` / `packer build` resolve it with no network and
   the pipeline never calls `packer init`.

Bump versions in one place: `ARG PACKER_VERSION` / `ARG AMAZON_PLUGIN_VERSION` in
the Dockerfile and the defaults in `stage-packer-artifacts.sh`; the plugin version
must equal `required_plugins.amazon.version` in `variables.pkr.hcl`.

## Running it

1. Push this directory as the **root** of a GitLab repo (or keep it in a subdir and
   set `PKR_DIR` in `.gitlab-ci.yml`).
2. Add CI/CD variables: `AWS_DEFAULT_REGION`, and either `AWS_ACCESS_KEY_ID` +
   `AWS_SECRET_ACCESS_KEY` (mask them) or wire up OIDC (`before_script` has a
   commented `assume-role-with-web-identity` block — the recommended path).
3. The build instance needs outbound internet (or a NAT) and, for
   `ssh_interface=public_ip`, a subnet that assigns public IPs. For private
   subnets set `SSH_INTERFACE=session_manager` and `IAM_INSTANCE_PROFILE` to a
   profile with `AmazonSSMManagedInstanceCore`.
4. `validate` runs automatically; `build-ami` is **manual** on the default branch
   and automatic on tags. The resulting AMI ID is in the `manifest.json` artifact.

## Local smoke test

On a networked machine (uses `packer init` to fetch the plugin):

```bash
packer init .
packer validate -var region=us-east-1 .
packer build -only=amazon-ebs.al2023 -var region=us-east-1 .
```

## Reproducible builds

`source_ami_al2023` uses a wildcard + `most_recent=true`. Pin the exact dated name
(e.g. `al2023-ami-minimal-2023.8.20260901.0-kernel-6.18-x86_64`) to freeze the base
image.
