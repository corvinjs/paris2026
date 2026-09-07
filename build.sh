#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-/}"

log() {
  echo "==> $*"
}

if command -v apt-get >/dev/null; then
  if ! { command -v magick >/dev/null || command -v convert >/dev/null; } || ! command -v cjxl >/dev/null; then
    log "Installing imagemagick and libjxl-tools"
    export DEBIAN_FRONTEND=noninteractive
    apt_log="$(mktemp)"
    if timeout 240s bash -c 'sudo apt-get update && sudo apt-get install -y -o Dpkg::Use-Pty=0 imagemagick libjxl-tools' >"$apt_log" 2>&1; then
      rm -f "$apt_log"
    else
      status=$?
      echo "ERROR: apt installation failed (status ${status}); output follows:" >&2
      cat "$apt_log" >&2
      rm -f "$apt_log"
      exit "$status"
    fi
  fi
fi

if ! { command -v magick >/dev/null || command -v convert >/dev/null; } || ! command -v cjxl >/dev/null; then
  echo "ERROR: ImageMagick (magick or convert) and cjxl are required" >&2
  exit 1
fi

export GEM_HOME="$HOME/.gems"
export PATH="$GEM_HOME/bin:$PATH"

if ! command -v jekyll >/dev/null; then
  log "Installing Jekyll"
  gem install --no-document jekyll >/dev/null 2>&1
fi

log "Building Jekyll site (baseurl=${BASE_URL})"
JEKYLL_ENV=production jekyll build --baseurl "$BASE_URL" --quiet
