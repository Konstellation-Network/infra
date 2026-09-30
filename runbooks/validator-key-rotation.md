# Validator key rotation, failover and re-sharding

**Rehearsed:** never. Rehearse on testnet-1 before any mainnet validator
exists — `ENGINEERING.md §18` makes dedicated Horcrux cosigners mandatory
for mainnet, and the ceremony below is how a validator gets there.

The rule above every step here is `ENGINEERING.md §2.7`: **never run two
nodes with the same `priv_validator_key.json`** (or two cosigner clusters
holding the same key). Double-signing is unrecoverable: 5 % slash (D10),
permanent tombstone. Nothing in this runbook is worth a double-sign; when in
doubt, stay stopped and lose blocks (downtime slash is 0.01 %).

## What "the key" is

| Key | Where | Rotatable? |
|---|---|---|
| **Consensus key** (ed25519) | `priv_validator_key.json` on the validator host — or, with horcrux, split into 3 shards (`<chain-id>_shard.json`) on the cosigners; the whole key never exists on any host after the ceremony | **No, not in place.** Cosmos SDK v0.54 (`x/staking`) has no consensus-key rotation message. Rotating means a *new validator* (step D). |
| **Operator key** (`konsvaloper…`) | the operator's wallet, never on a host | it is the account that signs `MsgCreateValidator`/`MsgEditValidator`; move it like any wallet key |
| **Node key** (`node_key.json`) | every node; the p2p identity | freely — but sentries' `private_peer_ids` and validators' `persistent_peers` name it (`ansible/roles/node`), so regenerate those |
| **Horcrux ECIES keys** (`ecies_keys.json`) | each cosigner; encrypts cosigner↔cosigner traffic | regenerate with `horcrux create-ecies-shards`, distribute like a shard |
| **Signing state** (`priv_validator_state.json`, or each cosigner's `<chain-id>_priv_validator_state.json`) | next to the key | **never edited, never copied to a second live signer**. It is the double-sign guard: the last height/round/step signed. |

## A. Key ceremony: from a local key to Horcrux

Applies to both modes (`ansible/roles/horcrux` `horcrux_mode`): colocated
(cosigners on the validator hosts — testnet-1 default) and dedicated
(separate cosigner hosts, `terraform/envs/<net>` `horcrux_mode = "dedicated"`).
Ansible has installed the binary, the per-instance homes and the
`horcrux@<instance>.service` units, disabled. It will not generate, move or
enable anything key-shaped — that is this section, done by a human.

1. **Stop signing.** `systemctl stop cosmovisor` on the validator. Confirm
   in `journalctl` that the last line is a clean shutdown and note the last
   signed height from `priv_validator_state.json` (read, do not edit).
2. **Generate shards offline**, on an air-gapped or at least
   single-purpose machine, from the validator's `priv_validator_key.json`:
   ```sh
   horcrux create-ed25519-shards --chain-id <net> --key-file priv_validator_key.json --threshold 2 --shards 3
   horcrux create-ecies-shards --shards 3
   ```
   Output: `cosigner_1/ … cosigner_3/`, each with `<net>_shard.json` and
   `ecies_keys.json`. Verify the count and that each shard's `id` matches
   its directory.
3. **Place each shard on its cosigner**, over the bastion, one at a time:
   ```sh
   # The ceremony machine must already trust the host keys: ssh_config's
   # accept-new is fine for ansible, not for moving shards — pre-seed
   # known_hosts from the bastion (or the provider console) and force
   # StrictHostKeyChecking=yes for these commands. Never through /tmp
   # (world-readable): a 0700 staging dir in deploy's home.
   ssh -F ansible/inventories/<net>/ssh_config -o StrictHostKeyChecking=yes <cosigner-host-1> 'mkdir -m 0700 -p ~/ceremony'
   scp -F ansible/inventories/<net>/ssh_config -o StrictHostKeyChecking=yes cosigner_1/* <cosigner-host-1>:~/ceremony/
   ssh -F ansible/inventories/<net>/ssh_config -o StrictHostKeyChecking=yes <cosigner-host-1> \
     'sudo install -o konstellation -g konstellation -m 0600 ~/ceremony/<net>_shard.json ~/ceremony/ecies_keys.json \
        /home/konstellation/.horcrux/<instance>/ && shred -u ~/ceremony/* && rmdir ~/ceremony'
   ```
   `<instance>` is the validator's inventory hostname in dedicated mode,
   `<net>` in colocated mode (`ansible/roles/horcrux/tasks/main.yml`).
   The `shard_id` in the inventory for that host must match the shard
   number placed there — this is what the templated `config.yaml`'s
   `cosigners` list assumes.
4. **Seed the signing state** so the cluster cannot sign below the height
   the validator last signed. Horcrux v3 has `state import <chain-id>`
   (reads a `priv_validator_state.json` on stdin — height, round *and*
   step) and `state set <chain-id> <height>` (height only: round and step
   become 0, which would let the cluster sign a *later round* of the last
   height the validator already voted in). So either `import` the exact
   file from step 1 on each cosigner, or `state set <net> <H+1>` where H is
   the height from step 1 — one above, never equal. Check `horcrux state
   --help` for the pinned version. **A wrong height here is the one way
   this ceremony can double-sign.**
5. **Remove the whole key from the validator host.** `shred -u
   priv_validator_key.json` (keep a copy *only* in the cold backup that the
   shards were made from, offline). A host that still holds the full key
   next to a live cosigner cluster is two signers.
6. **Point the node at the signer.** In the inventory, set
   `horcrux_enabled: true` for that validator (host_vars) and run
   `ansible-playbook site.yml --limit <validator>`: `ansible/roles/node`
   writes `priv_validator_laddr` (loopback in colocated mode, the host's
   private IP in dedicated mode; the firewalls admit only the cosigners on
   1234).
7. **Start the cosigners** (`systemctl enable --now horcrux@<instance>` on
   each), then the validator. Watch for the raft leader election in
   horcrux's log and "signed" lines in the node's. First signed height must
   be > the height from step 1.
8. **Shred the ceremony machine's copies** of the shards. Record the
   ceremony (who, when, which hosts hold which shard, last height) in the
   private ops notes — not in this repo.

## B. Failover: the validator host is gone

Symptom: tenderduty pages missed blocks; the host is unreachable.

- **With horcrux (dedicated):** the key is not on the host. Bring up a
  replacement validator host (`terraform apply` after removing the dead
  one from state, `ansible-playbook site.yml --limit <new host>`), point
  the cosigners' `chainNodes.privValAddr` at it (re-run the horcrux role —
  the inventory IP changed), start it. The cosigners' signing state
  prevents regression. This is the whole reason for §9.2's requirement.
