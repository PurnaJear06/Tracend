#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tool/versions.env"

tooling_dir="$repo_root/.tooling"
downloads_dir="$tooling_dir/downloads"
bin_dir="$tooling_dir/bin"
lima_dir="$tooling_dir/lima/$LIMA_VERSION"
docker_dir="$tooling_dir/docker/$DOCKER_CLI_VERSION"

mkdir -p "$downloads_dir" "$bin_dir" "$lima_dir" "$docker_dir"

colima_asset="colima-Darwin-arm64"
colima_url="https://github.com/abiosoft/colima/releases/download/v$COLIMA_VERSION"
lima_asset="lima-$LIMA_VERSION-Darwin-arm64.tar.gz"
lima_url="https://github.com/lima-vm/lima/releases/download/v$LIMA_VERSION"
docker_asset="docker-$DOCKER_CLI_VERSION.tgz"
docker_url="https://download.docker.com/mac/static/stable/aarch64/$docker_asset"

if [[ ! -f "$downloads_dir/$colima_asset" ]]; then
  curl --connect-timeout 15 --max-time 300 --fail --location \
    --output "$downloads_dir/$colima_asset" \
    "$colima_url/$colima_asset"
fi
if [[ ! -f "$downloads_dir/$colima_asset.sha256sum" ]]; then
  curl --connect-timeout 15 --max-time 60 --fail --location \
    --output "$downloads_dir/$colima_asset.sha256sum" \
    "$colima_url/$colima_asset.sha256sum"
fi

(
  cd "$downloads_dir"
  shasum -a 256 --check "$colima_asset.sha256sum"
)

install -m 0755 "$downloads_dir/$colima_asset" "$bin_dir/colima"

if [[ ! -f "$downloads_dir/$lima_asset" ]]; then
  curl --connect-timeout 15 --max-time 300 --fail --location \
    --output "$downloads_dir/$lima_asset" \
    "$lima_url/$lima_asset"
fi
if [[ ! -f "$downloads_dir/lima-SHA256SUMS" ]]; then
  curl --connect-timeout 15 --max-time 60 --fail --location \
    --output "$downloads_dir/lima-SHA256SUMS" \
    "$lima_url/SHA256SUMS"
fi

expected_lima_checksum="$(
  awk -v asset="$lima_asset" '$2 == asset { print $1 }' \
    "$downloads_dir/lima-SHA256SUMS"
)"
actual_lima_checksum="$(shasum -a 256 "$downloads_dir/$lima_asset" | awk '{ print $1 }')"

if [[ -z "$expected_lima_checksum" || "$actual_lima_checksum" != "$expected_lima_checksum" ]]; then
  echo "Lima checksum verification failed." >&2
  exit 1
fi

mkdir -p "$lima_dir"
tar -xzf "$downloads_dir/$lima_asset" -C "$lima_dir"

if [[ ! -f "$downloads_dir/$docker_asset" ]]; then
  curl --connect-timeout 15 --max-time 300 --fail --location \
    --output "$downloads_dir/$docker_asset" \
    "$docker_url"
fi

actual_docker_checksum="$(shasum -a 256 "$downloads_dir/$docker_asset" | awk '{ print $1 }')"
if [[ "$actual_docker_checksum" != "$DOCKER_CLI_SHA256" ]]; then
  echo "Docker CLI checksum verification failed." >&2
  exit 1
fi

tar -xzf "$downloads_dir/$docker_asset" -C "$docker_dir"

"$bin_dir/colima" version
"$lima_dir/bin/limactl" --version
"$docker_dir/docker/docker" --version
