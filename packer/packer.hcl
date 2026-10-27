packer {
  required_version = ">= 1.9.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "os_flavor" {
  type    = string
  default = "ubuntu-jammy-22.04"
}

data "amazon-ami" "base_linux" {
  filters = {
    virtualization-type = "hvm"
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    root-device-type    = "ebs"
  }
  owners      = ["099720109477"] # Canonical
  most_recent = true
  region      = var.aws_region
}

source "amazon-ebs" "patched_image" {
  ami_name      = "enterprise-hardened-${var.os_flavor}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  instance_type = "t3.medium"
  region        = var.aws_region
  source_ami    = data.amazon-ami.base_linux.id
  ssh_username  = "ubuntu"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name          = "Enterprise-Patched-Base"
    OS            = var.os_flavor
    PatchBaseline = "CIS-Benchmark-Level-1"
    ManagedBy     = "Packer"
    Timestamp     = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())
  }
}

build {
  sources = ["source.amazon-ebs.patched_image"]

  provisioner "ansible" {
    playbook_file = "./patching.yml"
    user          = "ubuntu"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
}
