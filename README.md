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
```

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

```bash
packer init .
packer validate -var region=us-east-1 .
REGION=us-east-1 packer build -only=amazon-ebs.al2023 -var region=us-east-1 .
```

## Reproducible builds

`source_ami_al2023` uses a wildcard + `most_recent=true`. Pin the exact dated name
(e.g. `al2023-ami-minimal-2023.8.20260901.0-kernel-6.18-x86_64`) to freeze the base
image.
