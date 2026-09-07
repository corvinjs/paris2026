#!/bin/bash

bash pull.sh

git add . >/dev/null 2>&1

# Only commit if there are actual changes staged
if ! git diff --cached --quiet; then
    echo Create new commit
    git commit -m "still alive" -q
fi
