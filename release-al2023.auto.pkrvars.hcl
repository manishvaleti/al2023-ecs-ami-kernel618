# Pinned build inputs for the AL2023 x86_64 ECS-optimized AMI (kernel 6.18).
# Mirrors the upstream aws/amazon-ecs-ami release vars, trimmed to x86_64 only.
ami_version_al2023        = "20260901"
ecs_agent_version         = "1.106.2"
ecs_init_rev              = "1"
docker_version_al2023     = "25.0.16"
containerd_version_al2023 = "2.2.5"
runc_version_al2023       = "1.3.5"
exec_ssm_version          = "3.3.4624.0"

# Base image: AWS-owned AL2023 minimal AMI, kernel 6.18, x86_64.
# most_recent=true in the source_ami_filter picks the newest match.
# Pin the full dated name (e.g. al2023-ami-minimal-2023.8.20260901.0-kernel-6.18-x86_64)
# for fully reproducible builds.
source_ami_al2023     = "al2023-ami-minimal-2023.*-kernel-6.18-x86_64"
kernel_version_al2023 = "-kernel-6.18"
