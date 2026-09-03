packer {
  required_plugins {
    amazon = {
      version = "1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  packages_al2023 = "amazon-efs-utils amazon-ssm-agent amazon-ec2-net-utils acpid iproute-tc ec2-instance-connect"
}

variable "region" {
  type        = string
  description = "Region to build the AMI in."
}

variable "ami_name_prefix_al2023" {
  type        = string
  description = "Outputted AMI name prefix."
  default     = "unofficial-amzn2023-ami-ecs"
}

variable "ami_version_al2023" {
  type        = string
  description = "Outputted AMI version."
}

variable "kernel_version_al2023" {
  type        = string
  description = "Amazon Linux 2023 kernel version suffix used in the output AMI name."
}

variable "source_ami_al2023" {
  type        = string
  description = "Amazon Linux 2023 source AMI name filter to build from."
}

variable "source_ami_owners" {
  type        = list(string)
  description = "Accounts to search when filtering source AMIs."
  default     = ["amazon"]
}

variable "block_device_size_gb" {
  type        = number
  description = "Size of the root block device."
  default     = 30
}

variable "general_purpose_instance_type" {
  type        = string
  description = "Instance type used to build the AMI."
  default     = "c5.large"
}

variable "ecs_agent_version" {
  type        = string
  description = "ECS agent version to build AMI with."
  default     = "1.106.2"
}

variable "ecs_init_rev" {
  type        = string
  description = "ecs-init package version rev"
  default     = "1"
}

variable "docker_version_al2023" {
  type        = string
  description = "Docker version to build AL2023 AMI with."
  default     = "25.0.16"
}

variable "containerd_version_al2023" {
  type        = string
  description = "Containerd version to build AL2023 AMI with."
  default     = "2.2.5"
}

variable "runc_version_al2023" {
  type        = string
  description = "Runc version to build AL2023 AMI with."
  default     = "1.3.5"
}

variable "exec_ssm_version" {
  type        = string
  description = "SSM binary version to build ECS exec support with."
  default     = "3.3.4624.0"
}

variable "ecs_init_url_al2023" {
  type        = string
  description = "Specify a particular ECS init URL for AL2023 to install. If empty it will use the standard path."
  default     = ""
}

variable "ecs_init_local_override" {
  type        = string
  description = "Specify a local init rpm under additional-packages/ to be used. If empty it will use the standard path."
  default     = ""
}

variable "air_gapped" {
  type        = string
  description = "If this build is for an air-gapped region, set to 'true'"
  default     = ""
}

variable "region_dns_suffix" {
  type        = string
  description = "DNS suffix to use for in-region URLs"
  default     = ""
}

variable "custom_endpoint_ec2" {
  type        = string
  description = "Custom EC2 endpoint to use for building AMIs"
  default     = ""
}

variable "ssh_interface" {
  type        = string
  description = "SSH interface for the build instance (public_ip, private_ip, session_manager)."
  default     = "public_ip"
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile to attach to the build instance. Required when ssh_interface is 'session_manager'."
  default     = ""
}

variable "subnet_id" {
  type        = string
  description = "VPC subnet ID for the build instance."
  default     = ""
}

variable "ami_ou_arns" {
  type        = list(string)
  description = "AWS Organizations OU ARNs that may launch the resulting AMI."
  default     = []
}

variable "ami_org_arns" {
  type        = list(string)
  description = "AWS Organizations ARNs that may launch the resulting AMI."
  default     = []
}

variable "ami_users" {
  type        = list(string)
  description = "Account IDs that may launch the resulting AMI."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the built AMI."
  default     = {}
}

variable "run_tags" {
  type        = map(string)
  description = "Tags to apply to resources used while building the AMI."
  default     = {}
}
