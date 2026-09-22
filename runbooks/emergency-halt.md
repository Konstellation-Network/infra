# Emergency halt

**Rehearsed:** never — this is the runbook `ENGINEERING.md §13` item 4
requires a drill for ("simulated advisory at an awkward hour, halt at a
height, patch, coordinated restart, back in under 90 minutes"). The first
drill rewrites this file.

Two situations bring you here, and they need different first moves:

| | A. Advisory with a patch | B. Exploit in progress / chain halted |
|---|---|---|
| Trigger | `upstream-release` issue for a `cosmos/evm` (or SDK/CometBFT) security tag; `ENGINEERING.md §4.2` | `NoNewBlocks` fired, or the explorer / a user shows funds moving that shouldn't |
| Clock | 24 h from the tag (§4.2) — or less if an exploit is public | now |
| First move | build + verify the patched release, schedule a halt height | **stop value movement**, then halt if needed |
| Tool | `--halt-height` (planned) | `x/circuit` first, `--halt-height` second, `kill` last |

Both are two-person operations: one drives, one reads the runbook aloud and
records times in the incident channel (`incident-comms.md`).

## The tools, and what each one does

**1. Circuit breaker — `x/circuit` (`ENGINEERING.md §13` item 1, D14).**
Disables specific message types *without* stopping the chain. Enforced at
the router, the ante handler, the mempool pre-check and inside cosmos/evm's
tx-path precompiles (`konstellation/app/circuit.go`,
`app/circuit_precompiles.go`), nested `authz` `MsgExec` included. A tripped
type is refused at submission with the reason. Requires the admin key from
`genesis.json` `account_permissions` (`ENGINEERING.md §18`: a dev key on
testnet-1, the 3-of-5 operations multisig on mainnet).

```sh
# what is currently disabled
konstellationd query circuit disabled-list --node <rpc>

# pause the whole EVM
konstellationd tx circuit disable /cosmos.evm.vm.v1.MsgEthereumTx --from <admin> --node <rpc>

# stop all IBC sends, Cosmos AND EVM (the ICS20 precompile is covered, D14)
konstellationd tx circuit disable /ibc.applications.transfer.v1.MsgTransfer --from <admin> --node <rpc>

# several at once
konstellationd tx circuit disable /cosmos.bank.v1beta1.MsgSend,/cosmos.bank.v1beta1.MsgMultiSend --from <admin> --node <rpc>

# undo
konstellationd tx circuit reset /cosmos.evm.vm.v1.MsgEthereumTx --from <admin> --node <rpc>
```

Semantics that matter under pressure:

- The breaker **cannot** disable its own messages or governance's — a trip
  naming them is refused, so it is always resettable and governance can
  always replace the admin. You cannot weld it shut by mistake.
- Disabling `MsgEthereumTx` stops every EVM transaction, including reads
  that go through `eth_sendRawTransaction`; `eth_call` still works.
- It needs blocks to be produced to take effect. If the chain is halted,
  the breaker is for *after* the restart (see step B5).
- On mainnet the admin is a multisig: collecting signatures is the slow
  part. The signing procedure and who holds keys is in `incident-comms.md`
  "Key holders"; rehearse it.

**2. Planned halt — `--halt-height`.** Every node stops gracefully after
committing height H. `app.toml` `halt-height` (or the `start` flag). This is
the mechanism for "everyone stops at the same height", which is what a
state-breaking patch needs: no node commits a block the others haven't.

```sh
# every node, well before H; cosmovisor restarts the process to pick it up
ansible -i ansible/inventories/<net>/hosts.yml chain_nodes -b -m community.general.ini_file \
  -a "path=/home/konstellation/.konstellationd/config/app.toml section= option=halt-height value=<H>"
ansible -i ansible/inventories/<net>/hosts.yml chain_nodes -b -m systemd -a "name=cosmovisor state=restarted"
```

Mainnet: operators set it themselves from the upgrade file / the announcement
(`ENGINEERING.md §9.4`: "`--halt-height` + Signal group"). **Remember to
clear it before the restart** or the node halts again at H immediately.

**3. Unplanned stop.** `systemctl stop cosmovisor` on the validators. Only
when the chain must stop *now* and there is no time to agree a height —
i.e. the exploit is draining funds this minute. It is not clean: validators
stop at different heights, and the restart has to reconcile that (B6).

## A. Advisory with a patch (the 24-hour path)

Times are targets from `ENGINEERING.md §4.2`.

1. **T+0 — triage (any engineer, §17).** Self-assign the issue. Read the
   upstream diff (`§4.2`: treat every patch tag as a security release; diff
   `x/vm/`, `x/vm/statedb/`, `precompiles/`). Decide: is it reachable on
   Konstellation? State-breaking? Record in `ENGINEERING.md §4.1` as the
   issue template asks.
2. **T+1 h — decide the shape.** State-breaking ⇒ coordinated halt at a
   height (this runbook + `coordinated-upgrade.md`). Not state-breaking ⇒
   rolling restart, no halt, still within 24 h.
3. **T+2 h — is anything exploitable *now*?** If the advisory describes an
   open path and the exploit is cheap, trip the breaker on the message type
   that reaches it while the build runs (tool 1). Announce it
   (`incident-comms.md`). A paused EVM for six hours beats a drained one.
4. **T+2 h → T+8 h — build and verify.** Bump the pin in `konstellation`,
   CI green, tag (`konstellation/RELEASING.md`): two independent builds must
   agree, checksums published. `gh attestation verify`. Record in
   `networks/RELEASES.md`. Never build on a validator (§2.6).
5. **T+8 h — write the upgrade file** from `networks/templates/upgrade.md`
   into `networks/<net>/upgrades/`, with the halt height H chosen so that
   every operator has ≥ 4 h notice on mainnet (testnet: whatever the drill
   says). Announce (comms step 2).
6. **T+8 h → H — stage.** Testnet: `ansible-playbook upgrade.yml` (see
   `coordinated-upgrade.md`). Mainnet: operators stage by hand from the
   upgrade file. Then set `halt-height = H` everywhere (tool 2).
7. **At H — halt.** Confirm every validator's last committed height is H:
   ```sh
   ansible -i ansible/inventories/<net>/hosts.yml validators -b -m shell \
     -a "journalctl -u cosmovisor -n 20 --no-pager | grep -i 'halting\|committed'"
   ```
   Mainnet: operators confirm in the channel with their height.
8. **Swap and restart** — for an emergency patch without a governance
   `MsgSoftwareUpgrade`, cosmovisor does not swap for you. Stage the new
   binary as `cosmovisor/upgrades/<name>/bin/konstellationd` with
   `ansible/upgrade.yml` (checksum-verified) and repoint `current` at that
   directory; **never overwrite `cosmovisor/genesis/bin/`** — `roles/node`
   re-downloads the pinned `konstellationd_version`/`_sha256` into it on the
   next `site.yml`, which would silently revert the patch on the next
   restart (review, 2026-09-21). In the **same step**, bump
   `konstellationd_version` and `konstellationd_sha256` in
   `ansible/inventories/<net>/group_vars/all.yml` (and `RELEASES.md`) to
   the patched release, so the fleet's declared state is the patched one.
   Then clear `halt-height`, restart. Watch for `⅔+` voting power to come
   back before expecting blocks.
9. **Verify:** height advancing on every node, `app_hash` identical across
   validators at H+1 (`curl localhost:26657/block?height=<H+1> | jq
   .result.block.header.app_hash`), the exploit path closed (re-run whatever
   the advisory's PoC is against a sentry's RPC). Reset any breaker trip from
   step 3 only after this.
10. **Close:** comms step 4, write-up in this directory, `§4.1` record.

## B. Exploit in progress, or the chain has stopped on its own

1. **Confirm it is real** (five minutes, not thirty): height on every
   sentry, the explorer, a raw `eth_getBalance` on the suspected contract or
   module account. `NoNewBlocks` on one node is a node; on all nodes it is
   the chain.
2. **Stop value movement first, with the narrowest tool that works.** If
   the chain is producing blocks: trip the breaker on the message type
   carrying the exploit (`MsgEthereumTx` if it is an EVM contract you cannot
   identify yet; `MsgTransfer` if value is leaving over IBC — and
   `x/ratelimit` should already be bounding that, §13.2). If you cannot get
   the admin signature within minutes, go to 3.
3. **Halt if the breaker is not enough.** Pick the nearest height every
   validator can hit (current + ~20 blocks) and set `halt-height` (tool 2).
   If value is leaving *this minute*, `systemctl stop cosmovisor` on the
   validators (tool 3) — you need ⅓+ of voting power stopped to stop the
   chain; with 10 equally-staked foundation validators (D7) that is 4 hosts.
4. **Announce** (`incident-comms.md` "chain halted" template) with the
   height. Do not speculate on cause in public yet.
5. **Understand before restarting.** A restart that re-opens the same path
   is the worst outcome. The patch may be a binary (path A from step 4),
   a breaker trip applied at the first block after restart, or — the case
   `ENGINEERING.md §10` rehearses — a compliance freeze on the attacker's
   address (`konstellationd tx compliance emergency-freeze <addr>... --from
   <authority>` — effective immediately for one timelock period, and it also
   clears any EIP-7702 delegation on the address).
6. **Do not "reconcile heights"** after an unplanned stop. Validators
   stopped at different heights are *normal*: a node behind simply catches
   up from its peers on restart, and a node ahead already holds a
   committed block the others will fetch. `konstellationd rollback` is for
   a block that was committed and must be undone (a bad upgrade handler,
   `coordinated-upgrade.md` §7), not for a stop — an unnecessary rollback
   is a way to make a node sign at a height it already signed. **Never edit
   or delete `priv_validator_state.json`** to make a restart go through —
   that is the double-sign path (`§2.7`), and with horcrux the equivalent
   is each cosigner's `state/` directory.
7. **Restart in an order that cannot double-sign:** sentries first, then
   validators one at a time, watching each one's `journalctl` for
   "signed" lines before the next. Height should advance once ⅔+ is back.
8. **Post-incident:** if funds moved, `ENGINEERING.md §10` "reversal
   options" is the menu, and it is a governance/legal question, not an
   on-call one. Write-up within 48 h, in this directory.

## Rehearsal checklist (the §13 drill)

- [ ] Start at an awkward hour, unannounced to the responders.
- [ ] Time every step against the table in `on-call.md`.
- [ ] Use a real patched build (`v<x>-rc1`, `RELEASING.md` pre-release), not a no-op.
- [ ] Exercise both the breaker and `halt-height`, and at least once the unplanned stop + `rollback` path.
- [ ] The §15 chaos test is a separate drill: kill 40 % of validators mid-block — 4 of the 10 (two per cloud, so neither cloud loses all its sentries) — and confirm the chain **halts** (60 % of voting power is below the ⅔ needed), then that restarting the four resumes without a double-sign. The halt is the expected result; the restart is what is being rehearsed.
- [ ] Verify `app_hash` agreement across validators after restart.
- [ ] Confirm the patched version survives a `site.yml` run after the drill (`konstellationd_version`/`_sha256` bumped, `cosmovisor/genesis/bin` untouched).
- [ ] Rehearse `coordinated-upgrade.md` §7's failed-handler rollback (`--unsafe-skip-upgrades`) once, on testnet, before it is ever needed.
- [ ] Write up: what took longest, what this file got wrong, and fix it in the same PR.
