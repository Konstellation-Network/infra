# Grafana

No dashboards yet — not building one from memory against metrics nobody has
seen live (see the caveat in `../prometheus/alerts.yml`). Once a testnet-1
node is running:

1. Point Grafana at the Prometheus instance scraping the fleet.
2. Confirm the real metric names from `/metrics` on a running node.
3. Build a first dashboard with: block height + rate, peer count per node,
   missed blocks per validator, disk headroom, and the same "no new blocks"
   signal `alerts.yml` pages on — a dashboard and its page should never
   disagree about what "down" means.
4. Export the dashboard JSON here.
