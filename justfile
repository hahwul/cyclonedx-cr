default:
  just --list

build:
  shards build

test:
  crystal spec

fix:
  crystal tool format

# Check version consistency across all files
version-check:
  #!/usr/bin/env bash
  set -euo pipefail
  version=$(grep '^version:' shard.yml | awk '{print $2}')
  echo "Source version (shard.yml): $version"
  echo ""
  files=(
    "flake.nix"
    "README.md"
    "github-action/Dockerfile"
    ".github/workflows/release-sbom.yml"
  )
  ok=true
  for file in "${files[@]}"; do
    if grep -q "$version" "$file"; then
      echo "  [OK] $file"
    else
      echo "  [MISMATCH] $file"
      ok=false
    fi
  done
  echo ""
  if [ "$ok" = true ]; then
    echo "All files are in sync."
  else
    echo "Some files have mismatched versions!"
    exit 1
  fi

alias vc := version-check

# Update version across all files
version-update new_version:
  #!/usr/bin/env bash
  set -euo pipefail
  old_version=$(grep '^version:' shard.yml | awk '{print $2}')
  new_version="{{new_version}}"
  echo "Updating version: $old_version -> $new_version"
  echo ""
  sed -i '' "s/^version: .*/version: $new_version/" shard.yml
  echo "  [UPDATED] shard.yml"
  sed -i '' "s/version = \"$old_version\"/version = \"$new_version\"/" flake.nix
  echo "  [UPDATED] flake.nix"
  sed -i '' "s|cyclonedx-cr@v$old_version|cyclonedx-cr@v$new_version|g" README.md
  echo "  [UPDATED] README.md"
  sed -i '' "s|cyclonedx-cr:v$old_version|cyclonedx-cr:v$new_version|" github-action/Dockerfile
  echo "  [UPDATED] github-action/Dockerfile"
  sed -i '' "s|cyclonedx-cr@v$old_version|cyclonedx-cr@v$new_version|g" .github/workflows/release-sbom.yml
  echo "  [UPDATED] .github/workflows/release-sbom.yml"
  echo ""
  echo "Done! Run 'just version-check' to verify."

alias vu := version-update
