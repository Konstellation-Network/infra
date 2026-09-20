# On-call

**Rehearsed:** never. **Rota:** not yet set — see "Schedule" below.

`ENGINEERING.md §17` decided the ownership model (shared across engineering,
any engineer may handle any row) and made one exception: **pages need a named
person at every moment**. "Anyone" is nobody at 03:00. This document is the
mechanics of that exception; the schedule itself is decided when validators
exist (§17 rule 3).

## What pages

| Source | Signal | Severity | Route |
|---|---|---|---|
| tenderduty (`ansible/roles/monitoring_server`) | validator missed ≥ 5 consecutive blocks, ≥ 10 % in the window, validator inactive/jailed, no reachable RPC, chain stalled 3 min | critical | tenderduty's own channels (`alert_pagerduty_routing_key` / `alert_discord_webhook_url` / `alert_telegram_*` / `alert_slack_webhook_url`) |
| Prometheus → Alertmanager (`monitoring/prometheus/alerts.yml`) | `NoNewBlocks` (the exploit tripwire, `ENGINEERING.md §9.2`), `ValidatorMissedBlocks`, `DiskHeadroomCritical`, `NodeDown` | critical, re-pages every 30 min until acknowledged | Alertmanager `on-call` receiver |
| Prometheus → Alertmanager | `FallingPeerCount`, `BlockTimeDrift`, `DiskHeadroomLow` | warning, no page | `on-call-warnings` receiver (chat channel) |
| GitHub (`konstellation` repo) | issue labelled `upstream-release` or `vulncheck` | not a page — 1 working day to self-assign (§17) | GitHub notifications |

**Both routes are placeholders today**: with every `alert_*` variable empty,
Alertmanager receives and shows alerts in its UI and tenderduty logs them,
and nobody is paged. That is deliberate — a pager to "anyone" trains everyone
to ignore it. Filling the variables (from a vault, never in `group_vars` in
plain text) is the last step of setting the schedule, not the first.

## Response targets

| | Target | From |
|---|---|---|
| Acknowledge a critical page | **15 minutes** | `ENGINEERING.md §17` |
| First status line in the incident channel | 15 minutes after ack | `incident-comms.md` |
| Back to producing blocks after a halt | **90 minutes** | `ENGINEERING.md §13` item 4 |
| Upstream security tag → patched fleet | **24 hours** | `ENGINEERING.md §4.2` |

## The first 15 minutes

1. **Acknowledge** the page (PagerDuty ack / reply in the channel). Silence
   nothing yet.
2. **Open the incident channel** and post the one-line format from
   `incident-comms.md`: what fired, what you see, what you are doing next.
3. **Look before touching.** Through the bastion:
   ```sh
   ssh -F ansible/inventories/<net>/ssh_config <sentry> \
     'curl -s localhost:26657/status | jq .result.sync_info'
   ssh -F ansible/inventories/<net>/ssh_config <sentry> \
     'curl -s localhost:26657/net_info | jq .result.n_peers'
   ssh -F ansible/inventories/<net>/ssh_config <validator> \
     'journalctl -u cosmovisor -n 200 --no-pager'
   ```
   Grafana / Alertmanager / tenderduty are loopback-only on the monitoring
   host; forward them:
   ```sh
   ssh -F ansible/inventories/<net>/ssh_config \
     -L 3000:localhost:3000 -L 9093:localhost:9093 -L 8888:localhost:8888 \
     <monitoring-host>
   ```
4. **Classify** (this decides which runbook you are now in):

   | You see | It is | Go to |
   |---|---|---|
   | one validator missing blocks, chain height advancing everywhere else | a node problem | fix the node; if the host is gone, `validator-key-rotation.md` "failover" — **never** start the key elsewhere while the old host might still be up (§2.7) |
   | height not advancing on **any** node, no upgrade scheduled | a consensus halt or **the exploit scenario** | `emergency-halt.md` |
   | height not advancing at exactly the planned upgrade height | the upgrade | `coordinated-upgrade.md` "at the height" |
   | peers falling fleet-wide, height still advancing | networking / a sentry problem | check sentries first; a validator with 0 peers stops signing |
   | disk critical | a host problem, with a deadline | free space or resize; IAVL commits fail at 0 % |
   | an `upstream-release` issue for a *security* tag | a 24 h clock | `emergency-halt.md` "advisory with a patch" |

5. **Escalate** if it is anything in the second or third row: pull in a
   second engineer immediately. Halts are two-person operations.

## Handover

At the end of a shift the outgoing on-call posts in the channel: open alerts
(silenced or not, with the silence's expiry), anything degraded, anything
scheduled (an upgrade height, a maintenance window). Silences must have an
expiry and a comment naming the person; a silence without either is deleted
by the incoming on-call.

## Schedule

**TBD — set before testnet-1 launches** (`ENGINEERING.md §17`: "set up in
`infra` before testnet-1"). Fill in here and in the pager tool; this file is
the source of truth for the mechanics, the tool for who is on right now.

| Field | Value |
|---|---|
| Rotation length | *TBD* (suggested: one week, Monday 09:00 UTC handover) |
| Primary | *TBD* |
| Secondary (escalation after 15 min unacknowledged) | *TBD* |
| Pager tool | *TBD* (PagerDuty routing key → `alert_pagerduty_routing_key`; or Discord/Telegram via tenderduty's native routes) |
| Incident channel | *TBD* — `incident-comms.md` |
| Override / swap procedure | *TBD* |
| Halt-drill lead | whoever is primary in the drill week (§17) |

Constraints on whatever is chosen: a rotation covers all 168 hours; the
secondary is never the same person as the primary; the schedule is visible
to the whole team; a change to it is a PR to this file.
