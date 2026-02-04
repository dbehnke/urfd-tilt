packer {
  required_plugins {
    parallels = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/parallels"
    }
  }
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type    = string
  default = ""
}

variable "vm_name" {
  type    = string
  default = "urfd-test"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type    = string
  default = "packer"
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cpus" {
  type    = number
  default = 2
}

variable "disk_size" {
  type    = number
  default = 20000
}

variable "user_data_path" {
  type    = string
  default = "packer/cloud-init/user-data"
}

source "parallels-iso" "debian" {
  # Use a Debian cloud image (arm64 or amd64) for reliable unattended provisioning.
  # Set `iso_url` to the cloud image URL you want to use (e.g. Debian cloud qcow2/iso).
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name       = var.vm_name
  guest_os_type = "Debian"

  ram       = var.memory
  cpus      = var.cpus
  disk_size = var.disk_size

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "20m"

  # Use floppy_files to attach cloud-init user-data/meta-data. Packer will add them
  # to a virtual floppy (cidata) so cloud-init can consume them on first boot.
  # Allow overriding the user-data path per-run (so CI can generate ephemeral
  # user-data containing a one-time ssh key). Default points to packer/cloud-init/user-data
  floppy_files = [var.user_data_path, "packer/cloud-init/meta-data"]

  boot_wait    = "10s"
  # The default boot_command is kept minimal because cloud images usually auto-login
  # and enable SSH via cloud-init. If you use a netinst ISO instead, you'll need to
  # provide a full preseed boot_command here.
  boot_command = ["<enter><wait>"]
}

build {
  sources = ["source.parallels-iso.debian"]

  provisioner "file" {
    source      = "../dist"
    destination = "/tmp/urfd-dist"
  }

  provisioner "shell" {
    script = "provision.sh"
    pause_before = "10s"
    execute_command = "echo '{{ user `ssh_password` }}' | sudo -S -E bash '{{ .Path }}'"
  }
}
