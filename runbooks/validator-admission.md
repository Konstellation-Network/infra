# Validator admission (D16)

**Rehearsed:** never — `ENGINEERING.md §15` phase 5 requires at least one
admission through this procedure on testnet-1, and phase 6 admits the first
independent operators with it. The first run rewrites this file.

The genesis set is 10 foundation-run validators (D7), created by gentx.
`genesis.json` ships with `/cosmos.staking.v1beta1.MsgCreateValidator` in
`x/circuit`'s `disabled_type_urls` on both networks, so **nobody can create
a validator** — the message is refused at submission (mempool pre-check),
in the ante handler, at the router, and inside the staking precompile
(`app/circuit_precompiles.go`), nested `authz` included (D14). Admission is
therefore: open the breaker, let the operator's `MsgCreateValidator` in,
close it again. Nothing under `x/` is involved; this is the D14 rail used
as a gate. "Permissioned" means who may *become* a validator — delegation
is open from genesis (D7).

## Roles

| | |
|---|---|
| **Admin** | the `x/circuit` `LEVEL_SUPER_ADMIN` account from `genesis.json` `account_permissions` (`ENGINEERING.md §18`): the 3-of-5 operations multisig on mainnet, a dev key on testnet-1 |
| **Operator** | the party being admitted; holds their own operator key and consensus key (`validator-key-rotation.md` — Horcrux is strongly recommended, not enforced) |
| **Lead** | the on-call engineer running the window (`on-call.md`); posts in the operator channel (`incident-comms.md`) |

## Before

