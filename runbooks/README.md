# Runbooks

Operational procedures for the Konstellation validator fleet (`ENGINEERING.md
§6.4`). Written before testnet-1 exists, so every runbook carries a
**Rehearsed** line at the top — a runbook that has never been run against a
live fleet is a hypothesis. The first halt drill (`ENGINEERING.md §13` item
4, §15 phase 5) is where these get corrected; edit them in the same PR as the
drill write-up.

| Runbook | When |
|---|---|
| [`on-call.md`](on-call.md) | read first: who is paged, how, what to do in the first 15 minutes |
| [`emergency-halt.md`](emergency-halt.md) | a security advisory, an exploit in progress, `NoNewBlocks` |
| [`coordinated-upgrade.md`](coordinated-upgrade.md) | a planned binary upgrade, testnet (`ansible`) or mainnet (governance) |
| [`validator-key-rotation.md`](validator-key-rotation.md) | moving, re-sharding or replacing a validator's signing key without double-signing |
| [`validator-admission.md`](validator-admission.md) | admitting an operator beyond the 4 genesis validators (D16: `x/circuit` reset → `MsgCreateValidator` → disable), and going permissionless |
| [`incident-comms.md`](incident-comms.md) | who says what, where, and when, during any of the above |

Conventions:

- Heights are authoritative, times are estimates (`networks/templates/upgrade.md`).
- Every command is run from an operator machine through the bastion
  (`ssh -F ansible/inventories/<net>/ssh_config <host>`), never from a host
  on the fleet to another host.
- `<net>` is `devnet-1`, `testnet-1` or `konstellation-1`; what differs
  between them is `ENGINEERING.md §18` and §9.4 — testnet is direct
  `ansible-playbook`, mainnet is a governance proposal plus the operator
  channel. devnet-1 (one validator, dapp developers, D18) runs mainnet's
  binary version, so it upgrades when mainnet does, with testnet's
  mechanics (the foundation holds 100 % of its voting power); it has no
  Horcrux, so `validator-key-rotation.md`'s ceremony paths do not apply
  there — see `infra/README.md` "devnet-1" for its key handling.
