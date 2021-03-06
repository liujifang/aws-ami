# ---------------------------------------------------------------------------------------------------------------------
# Added HCL format support
# ---------------------------------------------------------------------------------------------------------------------

variable "region" {
  description = "The type of EC2 Instances to run for each node in the Regional area id."
  default     = "cn-northwest-1"
}
variable "regions_to_copy" {
  type    = list(string)
  default = ["cn-north-1"]
}
variable "subnet_id" {
  type    = string
  default = null
}
variable "source_ami" {
  type    = string
  default = "ami-fce3c696"
}
variable "source_ami_owner" {
  type    = list(string)
  default = ["837727238323"]
}
variable "os_arch" {
  type    = string
  default = "amd64"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "iam_instance_profile" {
  type    = string
  default = "packer-ec2"
}
variable "timezone" {
  type    = string
  default = "Asia/Shanghai"
}
variable "java_version" {
  type    = string
  default = "11.0.7.10-1"
}
variable "node_exporter_version" {
  type    = string
  default = "1.0.1"
}
variable "docker_version" {
  type    = string
  default = "19.03.12"
}
variable "consul_version" {
  type    = string
  default = "1.8.0"
}
variable "nomad_version" {
  type    = string
  default = "0.12.0"
}

source "amazon-ebs" "ubuntu" {
  region      = var.region
  ami_regions = var.regions_to_copy
  source_ami  = var.source_ami
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-${var.os_arch}-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = var.source_ami_owner
    most_recent = true
  }
  ami_name                    = "ubuntu/18.04/${var.os_arch}/{{isotime \"20060102T150405Z\"}}"
  ami_description             = "Linux golden image based on Ubuntu 18.04"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${var.iam_instance_profile}"
  communicator                = "ssh"
  pause_before_connecting     = "30s"
  ssh_username                = "ubuntu"
  ssh_clear_authorized_keys   = true
  associate_public_ip_address = true
  subnet_id                   = "${var.subnet_id}"
  tags = {
    Name                  = "ubuntu/18.04/${var.os_arch}/{{isotime \"20060102T150405Z\"}}"
    build_region          = "{{ .BuildRegion }}"
    source_ami            = "{{ .SourceAMI }}"
    source_ami_name       = "{{ .SourceAMIName }}"
    os_name               = "Ubuntu"
    os_version            = "18.04"
    os_arch               = "${var.os_arch}"
    timezone              = "${var.timezone}"
    java_distro           = "Amazon Corretto"
    java_version          = "${var.java_version}"
    node_exporter_version = "${var.node_exporter_version}"
    docker_version        = "${var.docker_version}"
    consul_version        = "${var.consul_version}"
    nomad_version         = "${var.nomad_version}"
  }
}

build {
  sources = ["sources.amazon-ebs.ubuntu"]

  provisioner "file" {
    source      = "provisioners/shell/bash-helpers.sh"
    destination = "/tmp/"
  }

  provisioner "shell" {
    environment_vars = [
      "BASH_HELPERS         = /tmp/bash-helpers.sh",
      "TIMEZONE             = ${var.timezone}",
      "JAVA_VERSION         = ${var.java_version}",
      "NODE_EXPORTER_VERSION = ${var.node_exporter_version}"
    ]
    scripts = [
      "provisioners/shell/apt-mirrors.sh",
      "provisioners/shell/apt-upgrade.sh",
      "provisioners/shell/apt-daily-conf.sh",
      "provisioners/shell/packages.sh",
      "provisioners/shell/journald-conf.sh",
      "provisioners/shell/core-pattern.sh",
      "provisioners/shell/kernel-tuning.sh",
      "provisioners/shell/chrony.sh",
      "provisioners/shell/timezone.sh",
      "provisioners/shell/awscliv2.sh",
      "provisioners/shell/java-amazon-corretto.sh",
      "provisioners/shell/prometheus/node-exporter.sh"
    ]
  }

  provisioner "file" {
    source      = "provisioners/shell/cloud-init/mount-nvme-instance-store"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/",
      "sudo install -v mount-nvme-instance-store /var/lib/cloud/scripts/per-instance/"
    ]
  }

  provisioner "file" {
    source      = "provisioners/shell/ebs"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/ebs",
      "sudo install -v ebs-nvme-id /usr/local/bin/",
      "sudo install -v -m 644 99-ebs-nvme.rules /etc/udev/rules.d/",
      "sudo install -v ebs-init /usr/local/bin/"
    ]
  }

  provisioner "file" {
    source      = "provisioners/shell/docker"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/docker",
      "chmod +x install-docker",
      "./install-docker --version ${var.docker_version}"
    ]
  }

  provisioner "file" {
    source      = "provisioners/shell/consul"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/consul",
      "chmod +x install-consul",
      "./install-consul --version ${var.consul_version}"
    ]
  }

  provisioner "file" {
    source      = "provisioners/shell/nomad"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/nomad",
      "chmod +x install-nomad",
      "./install-nomad --version ${var.nomad_version}"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo 'Validating provisioners...'",
      "aws --version", "java -version",
      "prometheus-node-exporter --version",
      "docker --version",
      "consul --version",
      "nomad --version"
    ]
  }

  post-processor "manifest" {
  }
}
