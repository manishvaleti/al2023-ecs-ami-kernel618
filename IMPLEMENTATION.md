# Implementation guide

Step-by-step instructions to stand up this pipeline and produce the AL2023
x86_64 ECS-optimized AMI on **kernel 6.18** in your AWS account, driven by
GitLab CI/CD with an air-gapped (no-curl) build image.

Read this top to bottom the first time. Steps 1–4 are one-time setup; step 5 is
the recurring build.

---

## 0. What you are building

- **One AMI:** Amazon Linux 2023, `x86_64`, ECS-optimized, kernel 6.18.
- Everything else (ECS agent, Docker, containerd, runc, ECS exec, EFS/SSM/
  Service Connect, cleanup) matches `aws/amazon-ecs-ami` release `20260901`.
- The only change vs upstream: the Packer `source_ami_filter` points at the
  AWS-published `al2023-ami-minimal-*-kernel-6.18-x86_64` base image instead of
  the kernel-6.1 one. The kernel is **not** swapped in a script.

```
al2023.pkr.hcl                    Packer source + build (x86 only)
variables.pkr.hcl                 variable + required_plugins declarations
release-al2023.auto.pkrvars.hcl   pinned versions + kernel-6.18 base AMI filter
scripts/ files/ additional-packages/ amazon-ecs-logs-collector/
                                  provisioner assets used by the build
ci/Dockerfile                     Alpine CI executor (packer + plugin from S3)
ci/stage-packer-artifacts.sh      one-time mirror of packer + plugin into S3
.gitlab-ci.yml                    validate + build pipeline
```

---

## 1. Prerequisites

You need, once:

- A networked workstation with `curl`, `unzip`, `sha256sum`, `aws` CLI,
  `docker` (with BuildKit), and `git`.
