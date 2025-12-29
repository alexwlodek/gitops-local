#!/bin/bash
set -euo pipefail

./scripts/create-cluster.sh
./scripts/bootstrap-cluster.sh
