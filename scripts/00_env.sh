#!/usr/bin/env bash
# Source this before any nextflow command: `source scripts/00_env.sh`
# Not meant to be executed directly (it needs to affect your current shell).
set -euo pipefail

source /usr/share/Modules/init/bash 2>/dev/null
module load openjdk/20.0.0
module load nextflow/25.10.4
module load singularity/3.8.7

# See README.md "Monitoring / troubleshooting": if TMPDIR is set to something
# that doesn't exist inside Singularity containers (common in interactive/agent
# shells), amrfinder_update and similar tools fail with
# "Error creating a temporary directory". Always run with it unset.
unset TMPDIR

echo "Environment ready: $(nextflow -version 2>&1 | grep version) / $(singularity --version)"
