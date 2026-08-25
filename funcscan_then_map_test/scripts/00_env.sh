#!/usr/bin/env bash
# Source this before any nextflow command: `source scripts/00_env.sh`
# Identical to ../scripts/00_env.sh -- same cluster, same modules, same TMPDIR gotcha.
set -euo pipefail

source /usr/share/Modules/init/bash 2>/dev/null
module load openjdk/20.0.0
module load nextflow/25.10.4
module load singularity/3.8.7
unset TMPDIR

echo "Environment ready: $(nextflow -version 2>&1 | grep version) / $(singularity --version)"
