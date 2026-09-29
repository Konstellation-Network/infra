# Remote state, partial config — fill in with `terraform init -backend-config=backend.hcl`.
# Same pattern as envs/testnet-1/backend.tf, and the same open decision: the
# state bucket (STATUS §5a P4) has not been created or named. backend.hcl
# (gitignored) example — one bucket, one prefix per network:
#   bucket = "konstellation-terraform-state"
#   prefix = "devnet-1"
#
# devnet-1 is Hetzner-only, so a GCS bucket is the only GCP dependency this
# environment has; if P4 lands somewhere else (S3-compatible, e.g. Hetzner
# Object Storage), change the backend type here and in testnet-1 together.
# Placeholder, not a working default.
terraform {
  backend "gcs" {}
}
