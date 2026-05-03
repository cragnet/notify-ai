#!/bin/bash
# generate_commit.sh — writes current git short hash to assets/commit.txt
set -e
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
mkdir -p assets
echo -n "$HASH" > assets/commit.txt
echo "Generated commit hash: $HASH"
