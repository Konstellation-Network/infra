# Coordinated upgrade

**Rehearsed:** never — `ENGINEERING.md §15` phase 5 requires one
state-breaking upgrade drill on testnet-1 before mainnet. The first drill
rewrites this file.

The mechanics (`ENGINEERING.md §9.4`): signed release → upgrade file in
`networks` → the halt height reaches every node → cosmovisor swaps the
binary at that height → the network resumes on the new one. What differs
between the networks is *how the height reaches the nodes*:

| | testnet-1 | konstellation-1 |
|---|---|---|
| Height is set by | `ansible-playbook` (binary staged, and — because there is no proposal — `halt-height`, or a gov proposal if the drill is rehearsing mainnet) | `MsgSoftwareUpgrade` via governance (`x/upgrade`); cosmovisor reads the plan from the chain |
| Operators | us | 7+ independent operators; the operator channel (`incident-comms.md`) |
| Notice | hours (`§18`: 2 h voting period) | days (3 d voting period, D11) |

**Cosmovisor auto-download is OFF everywhere** (`§9.2`); every binary is
staged by hand after checksum verification. `DAEMON_ALLOW_DOWNLOAD_BINARIES=false`
in `ansible/roles/cosmovisor/templates/cosmovisor.service.j2` is not a
setting to relax during an upgrade.

## 0. Prerequisites

- A signed tag built by `release.yml`, two independent builds agreeing,
  `SHA256SUMS` published, `gh attestation verify` clean
  (`konstellation/RELEASING.md`).
- The version, date and sha256 in `networks/RELEASES.md`.
- For a state-breaking release: `konstellation/app/upgrades/<name>/` exists
  with the handler and store upgrades; the plan **name** in the handler is
  the name in the proposal, the upgrade file and the cosmovisor directory —
  one string, four places, check all four.
- `networks/<net>/upgrades/v<N>-<name>.md` written from
  `networks/templates/upgrade.md` with all six sections
  (`networks/scripts/verify.sh` checks). Its rollback section is written
  *before* the upgrade, not after.

## 1. Choose the height

- ≥ 4 h of notice on testnet, ≥ 48 h on mainnet after the proposal passes
  (so every operator's on-call sees it during a working day).
- Not at a weekend or holiday boundary; not within 24 h of another
  scheduled change.
- Compute from the observed block time (`networks/<net>/chain.json`) and
  state the expected UTC time in the upgrade file, with the height marked
  authoritative.

## 2. Announce (comms step 1 in `incident-comms.md`)

Upgrade name, height, expected time, binary URL + sha256, whether it is
state-breaking, and the rollback plan. Link the upgrade file. On mainnet,
the proposal id.

## 3. Stage the binary — every chain node, both clouds

Testnet (`ENGINEERING.md §16`):

```sh
cd ~/Desktop/Konstellation-Network/infra/ansible
ansible-playbook -i inventories/testnet-1/hosts.yml upgrade.yml \
  -e upgrade_name=<name> \
  -e binary_url=https://github.com/Konstellation-Network/konstellation/releases/download/v<X.Y.Z>/konstellationd-v<X.Y.Z>-linux-amd64 \
  -e binary_sha256=<sha256 from networks/<net>/upgrades/v<N>-<name>.md>
```

`upgrade.yml` targets `chain_nodes` (validators, sentries, rpc, archive —
not bastions, monitoring or cosigners), verifies the checksum on every host,
and touches nothing else: not `current`, not the running process.

Mainnet: each operator runs the "Staging steps" block from the upgrade
file. Ask every operator to confirm in the channel with the output of
`$DAEMON_HOME/cosmovisor/upgrades/<name>/bin/konstellationd version`.

Verify fleet-wide before the height:

```sh
ansible -i inventories/<net>/hosts.yml chain_nodes -b -m shell \
  -a "sha256sum /home/konstellation/.konstellationd/cosmovisor/upgrades/<name>/bin/konstellationd"
```

Every line must show the same sha256 as the upgrade file. One that differs
is a stop-the-upgrade finding.

## 4. Set the height

Mainnet — governance:

```sh
konstellationd tx upgrade software-upgrade <name> \
  --upgrade-height <H> \
  --upgrade-info '{"binaries":{}}' \
  --title "<name>" --summary "<link to the upgrade file>" \
  --deposit 1000000000000000000000esp \
  --from <proposer> --node <rpc>
konstellationd query gov proposals --node <rpc>
```

Vote; watch quorum (33.4 %, D11). When it passes, `konstellationd query
upgrade plan` shows the plan on every node. Cosmovisor watches for it and
needs nothing else. **A proposal that fails or is cancelled
(`cancel-software-upgrade` via governance) leaves the staged binary
harmless in its directory.**

Testnet without a proposal (a pure ansible drill): the height is a
`halt-height` on every node, and the swap is manual at that height (see
`emergency-halt.md` tool 2 and step A8). Prefer rehearsing the governance
path at least once on testnet — it is the one mainnet uses.

## 5. Before the height

- Snapshot on state-breaking upgrades: `konstellationd snapshots export`
  on one archive node at H−1 (or a filesystem snapshot of `data/` with the
  node stopped). The rollback section of the upgrade file says whether this
  is required; for state-breaking it is.
- The on-call for the window is named in the channel, with a second
  engineer. Both have the bastion reachable and the runbook open.
- Confirm `DiskHeadroomLow` is not firing anywhere — a migration needs
  headroom.

## 6. At the height

Cosmovisor logs `UPGRADE "<name>" NEEDED at height <H>` then restarts on the
new binary (`DAEMON_RESTART_AFTER_UPGRADE=true`). Watch:

```sh
ansible -i inventories/<net>/hosts.yml validators -b -m shell \
  -a "journalctl -u cosmovisor -n 50 --no-pager | grep -iE 'upgrade|applying|started|panic'"
```

Blocks resume once ⅔+ voting power is on the new binary. Then:

- `konstellationd query upgrade applied <name>` returns H.
- `app_hash` at H+1 is identical on every validator (`emergency-halt.md` A9).
- The explorer and the RPC node are on the new binary (`konstellationd
  version` via the RPC's `/abci_info`).
- `NoNewBlocks` clears; `BlockTimeDrift` should settle within 10 minutes.

## 7. If it goes wrong

| Symptom | Do |
|---|---|
| A node panics in the upgrade handler | it is the migration. If it is one node: check its binary sha256; if it is every node: **rollback** (below). Do not "fix forward" live. |
| Chain halts at H, only some validators come back | the others have the wrong binary or no binary staged; they stay stopped until fixed, chain resumes at ⅔+ |
| Blocks resume, `app_hash` differs across validators | a non-deterministic migration; halt immediately (`emergency-halt.md` tool 2 at current+5) and rollback |

**Rollback** (the plan the upgrade file promised): every validator stops;
restore `data/` from the pre-height snapshot on every node (state-breaking) or
`konstellationd rollback` once (non-state-breaking, one block); repoint
`cosmovisor/current` at the previous version's directory; **do not touch
`priv_validator_state.json`** (`§2.7`; with horcrux, the cosigners' state
files); restart sentries then validators. Then a `cancel-software-upgrade`
proposal on mainnet, so the plan does not re-fire.

## 8. After

- `docs/docs/upgrades.md` gets the historical entry.
- The drill write-up (testnet) or the incident write-up (if anything went
  wrong) goes in this directory and fixes this file.
