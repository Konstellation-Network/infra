# Incident communications

**Rehearsed:** never. Channels marked *TBD* are set with the on-call rota
(`on-call.md`) before testnet-1.

Two audiences, two channels, one voice. Internal is fast and blunt;
external is slow and precise. Nothing goes external that was not first
written internally.

## Channels

| | Purpose | Where | Who posts |
|---|---|---|---|
| **Incident channel** (internal) | the running log: every action, every observation, with a timestamp | *TBD* (a dedicated chat channel; one per incident is fine) | the responders; the scribe keeps the log |
| **Operator channel** (mainnet only) | validator operators: upgrade heights, halts, restart go/no-go | *TBD* — `ENGINEERING.md §9.4` says a Signal group | the incident lead |
| **Public status** | users, exchanges, the explorer's banner | *TBD* (status page / `@` account / `docs` banner) | the comms owner, after the lead approves the text |
| **Security contact** | inbound reports | `SECURITY.md` in `konstellation` (to be written, `ENGINEERING.md §6.1`) | whoever is on-call triages |

## Roles

Assigned in the first message of the incident channel, by the on-call:

- **Lead** — decides. Usually the on-call primary until they hand over.
- **Scribe** — writes everything down with times; owns the write-up.
  Cannot be the lead.
- **Comms** — talks outward. On a small team this is the lead's second.
- **Key holders** — for a circuit-breaker trip or compliance freeze on
  mainnet, the multisig signers. *TBD* list; must be reachable within the
  15-minute window of `on-call.md`, which means the pager reaches them too.

## Templates

**Internal — first message** (within 15 min of acknowledging, `on-call.md`):

```
INCIDENT <date>-<short name>
Lead: <name>  Scribe: <name>  Comms: <name>
Trigger: <alert / report>, fired <HH:MM UTC>
Observed: <heights, which nodes, what the explorer shows>
Doing next: <one line>
Runbook: <emergency-halt.md | coordinated-upgrade.md | validator-key-rotation.md>
```

Then one line per action, timestamped, in the channel. Copy-paste the
command you ran and the salient output. "Restarted v2" is not a log line;
"14:02 `systemctl restart cosmovisor` on hetzner-v2; back at height 812004,
signing" is.

**Operator channel — halt** (mainnet):

```
[Konstellation] HALT at height <H> (~<HH:MM UTC>).
Set halt-height = <H> in app.toml and restart now. Do NOT restart after the halt until the go message.
Reason: <security patch | consensus fault | under investigation>. Details to follow here.
Upgrade file: <link, if any>
```

**Operator channel — restart go:**

```
[Konstellation] RESTART GO. Binary v<X.Y.Z> sha256 <…> (networks/<net>/upgrades/<file>).
Clear halt-height, stage the binary per the upgrade file, start sentries then validators.
Confirm here with `konstellationd status | jq .sync_info.latest_block_height` once signing.
```

**Public — during** (only after the lead approves; every 60 min while
open, even if nothing changed):

```
<HH:MM UTC> Konstellation <testnet-1|mainnet> is halted at height <H> while we
<apply a security patch | investigate a consensus fault>. Funds are not at risk
[or: we are investigating reports of <…>]. Next update by <HH:MM UTC>.
```

**Public — resolved:**

```
<HH:MM UTC> Konstellation resumed producing blocks at <HH:MM UTC>, height <H+1>,
on v<X.Y.Z>. <One sentence on cause.> A full write-up will be published at <link> by <date>.
```

## Rules

1. **No speculation outward.** "Under investigation" is a complete sentence.
   The cause goes public in the write-up, when it is known.
2. **Never name the upstream advisory before the fleet is patched.**
   `ENGINEERING.md §4.2`: the window between "advisory public" and "chain
   patched" is when chains get drained. On the day of a `cosmos/evm`
   security tag, the public line is "scheduled maintenance upgrade at
   height H", nothing more, until every validator is on the new binary.
3. **Every halt has a next-update time**, and it is met, even with "no
   change".
4. **Funds moved ⇒ legal is in the channel** before anything is said
   publicly about amounts, addresses or reversal (`ENGINEERING.md §10`
   "reversal options" are governance and legal decisions).
5. **Silence is not resolution.** The incident is closed by the lead in the
   channel with the resolved template, and the write-up lands within 48 h
   in `infra/runbooks/` (private) with a public version in `docs` when
   appropriate.

## Write-up

Within 48 h, by the scribe, in this directory as
`incidents/<date>-<short-name>.md` (create the directory with the first
one). Sections: timeline (from the channel log), impact (blocks lost, funds,
users), cause, what worked, what did not, actions with owners — and the
diff to whichever runbook was wrong.
