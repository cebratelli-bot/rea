#!/bin/bash
# Prepares Claude Code cloud sessions: submodules, the pinned Node/npm
# toolchain (.nvmrc, packageManager) and npm dependencies.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

git submodule update --init --recursive

# Pinned toolchain: the container's default Node is older than package.json#engines allows
node_version="v$(tr -d '[:space:]' < .nvmrc)"
npm_version="$(node -p "require('./package.json').packageManager.split('@')[1]")"
node_dir="/opt/node-${node_version}"
if [ "$("$node_dir/bin/node" -v 2>/dev/null || true)" != "$node_version" ]; then
  tarball="node-${node_version}-linux-x64.tar.xz"
  tmp="$(mktemp -d)"
  curl -sSfL -o "$tmp/$tarball" "https://nodejs.org/dist/${node_version}/${tarball}"
  curl -sSfL "https://nodejs.org/dist/${node_version}/SHASUMS256.txt" | grep " ${tarball}\$" | (cd "$tmp" && sha256sum -c -)
  rm -rf "$node_dir" && mkdir -p "$node_dir"
  tar -xJf "$tmp/$tarball" -C "$node_dir" --strip-components=1
  rm -rf "$tmp"
fi
export PATH="$node_dir/bin:$PATH"
if [ "$(npm -v)" != "$npm_version" ]; then
  npm install --global "npm@${npm_version}"
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$node_dir/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Run the install only if a listed file has changed since the install last succeeded
hashes=node_modules/.session-start.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null; then
  # Delete the old hashes first, so a failed install runs again next time
  rm -f "$hashes"

  npm install

  sha256sum .claude/hooks/session-start.sh .nvmrc package.json package-lock.json 2>/dev/null > "$hashes" || rm -f "$hashes"
fi
