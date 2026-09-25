#!/usr/bin/env bash
set -euo pipefail

echo "CI preview: hello from $(uname -s)"
echo "Current directory:"
pwd

echo "Repository status:"
git status

echo "Done."
