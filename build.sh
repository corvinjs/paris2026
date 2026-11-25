#!/usr/bin/env bash
# apt: jekyll imagemagick libjxl-tools ffmpegthumbnailer
# Usage: ./build.sh [BASEURL] [OUTDIR]
#   BASEURL defaults to baseurl in _config.yml, OUTDIR to _site.
#   Image variants and video posters from an earlier build in OUTDIR are reused.
set -euo pipefail
cd "$(dirname "$0")"
JEKYLL_ENV=production exec jekyll build --quiet ${1+--baseurl "$1"} --destination "${2:-_site}"