- **With a local key or colocated horcrux:** the key and its state file are
  on the dead host. **Do not restore the key to a new host until you have
  proven the old host is not running** — a host that is "unreachable"
  through the bastion may still be up and signing. Proof means the cloud
  console shows it stopped/deleted, or the provider confirms the
  hardware is dead; not a failed ping. Then: restore the key from cold
  backup, and set `priv_validator_state.json` on the new host to a height
  **higher** than anything the old host could have signed (the current
  chain height + a margin is safe: the node will simply wait). Losing a few
  blocks is the cost of certainty.
- **devnet-1 (one validator, local key — D18, 2026-09-29):** the "+ a
  margin, the node will simply wait" step above **deadlocks** a
  one-validator chain: no one else advances the height. Move the key *and*
  its state file together from the old disk (after the same proof the old
  server is deleted). If the state file died with the host there is no
  rehearsed answer yet — stop and escalate (re-genesis vs. a deliberate
  one-off; `infra/README.md` "devnet-1"), do not improvise. devnet-1 runs
  on Contabo (2026-09-30): "proof" is the Contabo panel showing the old
  VPS cancelled or reinstalled, not a failed SSH through server 2. Its
  validator keeps key, state and data on one disk, so `site.yml` stops
  (`roles/node/tasks/state_guard.yml`) whenever the key is present and
  `priv_validator_state.json` is not — the moment to read this paragraph,
  not to write a height-0 state file. Never restore a Contabo snapshot of
  the validator over a running chain: it rolls the state file back.

GCP validators on Local SSD (`terraform/modules/gcp/validator`,
`infra/README.md`) lose their disk — key *and* state — on a host
maintenance event. That is why this failover path exists and why dedicated
cosigners are mandatory before mainnet.

## C. Re-sharding (a cosigner host is compromised or lost)

One shard alone signs nothing (2-of-3), but a lost shard means the cluster
has no redundancy, and a leaked shard plus one more is the key.

1. Stop the affected cosigner instance(s). The cluster keeps signing on the
   remaining two — this is what the threshold buys you.
2. Provision the replacement cosigner host; give it the **same `shard_id`**
   in the inventory (`cosigner_placement` order in terraform).
3. Re-run the ceremony (section A steps 2–4) from the cold backup, producing
   a **fresh** set of three shards (a new split of the same key). All three
   cosigners get new shards — the old split's remaining shards are now
   invalid alongside the leaked one. Do this as a stop-the-cluster window:
   stop all three, seed state from the last signed height, place, start.
4. If the shard was *leaked* rather than lost and you cannot be sure the
   other two were not: the key is compromised. Go to D.

## D. Rotation: replacing the consensus key

There is no in-place rotation in Cosmos SDK v0.54. A validator with a
compromised or lost consensus key is retired and a new one created:

1. Generate a new consensus key (a fresh `konstellationd init` in a
   throwaway home gives one), and go straight to the ceremony (A) so the
   whole key never lives on a networked host.
2. `konstellationd tx staking create-validator` with the new pubkey from
   the same operator wallet (or a new one), and the sentry/validator pair
   for it.
3. Delegators (on testnet-1: the team) redelegate from the old validator to
   the new one; the old one is unbonded (`MsgUndelegate` of the
   self-delegation, or simply left to be jailed for downtime — but a jailed
   validator is still a validator with a possibly-leaked key, so **stop the
   old signer first**; a leaked key on a validator with zero voting power
   cannot double-sign anything that matters, but do not rely on that).
4. Update tenderduty's `tenderduty_validators` valoper for the new one.
5. On mainnet, the operator channel is told (`incident-comms.md`): a
   validator disappearing from the set looks like an incident to everyone
   else.

## E. Node key and peer wiring

`node_key.json` is regenerated by deleting it and restarting; the node id
changes. Then update `validator_node_id` (sentries' `private_peer_ids`) and
`persistent_peers` in the inventory and re-run `ansible/roles/node` on the
affected pair, and `networks/<net>/persistent_peers.txt` / `seeds.txt` if a
public node changed.
