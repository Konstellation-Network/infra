# Remote state, partial config — fill in with `terraform init -backend-config=backend.hcl`.
# State for a live validator fleet must never be local-only or in git: it contains
# no secrets by itself, but losing it (or two people applying against stale local
# state) risks a destructive drift you'd only notice after the fact.
#
# GCS chosen now that a GCP project exists anyway (var.gcp_project) — a bucket
# there works fine as state storage regardless of which resources (Hetzner or
# GCP) it's tracking. backend.hcl (gitignored) example:
#   bucket = "konstellation-terraform-state"
#   prefix = "testnet-1"
#
# Not filled in here because the bucket hasn't been created yet — this is a
# placeholder, not a working default.
terraform {
  backend "gcs" {}
}
