#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-/}"

log() {
  echo "==> $*"
}

if command -v apt-get >/dev/null; then
  packages=()
  if ! { command -v magick >/dev/null || command -v convert >/dev/null; }; then
    packages+=(imagemagick)
  fi
  if ! command -v cjxl >/dev/null; then
    packages+=(libjxl-tools)
  fi
  if ! command -v ffmpegthumbnailer >/dev/null; then
    packages+=(ffmpegthumbnailer)
  fi
  if ((${#packages[@]})); then
    log "Installing ${packages[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt_log="$(mktemp)"
    if timeout 240s sudo apt-get update >"$apt_log" 2>&1 &&
      timeout 240s sudo apt-get install -y -o Dpkg::Use-Pty=0 "${packages[@]}" >>"$apt_log" 2>&1; then
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

if ! { command -v magick >/dev/null || command -v convert >/dev/null; } ||
  ! command -v cjxl >/dev/null || ! command -v ffmpegthumbnailer >/dev/null; then
  echo "ERROR: ImageMagick (magick or convert), cjxl, and ffmpegthumbnailer are required" >&2
  exit 1
fi

export GEM_HOME="$HOME/.gems"
export PATH="$GEM_HOME/bin:$PATH"

BUNDLER_VERSION="4.0.20"

if ! bundle "_${BUNDLER_VERSION}_" --version >/dev/null 2>&1; then
  log "Installing Bundler"
  gem install --no-document bundler --version "$BUNDLER_VERSION"
fi

# Keep installed gems inside the project so the build cache can retain them.
# The local Bundler setting also makes subsequent commands such as
# `bundle exec jekyll serve` use the same gems outside this script.
bundle "_${BUNDLER_VERSION}_" config set --local path .gems

if ! bundle "_${BUNDLER_VERSION}_" check >/dev/null 2>&1; then
  log "Installing Ruby dependencies"
  bundle "_${BUNDLER_VERSION}_" install --jobs 4 --retry 3
fi

log "Building Jekyll site (baseurl=${BASE_URL})"
JEKYLL_ENV=production bundle "_${BUNDLER_VERSION}_" exec jekyll build --baseurl "$BASE_URL" --quiet
