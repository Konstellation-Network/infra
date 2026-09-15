#!/bin/bash
set -euo pipefail

# GCP's guest agent reads the `ssh-keys` instance metadata and creates the
# user + authorized_keys automatically — no cloud-init/user-creation step
# needed here, unlike terraform/modules/hetzner's cloud-init.yaml.tpl.
# Everything past this point (binary install, config.toml/app.toml,
# cosmovisor, horcrux, firewall rules) is owned by Ansible, not this script.

apt-get update
apt-get install -y fail2ban unattended-upgrades
