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

%{ if default_route_via != "" ~}
# This host has no public IP. A Hetzner server without one has no route to
# the internet at all — apt and the checksummed binary download in
# ansible/roles/node would both fail — so it egresses through the bastion's
# NAT (modules/hetzner/bastion, hcloud_network_route 0.0.0.0/0). The route
# on the hcloud_network only takes effect if the host itself points its
# default route at the network gateway (always the first address of the
# network range). Hetzner's DHCP does not push that route, so this unit
# installs it after the private interface is up, every boot.
write_files:
  - path: /etc/systemd/system/private-default-route.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Default route via the private network gateway (bastion NAT)
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/sbin/ip route replace default via ${default_route_via}
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now private-default-route.service
%{ endif ~}

package_update: true
packages:
  - fail2ban
  - unattended-upgrades

# Everything past this point (binary install, config.toml/app.toml, cosmovisor,
# horcrux, firewall rules) is owned by Ansible, not cloud-init. This block only
# gets a host to the point where Ansible can reach it over SSH as `deploy`.