1. **Decision recorded.** Who is admitted, why, and where the foundation
   decided it (a signed note, a governance signal vote, whatever the
   whitepaper roadmap's stage requires). This runbook executes, it does not
   decide.
2. **Operator readiness** (the `docs` repo's `run-a-validator.md` is the
   checklist they follow; this is what the lead checks):
   - A synced full node on the network, behind a sentry, `pex = false`,
     private peer id set on the sentry — i.e. the §9.2 topology, on hosts
     the foundation does not run.
   - Consensus public key: `konstellationd comet show-validator` output
     (or the Horcrux cluster's), sent to the lead over the operator
     channel, **and** the operator address (`konsvaloper…` /
     `kons…`) the `MsgCreateValidator` will be signed with.
   - Funded: enough KASH for the self-delegation they intend plus fees.
     `min_self_delegation` in their message must be ≥ what they will
     actually delegate, `commission_rate` ≥ `min_commission_rate` (5 %,
     D10) or the message fails and the window was wasted.
   - The message **pre-built and pre-signed**, delivered as a file:
     ```sh
     # explicit fee and a timeout: a zero-fee tx fails inside the window
     # with "insufficient fee" and forces a new window; the timeout-height
     # makes a stale pre-signed tx unusable after the window.
     konstellationd tx staking create-validator validator.json \
       --from <operator> --chain-id <net> --node <rpc> \
       --gas 300000 --gas-prices 10000000000esp \
       --timeout-height <window end height + margin> \
       --generate-only > unsigned.json
     konstellationd tx sign unsigned.json --from <operator> --chain-id <net> --node <rpc> > signed-create-validator.json
     ```
     The lead dry-runs it: `konstellationd tx validate-signatures
     signed-create-validator.json` and checks the pubkey, addresses,
     amounts and commission against what was agreed. Nothing is broadcast
     yet — broadcasting now is refused by the breaker anyway, which is a
     free check that the gate is still closed.
3. **Admin readiness.** The multisig signers are online for the window
   (mainnet: three of five, `incident-comms.md` "Key holders"). Two
   admin transactions are pre-built:
   ```sh
   # 1. open
   konstellationd tx circuit reset /cosmos.staking.v1beta1.MsgCreateValidator \
     --from <admin> --chain-id <net> --node <rpc> --generate-only > reset.json
   # 2. close
   konstellationd tx circuit disable /cosmos.staking.v1beta1.MsgCreateValidator \
     --from <admin> --chain-id <net> --node <rpc> --generate-only > disable.json
   ```
   On mainnet each is signed by the multisig's members (`tx multisign`)
   ahead of the window, with sequence numbers set so that `reset` and
   `disable` are consecutive (`--sequence`, `--offline`).
4. **Confirm the current state is closed**, and that the disabled list
   contains nothing else you would be surprised by:
   ```sh
   konstellationd query circuit disabled-list --node <rpc>
   ```
5. **Announce** the window in the operator channel: height range, the
   operator's moniker and valoper, and that the set will grow by one.

## The window

Aim for **one block**: the three transactions — `reset`, the operator's
`create-validator`, `disable` — broadcast back-to-back to the same sentry
RPC, in that order, within one block time (~1.5 s target; realistically
they land in one or two consecutive blocks). The order is enforced by the
sequence numbers on the admin side; the operator's tx only depends on the
`reset` having executed, so it is submitted the instant `reset` is seen
in a block (or in the same block, if the node's mempool orders by
arrival — do not rely on that).

```sh
# terminal 1 — lead, watching
konstellationd query circuit disabled-list --node <rpc>   # loop this

# terminal 2 — admin
konstellationd tx broadcast reset.json   --node <rpc> --broadcast-mode sync
# wait for it in a block:
konstellationd query tx <hash> --node <rpc>

# terminal 3 — operator (or the lead, with the operator's signed file)
konstellationd tx broadcast signed-create-validator.json --node <rpc> --broadcast-mode sync
konstellationd query tx <hash> --node <rpc>               # code 0 expected

# terminal 2 — admin, immediately, whether or not step 3 succeeded
konstellationd tx broadcast disable.json --node <rpc> --broadcast-mode sync
```

**Close the gate regardless of the outcome.** If the operator's tx fails
(wrong commission, insufficient funds, bad pubkey), the answer is to fix
the message and run a *new* window — not to leave the gate open while it
is fixed.

What the window exposes, and why it is acceptable (D16): anyone watching
the mempool could slip their own `MsgCreateValidator` into the same
blocks. A validator created that way **does enter the active set** —
`max_validators` is 30 (D10) and only 10 seats are taken, so any bonded
validator is in the set; what its stake decides is its *voting power*,
which next to ten foundation-scale validators is negligible, and it can
be jailed for downtime like any other. It cannot be un-created — if one
appears, it is a validator like any other, and its existence goes in the
write-up. If this ever becomes a real problem, the
recorded fallback is gating the same message on `x/compliance`'s
allowlist in the ante handler; it is deliberately not built (it would
break D6's "allowlisting is never required" rule).

## After

1. **Gate closed:** `query circuit disabled-list` shows
   `/cosmos.staking.v1beta1.MsgCreateValidator` again. If it does not,
   this is an incident: broadcast `disable` again immediately, then find
   out why.
2. **Exactly one new validator**, the intended one:
   ```sh
   konstellationd query staking validators --node <rpc> | grep -c operator_address   # was N, now N+1
   konstellationd query staking validator <konsvaloper…> --node <rpc>                # status, tokens, commission, pubkey match
   ```
   Any *other* new validator: record it, announce it, do not touch it.
3. **The operator is signing** — once their stake puts them in the active
   set (`bonded`, not `unbonded`): their consensus address appears in
   block commits, `query slashing signing-info <conspub>` shows a rising
   index and zero missed blocks, and tenderduty has a `tenderduty_validators`
   entry for them (`group_vars/monitoring.yml`; the foundation pages on
   every validator's liveness, not only its own).
4. **Records:** the validator's moniker, valoper, consensus pubkey, the
   heights of the three transactions and their hashes, in the private ops
   notes; `networks/<net>/README.md` validator list if one is kept; the
   operator channel gets the "welcome" line.
5. **Write-up** in this directory as `admissions/<date>-<moniker>.md`
   (first one creates the directory): what took longest, how many blocks
   the window spanned, and the diff to this file.

## Removing a validator

There is no admission in reverse: the gate controls creation only. A
validator that must go is unbonded by its delegators, or jailed by the
chain for downtime / tombstoned for double-signing (D10). The foundation
can redelegate away from it; it cannot delete it. That asymmetry is by
design (D14/D16) and belongs in the whitepaper's roadmap language.

## Going permissionless (governance)

When the roadmap stage says so, the gate is removed for good by a
governance proposal — `x/circuit`'s authority is governance (D14), so
governance can reset what the admin disabled, and can also revoke the
admin's permission if the foundation's role in admission is to end:

```json
{
  "messages": [
    {
      "@type": "/cosmos.circuit.v1.MsgResetCircuitBreaker",
      "authority": "<gov module account>",
      "msg_type_urls": ["/cosmos.staking.v1beta1.MsgCreateValidator"]
    }
  ],
  "metadata": "<ipfs or url>",
  "deposit": "1000000000000000000000esp",
  "title": "Open validator admission",
  "summary": "Removes MsgCreateValidator from the circuit breaker's disabled list permanently (D16 stage <n>)."
}
```

```sh
konstellationd tx gov submit-proposal proposal.json --from <proposer> --node <rpc>
```

Check the exact message type URL and authority address against the
pinned SDK before submitting (`konstellationd query circuit accounts`
lists who holds what; the gov module account is `konstellationd query auth
module-account gov`). After it passes: `disabled-list` no longer contains
the type, and the admin multisig should **not** re-disable it — a re-trip
after governance opened admission is the one thing that would read as the
foundation overriding a vote. Whether the admin keeps `LEVEL_SUPER_ADMIN`
for the other D14 emergency uses (`emergency-halt.md`) is a separate,
recorded decision, not a side effect of this proposal.

Voting period and quorum are D11's (3 d / 33.4 % on mainnet, 2 h on
testnet-1) — rehearse the proposal path on testnet-1 once, so the first
mainnet proposal of this kind is not also the first ever.
