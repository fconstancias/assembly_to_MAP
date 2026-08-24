#!/usr/bin/env bash
# Apply every patch in patches/*.patch to MAP's already-pulled Nextflow assets
# (issue 7/4: pathofact2_integrator.py's GFF-validity check only scans the first
# 200 lines, silently dropping all virulence/toxin output for any real assembly
# -- see README.md and github_issue_drafts.md for the full writeup).
#
# Run this BEFORE your first real run if starting fresh (recommended -- one command,
# `nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 --help`,
# pulls the pipeline assets without executing anything, so the patch applies cleanly
# before any task ever runs against the buggy version).
#
# If you already ran once WITHOUT the patch (so PATHOFACT2_INTEGRATOR is cached with
# its broken empty-output result), also pass --invalidate-cache to force those two
# specific tasks to re-execute -- see "IMPORTANT" note below for why a plain
# `-resume` after patching is NOT enough.
#
# IMPORTANT: patches/*.patch must be applied to the copy of the pipeline actually
# used by `nextflow run EBI-Metagenomics/mobilome-annotation-pipeline` --
# ~/.nextflow/assets/EBI-Metagenomics/mobilome-annotation-pipeline/ -- not to a
# separate local clone. Pointing nextflow at a local clone path instead of the
# remote-form name changes how it resolves the project and invalidates Nextflow's
# ENTIRE resume cache (every task, not just the patched one) -- this cost us a
# near-total pipeline re-run once; see README.md troubleshooting.
#
# Also important: Nextflow's task-hash/resume mechanism does NOT track the content
# of module-bundled `resources/usr/bin/*` helper scripts (they're staged into PATH,
# not declared as process inputs) -- so patching the file alone does not make
# `-resume` notice anything changed. That's what --invalidate-cache is for.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # assembly_to_MGE/

ASSET_DIR="$HOME/.nextflow/assets/EBI-Metagenomics/mobilome-annotation-pipeline"

if [ ! -d "$ASSET_DIR" ]; then
    echo "Pipeline not pulled yet -- pulling now (no execution, just fetches assets)..."
    nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 --help > /dev/null
fi

echo "Applying patches to $ASSET_DIR ..."
for p in patches/*.patch; do
    p_abs="$(pwd)/$p"   # git -C resolves relative paths against ASSET_DIR, not cwd -- must be absolute
    if git -C "$ASSET_DIR" apply --reverse --check "$p_abs" 2>/dev/null; then
        echo "  $p : already applied, skipping"
    else
        git -C "$ASSET_DIR" apply "$p_abs"
        echo "  $p : applied"
    fi
done

if [ "${1:-}" = "--invalidate-cache" ]; then
    echo
    echo "Forcing PATHOFACT2_INTEGRATOR to re-execute (deleting its cached work dirs)..."
    if [ ! -f .nextflow.log ]; then
        echo "  No .nextflow.log here -- nothing to invalidate, you haven't run yet."
    else
        WORKDIRS=$(grep "PATHOFACT2_INTEGRATOR" .nextflow.log \
            | grep -o "workDir: [^ ]*" | cut -d' ' -f2 | sort -u)
        if [ -z "$WORKDIRS" ]; then
            echo "  No PATHOFACT2_INTEGRATOR task found in .nextflow.log -- nothing to do."
        else
            for wd in $WORKDIRS; do
                echo "  removing $wd"
                rm -rf "$wd"
            done
            echo "  Done. Re-run with -resume: everything else stays cached, only"
            echo "  PATHOFACT2_INTEGRATOR and whatever depends on it (COMBINEREPORTER,"
            echo "  GFF_MAPPING_COMPRESSION_AND_INDEXING, MULTIQC) will re-execute."
        fi
    fi
fi