- AWS access to:
  - the **org artifact S3 bucket** (IaC-managed, e.g. `s3://triage`) — write for
    staging in step 2, read for the image build in step 3.
  - the **target account** where the AMI is built — permissions in
    [Appendix A](#appendix-a-aws-iam-permissions-for-the-build).
- A GitLab project (this repo pushed to GitLab) and a runner that can run
  Docker images (`docker` executor or Kubernetes executor).
- Access to your GitLab container registry (`$CI_REGISTRY_IMAGE`).

Pinned versions (change in one place later — see [step 6](#6-upgrading-versions)):

| Component | Version | Where it is declared |
|---|---|---|
| Packer | `1.11.2` | `ci/Dockerfile` ARG, `ci/stage-packer-artifacts.sh` default |
| `packer-plugin-amazon` | `1.2.8` | `variables.pkr.hcl` `required_plugins`, `ci/Dockerfile` ARG |
| ECS agent / docker / containerd / runc / ssm | see `release-al2023.auto.pkrvars.hcl` |

---

## 2. Stage Packer + the amazon plugin into S3 (one-time)

The CI image cannot reach `releases.hashicorp.com` or GitHub, so mirror the two
binaries into the org bucket first.

```bash
# from the networked workstation, with AWS creds that can write to the bucket
export ARTIFACT_BUCKET=triage      # the org IaC-managed bucket, no s3:// prefix
export ARTIFACT_PREFIX=packer      # agreed key prefix inside the bucket

./ci/stage-packer-artifacts.sh
```

The script:

1. downloads `packer_1.11.2_linux_amd64.zip` from `releases.hashicorp.com` and
   verifies it against the published `SHA256SUMS`;
2. downloads `packer-plugin-amazon_v1.2.8_x5.0_linux_amd64.zip` from the plugin's
   GitHub release and verifies it against its `SHA256SUMS`;
3. uploads both to `s3://$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/`.

> **Why GitHub for the plugin?** HashiCorp only publishes the *core* Packer
> binary on `releases.hashicorp.com`. Packer *plugins* (including the official
> `amazon` one) are released from their own GitHub repos; `packer init` resolves
> them there. There is no `releases.hashicorp.com` URL for the plugin.

Verify:

```bash
aws s3 ls s3://$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/
# packer_1.11.2_linux_amd64.zip
# packer-plugin-amazon_v1.2.8_x5.0_linux_amd64.zip
```

If your org already has an artifact-mirroring pipeline, wire the two `curl` +
`aws s3 cp` lines into it instead of running the script by hand.

---

## 3. Build and push the CI executor image (one-time, then on version bumps)

`ci/Dockerfile` builds an Alpine image that `aws s3 cp`s the two artifacts and
installs the plugin into `PACKER_PLUGIN_PATH` **with its `_SHA256SUM` sidecar**
(via `packer plugins install --path`). Result: `packer validate` / `packer build`
resolve the plugin with zero network and the pipeline never calls `packer init`.

### 3a. Credentials for `aws s3 cp` during the image build

Pick one:

- **Instance / task role (preferred):** run the build on a host whose role has
  `s3:GetObject` on `arn:aws:s3:::$ARTIFACT_BUCKET/$ARTIFACT_PREFIX/*`. Nothing to
  configure in the Dockerfile.
- **BuildKit secret:** uncomment the `--mount=type=secret,id=aws_creds,...` line
  in `ci/Dockerfile` and pass `--secret id=aws_creds,src=$HOME/.aws/credentials`.

### 3b. Build

```bash
export CI_REGISTRY_IMAGE=registry.gitlab.com/<group>/<project>   # your registry path
IMAGE="$CI_REGISTRY_IMAGE/al2023-ami-builder:latest"

DOCKER_BUILDKIT=1 docker build \
  --build-arg ARTIFACT_BUCKET=triage \
  --build-arg ARTIFACT_PREFIX=packer \
  --build-arg PACKER_VERSION=1.11.2 \
  --build-arg AMAZON_PLUGIN_VERSION=1.2.8 \
  -t "$IMAGE" \
  ci/
```

The final `RUN packer plugins installed | grep -q "hashicorp/amazon"` line fails
the build if the plugin did not install — a green build means the image is good.

### 3c. Push

```bash
docker login "$CI_REGISTRY"          # or: echo $CI_JOB_TOKEN | docker login -u ... --password-stdin
docker push "$IMAGE"
```

You can also do 3b/3c as a GitLab job with `docker:dind` or kaniko — out of scope
here, but the `docker build` args above map 1:1.

---

## 4. Configure the GitLab project (one-time)

### 4a. CI/CD variables

**Settings → CI/CD → Variables**:

| Variable | Value | Flags |
|---|---|---|
| `AWS_DEFAULT_REGION` | e.g. `us-east-1` | Protected |
| `AWS_ACCESS_KEY_ID` | build-account key | Masked, Protected |
| `AWS_SECRET_ACCESS_KEY` | build-account secret | Masked, Protected |
| `AWS_SESSION_TOKEN` | only if using temporary creds | Masked, Protected |

**Preferred: OIDC instead of static keys.** Remove the three `AWS_*` key
variables, add `AWS_ROLE_ARN`, and in `.gitlab-ci.yml` uncomment the
`id_tokens:` block + the `assume-role-with-web-identity` line in `before_script`.
See [Appendix B](#appendix-b-gitlab-oidc-to-aws).

### 4b. Pipeline variables to review in `.gitlab-ci.yml`

| Variable | Default | Set when |
|---|---|---|
| `CI_IMAGE` | `${CI_REGISTRY_IMAGE}/al2023-ami-builder:latest` | matches step 3 tag |
| `SUBNET_ID` | `""` (default VPC) | build must run in a specific subnet |
| `SSH_INTERFACE` | `public_ip` | private subnet → set `session_manager` |
| `IAM_INSTANCE_PROFILE` | `""` | required if `SSH_INTERFACE=session_manager` |

If `SSH_INTERFACE=session_manager`: the profile needs
`AmazonSSMManagedInstanceCore`, and the subnet needs SSM connectivity (NAT or
VPC endpoints for `ssm`, `ssmmessages`, `ec2messages`).

### 4c. Runner

Ensure a runner picks up the `docker` tag (see `default.tags` in
`.gitlab-ci.yml`) and can pull `CI_IMAGE` from the registry.

---

## 5. Run a build (recurring)

1. Push to `main` (or open an MR). The **`validate`** stage runs automatically:
   `packer fmt -check` + `packer validate`.
2. Go to **CI/CD → Pipelines**, open the latest pipeline, and click **▶ Run** on
   the manual **`build-ami`** job. (Tag builds run it automatically.)
3. The job runs, roughly 15–30 min:
   - launches a `c5.large` in the target account from the newest
     `al2023-ami-minimal-*-kernel-6.18-x86_64` AMI,
   - provisions ECS agent / Docker / exec / etc.,
   - reboots to activate the latest 6.18 patch,
   - registers the AMI, terminates the builder.
4. Get the AMI ID from the **`manifest.json`** job artifact:
   ```json
   { "builds": [ { "artifact_id": "us-east-1:ami-0abc123...", ... } ] }
   ```
   or from the job log (`Built AMI:` line).

### Verify the result

```bash
aws ec2 describe-images --image-ids ami-0abc123... \
  --query 'Images[0].{Name:Name,State:State}' --region us-east-1
# launch it, then on the instance:
uname -r          # -> 6.18.x
sudo systemctl is-enabled ecs
```

---

## 6. Upgrading versions

### Packer or the amazon plugin

1. Bump `ARG PACKER_VERSION` / `ARG AMAZON_PLUGIN_VERSION` in `ci/Dockerfile`.
2. Bump the matching defaults in `ci/stage-packer-artifacts.sh`.
3. If the plugin changed, bump `required_plugins.amazon.version` in
   `variables.pkr.hcl` to the **exact** same version.
4. Re-run step 2 (stage new artifacts) and step 3 (rebuild + push image).

> The plugin version in `variables.pkr.hcl` and in the Dockerfile **must match
> exactly** — `required_plugins { version = "1.2.8" }` is an exact constraint.

### ECS agent / Docker / base image

Edit `release-al2023.auto.pkrvars.hcl`. To pin the base image for fully
reproducible builds, replace the wildcard with the exact dated name:

```hcl
source_ami_al2023 = "al2023-ami-minimal-2023.8.20260901.0-kernel-6.18-x86_64"
```

Find current names with:

```bash
aws ssm get-parameters-by-path \
  --path /aws/service/ami-amazon-linux-latest --region us-east-1 \
  --query "Parameters[?contains(Name,'al2023-ami-minimal-kernel-6.18-x86_64')].Value"
```

### Re-sync from upstream `aws/amazon-ecs-ami`

When AWS cuts a new release, diff their `al2023.pkr.hcl`, `variables.pkr.hcl`,
`release-al2023.auto.pkrvars.hcl`, and the `scripts/`/`files/` this repo vendors,
and port the relevant changes. This repo intentionally dropped arm64 / GPU /
Neuron sources and provisioners.

---

## Appendix A. AWS IAM permissions for the build

The build identity (static keys or assumed role) needs, in the target account,
the standard Packer `amazon-ebs` set — at minimum:

- `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:StopInstances`,
  `ec2:Describe*`
- `ec2:CreateImage`, `ec2:RegisterImage`, `ec2:DeregisterImage`
- `ec2:CreateSnapshot`, `ec2:DeleteSnapshot`
- `ec2:CreateTags`
- `ec2:CreateKeyPair`, `ec2:DeleteKeyPair`
- `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`,
  `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress`
- if `SSH_INTERFACE=session_manager`: `iam:PassRole` for the instance profile
- if sharing the AMI: `ec2:ModifyImageAttribute`

HashiCorp publishes a reference policy:
<https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#iam-task-or-instance-role>

---

## Appendix B. GitLab OIDC to AWS

1. In AWS IAM, add GitLab as an OIDC identity provider
   (`https://gitlab.com` or your self-managed URL).
2. Create a role trusting that provider with a condition on
   `aud` and `sub` (e.g. `project_path:<group>/<project>:ref_type:branch:ref:main`).
3. Attach the policy from Appendix A.
4. In `.gitlab-ci.yml`:
   ```yaml
   build-ami:
     id_tokens:
       GITLAB_OIDC_TOKEN:
         aud: https://gitlab.com
   ```
   and uncomment the `assume-role-with-web-identity` block in `before_script`.
5. Set `AWS_ROLE_ARN` as a (non-masked) CI/CD variable; delete the static
   `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` variables.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `packer: not found` in CI | `CI_IMAGE` wrong or image not pushed (step 3c). |
| `required_plugins ... not installed, run: packer init` | Plugin not in the image. Re-check step 3 build log for the `packer plugins install` line; confirm `PACKER_PLUGIN_PATH` matches between Dockerfile and `.gitlab-ci.yml`. |
| `no valid versions installed` for the plugin | Plugin binary placed without its `_SHA256SUM` sidecar. Use `packer plugins install --path` (the Dockerfile does), don't just `cp` the binary. |
| S3 `AccessDenied` in `docker build` | Image builder role lacks `s3:GetObject` on the artifact prefix (step 3a). |
| `InvalidAMIID.NotFound` / no source AMI | kernel-6.18 minimal AMI not yet in that region, or the wildcard matched nothing. Check with the `aws ssm get-parameters-by-path` command in step 6. |
| Build hangs at `Waiting for SSH` | `SSH_INTERFACE=public_ip` but subnet has no public IP / IGW. Use a public subnet or switch to `session_manager`. |
| `UnauthorizedOperation` mid-build | Build identity missing an EC2 permission — see Appendix A. |
