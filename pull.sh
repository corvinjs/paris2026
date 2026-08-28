#!/bin/bash

# Fetch remote tracking branches silently
git fetch -q

# Count how many commits local is behind remote
BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null)

if [ "$BEHIND" -eq 0 ]; then
    echo "Remote had no changes"
fi

# Run stash and pull with zero output
git stash push -q >/dev/null 2>&1
git pull --rebase -q >/dev/null 2>&1
git stash pop -q >/dev/null 2>&1
