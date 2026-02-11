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

variable "package_source_dir" {
  type    = string
  default = "dist"
}

source "parallels-iso" "debian" {
  # Use Debian netinst ISO with unattended preseed installation.
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name       = var.vm_name
  guest_os_type = "debian"

  memory    = var.memory
  cpus      = var.cpus
  disk_size = var.disk_size

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "45m"

  parallels_tools_mode = "disable"

  http_directory = "packer/http"

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  # Use floppy_files to attach cloud-init user-data/meta-data. Packer will add them
  # to a virtual floppy (cidata) so cloud-init can consume them on first boot.
  # Allow overriding the user-data path per-run (so CI can generate ephemeral
  # user-data containing a one-time ssh key). Default points to packer/cloud-init/user-data
  floppy_files = [var.user_data_path, "packer/cloud-init/meta-data"]

  boot_wait = "10s"
  boot_command = [
    "c<wait>",
    "linux /install.a64/vmlinuz auto=true priority=critical url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg debian-installer=en_US.UTF-8 locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=us netcfg/get_hostname={{ .Name }} netcfg/get_domain=local fb=false ---<enter><wait>",
    "initrd /install.a64/initrd.gz<enter><wait>",
    "boot<enter>"
  ]
}

build {
  sources = ["source.parallels-iso.debian"]

  provisioner "file" {
    source      = var.package_source_dir
    destination = "/tmp/urfd-dist"
  }

  provisioner "shell" {
    script = "packer/provision.sh"
    pause_before = "10s"
    execute_command = "echo '${var.ssh_password}' | sudo -S -E bash '{{ .Path }}'"
  }
}
