#!/usr/bin/env bash
# Run funcscan (see ../CLAUDE.md open question 7):
#   ARG : ALL 5 tools -- ABRicate, AMRFinderPlus, fARGene, RGI, DeepARG + argNorm.
#     Decided 2026-08-25 to run the full set here, not just ABRicate/fARGene, even though
#     AMRFinderPlus/RGI/DeepARG duplicate what MAP also runs -- the payoff is ONE
#     hAMRonization table covering all 5 ARG tools in a single normalized schema, which
#     MAP's own combined_report.tsv doesn't give (it just lists each hit with a bare
#     amr_tool field, not a harmonized cross-tool report). These 3 tools are individually
#     cheap (unlike antiSMASH, which is why BGC below still skips it), so the redundant
#     compute is an acceptable trade for that.
#   AMP : ampir + Macrel + AMPlify           (MAP has zero AMP coverage)
#   BGC : DeepBGC                            (antiSMASH/GECCO still skipped -- MAP's job, antiSMASH alone ran ~3h on co728)
#   CAZyme: dbCAN                            (MAP has zero CAZyme coverage)
#
# Gene calling: pyrodigal (funcscan's own default) -- NOT prokka, which truncates/renames
# contig headers (its 20-char locus-tag limit) and would break the original-contig-ID
# handoff to MAP this whole test exists to validate. This run's own Pyrodigal output
# (protein FASTA + GFF) becomes MAP's proteins_gff/proteins_faa input in step 2 -- see
# scripts/02_prep_map_input.sh once funcscan's actual output paths are confirmed.
#
# First run: --save_db persists auto-downloaded databases into the run's own results dir
# (funcscan has no separate --download_dbs mode like MAP -- it downloads inline, on demand,
# per docs/usage.md). Move them to a shared scratch/funcscan_db/ location afterward and
# point the relevant --*_db params there directly for subsequent runs, matching this
# project's DB-directory convention (see ../CLAUDE.md).
#
# Apply scripts/00b_apply_local_patches.sh first (real bug found 2026-08-25:
# ampcombi_download.py crashes on a NaN row in DRAMP's live TSV export -- see
# patches/ampcombi_download_nan_sequence_fix.patch).
#
#   source scripts/00_env.sh
#   bash scripts/00b_apply_local_patches.sh
#   bash scripts/01_run_funcscan.sh
#
# Safe to re-run: -resume (via the fixed session name below) picks up from wherever it
# left off, same as MAP's own scripts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # funcscan_then_map_test/

nextflow run nf-core/funcscan -r 4.0.0 \
    --input samplesheet_funcscan_participant728.csv \
    --outdir results/01_funcscan_participant728 \
    --annotation_tool pyrodigal \
    --run_arg_screening \
    --run_amp_screening \
    --run_bgc_screening --bgc_skip_antismash --bgc_skip_gecco \
    --run_cazyme_screening \
    --save_db \
    -c nextflow.config \
    -profile singularity \
    -with-trace funcscan_trace.txt \
    -resume funcscan_test_participant728
