#cloud-config
users:
  - name: deploy
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - ${ssh_public_key}

ssh_pwauth: false
disable_root: true

package_update: true
packages:
  - fail2ban
  - unattended-upgrades

# Everything past this point (binary install, config.toml/app.toml, cosmovisor,
# horcrux, firewall rules) is owned by Ansible, not cloud-init. This block only
# gets a host to the point where Ansible can reach it over SSH as `deploy`.
