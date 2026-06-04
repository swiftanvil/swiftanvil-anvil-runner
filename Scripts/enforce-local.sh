#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
workspace_root=$(CDPATH='' cd -- "$repo_root/.." && pwd)
enforcement_root="$workspace_root/swiftanvil-enforcement"
registry_root="$workspace_root/swiftanvil-meta"

if [ ! -x "$enforcement_root/scripts/enforce-local.sh" ]; then
  echo "error: SwiftAnvil enforcement checkout not found at $enforcement_root" >&2
  echo "clone https://github.com/swiftanvil/swiftanvil-enforcement next to this repository" >&2
  exit 2
fi

if [ ! -f "$registry_root/REGISTRY.yml" ]; then
  echo "error: SwiftAnvil registry checkout not found at $registry_root" >&2
  echo "clone https://github.com/swiftanvil/swiftanvil-meta next to this repository" >&2
  exit 2
fi

"$enforcement_root/scripts/enforce-local.sh" \
  --registry-root "$registry_root" \
  --root "$repo_root"
