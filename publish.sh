#!/bin/bash

bash pull.sh

git add . >/dev/null 2>&1

# Only commit if there are actual changes staged
if ! git diff --cached --quiet; then
    git commit -m "still alive" -q >/dev/null 2>&1
    echo Created new commit
fi

# Push silently and display success message on completion
if git push -q >/dev/null 2>&1; then
    echo "Everything up-to-date"
fi
