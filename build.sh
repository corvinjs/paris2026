#!/usr/bin/env bash

BASE_URL="${1:-/}"

export GEM_HOME="$HOME/.gems"
export PATH="$GEM_HOME/bin:$PATH"
gem install jekyll

JEKYLL_ENV=production jekyll build --baseurl "$BASE_URL"
