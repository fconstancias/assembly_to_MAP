#!/usr/bin/env bash
# Apply every patch in patches/*.patch to funcscan's already-pulled Nextflow assets
# (~/.nextflow/assets/nf-core/funcscan/ -- same git-checkout structure as MAP's, see
# ../scripts/02_apply_local_patches.sh, same two gotchas apply here too:
#   1. Must patch the assets copy the `nextflow run nf-core/funcscan` remote-form command
#      actually uses -- not a separate local clone (that changes project resolution and
#      invalidates the ENTIRE resume cache, not just the patched task).
#   2. Nextflow's resume/task-hash does not track content changes to `bin/`-staged helper
#      scripts (they're added to PATH, not declared process inputs) -- patching the file
#      alone does not make a cached task notice anything changed. Pass --invalidate-cache
#      to force AMP_DATABASE_DOWNLOAD specifically to re-run after already having failed once.
#
# Run BEFORE the first run if starting fresh (recommended):
#   nextflow run nf-core/funcscan -r 4.0.0 --help   # pulls assets without executing
#   bash scripts/00b_apply_local_patches.sh
#
# If scripts/01_run_funcscan.sh already failed on AMP_DATABASE_DOWNLOAD once:
#   bash scripts/00b_apply_local_patches.sh --invalidate-cache
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # funcscan_then_map_test/

ASSET_DIR="$HOME/.nextflow/assets/nf-core/funcscan"

if [ ! -d "$ASSET_DIR" ]; then
    echo "Pipeline not pulled yet -- pulling now (no execution, just fetches assets)..."
    nextflow run nf-core/funcscan -r 4.0.0 --help > /dev/null
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
    echo "Forcing AMP_DATABASE_DOWNLOAD to re-execute (deleting its cached work dir)..."
    if [ ! -f .nextflow.log ]; then
        echo "  No .nextflow.log here -- nothing to invalidate, you haven't run yet."
    else
        WORKDIRS=$(grep "AMP_DATABASE_DOWNLOAD" .nextflow.log \
            | grep -o "workDir: [^ ]*" | cut -d' ' -f2 | sort -u)
        if [ -z "$WORKDIRS" ]; then
            echo "  No AMP_DATABASE_DOWNLOAD task found in .nextflow.log -- nothing to do."
        else
            for wd in $WORKDIRS; do
                echo "  removing $wd"
                rm -rf "$wd"
            done
            echo "  Done. Re-run with -resume: everything else stays cached (including the"
            echo "  already-completed Pyrodigal gene-calling), only this task and whatever"
            echo "  depends on it re-executes."
        fi
    fi
fi
