#!/bin/sh
# Kept for anyone with the old command in their notes. The full suite lives in
# Scripts/run_tests.sh, which compiles each test against only the sources it
# exercises.
set -eu
exec "$(dirname "$0")/../Scripts/run_tests.sh" "$@"
