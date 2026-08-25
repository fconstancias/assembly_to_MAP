#!/usr/bin/env bash
# The actual test run: one single assembly (megaS121) + its covering coassembly
# (co728), both participant 728. See README.md for what this is testing and why.
#
#   source scripts/00_env.sh
#   bash scripts/01_download_databases.sh          # first time only
#   bash scripts/01b_download_interproscan.sh      # first time only (needed for SanntiS)
#   bash scripts/02_apply_local_patches.sh         # first time only (see its own docstring
#                                                   #   for the --invalidate-cache case)
#   bash scripts/03_run_test_participant728.sh
#
# Safe to re-run: nextflow -resume picks up from wherever it left off.
#
# --skip_sanntis false: real SanntiS BGC predictions (needs scripts/01b's ~17GB core IPS
# data). signalP column in the combined report still won't populate -- that needs the
# licensed SignalP hook, which isn't set up (see scripts/01b_download_interproscan.sh and
# github_issue_drafts.md issue 9/4).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # assembly_to_MGE/

nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 \
    --input samplesheet_participant728_test.csv \
    --outdir results/01_map_test_participant728 \
    --skip_sanntis false \
    -c nextflow.config \
    -c my_paths.config \
    -profile singularity \
    -with-trace map_test_trace.txt \
    -resume map_test_participant728
