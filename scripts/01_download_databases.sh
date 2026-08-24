#!/usr/bin/env bash
# One-time: download MAP's reference databases and work around the two upstream
# --download_dbs bugs documented in README.md (issues 1/4 and 2/4 in
# github_issue_drafts.md). Safe to re-run: every step is idempotent (skips work
# already done). Run from the assembly_to_MGE/ directory:
#
#   source scripts/00_env.sh && bash scripts/01_download_databases.sh
#
# Takes ~10-20 min depending on network speed. All output goes under
# DB_DIR (shared across projects, matches this project's DB-directory convention
# -- see CLAUDE.md "Shared resource DB convention").
set -euo pipefail

DB_DIR="/maps/projects/hansen_ol-AUDIT/scratch/mobilome_db"
SINGULARITY_CACHE="/maps/projects/hansen_ol-AUDIT/scratch/singularity_cache"
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # assembly_to_MGE/

echo "== Step 1: nextflow --download_dbs (VFDB + geNomad/icefinder2 download steps set to"
echo "   errorStrategy=ignore in nextflow.config -- both have known upstream bugs, fixed"
echo "   manually below rather than by editing MAP's own code) =="
nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 \
    --download_dbs "$DB_DIR" \
    -c nextflow.config \
    -profile singularity \
    -with-trace db_download_trace.txt \
    -resume map_db_download || true   # expected to report ignored failures; see below

echo
echo "== Step 2: manually build VFDB_setB_pro.dmnd (issue 1/4: DB_DOWNLOAD_VFDB's script"
echo "   calls curl, but its container only ships wget) =="
if [ ! -f "$DB_DIR/virulence/VFDB_setB_pro.dmnd" ]; then
    mkdir -p "$DB_DIR/virulence"
    cd "$DB_DIR/virulence"
    curl -L -o VFDB_setB_pro.fas.gz https://www.mgc.ac.cn/VFs/Down/VFDB_setB_pro.fas.gz
    DIAMOND_IMG="$SINGULARITY_CACHE/depot.galaxyproject.org-singularity-diamond-2.1.16--h13889ed_0.img"
    singularity exec --bind "$DB_DIR/virulence:$DB_DIR/virulence" --pwd "$DB_DIR/virulence" "$DIAMOND_IMG" \
        diamond makedb --threads 4 --in VFDB_setB_pro.fas.gz -d VFDB_setB_pro
    rm VFDB_setB_pro.fas.gz
    cd - > /dev/null
else
    echo "   already present, skipping"
fi

echo
echo "== Step 3: rescue geNomad + ICEfinder2 DBs from the failed DB_DOWNLOAD_MOBILOME_DBS"
echo "   task's work dir (issue 2/4: data downloads/extracts fine, but the process expects"
echo "   the extracted folder to be named genomad_db_v1.9/, while the tarball's actual"
echo "   top-level folder is genomad_db/) =="
if [ ! -d "$DB_DIR/genomad/genomad_db_v1.9" ]; then
    WORKDIR=$(grep "DOWNLOAD_DATABASES:DB_DOWNLOAD_MOBILOME_DBS" .nextflow.log 2>/dev/null \
        | grep -o "workDir: [^ ]*" | tail -1 | cut -d' ' -f2)
    if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR/genomad_db" ]; then
        echo "   ERROR: couldn't locate the DB_DOWNLOAD_MOBILOME_DBS work dir automatically."
        echo "   Check .nextflow.log manually for 'DB_DOWNLOAD_MOBILOME_DBS' and its workDir,"
        echo "   then: mkdir -p $DB_DIR/genomad $DB_DIR/icefinder2"
        echo "         cp -r <workDir>/genomad_db  $DB_DIR/genomad/genomad_db_v1.9"
        echo "         cp -r <workDir>/icf2_dbs    $DB_DIR/icefinder2/icf2_dbs"
        exit 1
    fi
    mkdir -p "$DB_DIR/genomad" "$DB_DIR/icefinder2"
    cp -r "$WORKDIR/genomad_db" "$DB_DIR/genomad/genomad_db_v1.9"
    cp -r "$WORKDIR/icf2_dbs" "$DB_DIR/icefinder2/icf2_dbs"
else
    echo "   already present, skipping"
fi

echo
echo "== Step 4: preprocess the CARD database for RGI (issue 6/4: --download_dbs only runs"
echo "   RGI_DOWNLOADDB, i.e. the raw card.json; RGI_MAIN needs the output of the separate"
echo "   RGI_CARDANNOTATION preprocessing step, which --download_dbs never runs) =="
if [ ! -f "$DB_DIR/rgi/card_database_processed/card.json" ]; then
    WORKDIR="$DB_DIR/rgi/card_annotation_work"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"
    RGI_IMG="$SINGULARITY_CACHE/depot.galaxyproject.org-singularity-rgi-6.0.5--pyh05cac1d_0.img"
    singularity exec --bind "$WORKDIR:$WORKDIR" --bind "$DB_DIR/rgi/card_dir:$DB_DIR/rgi/card_dir" --pwd "$WORKDIR" "$RGI_IMG" \
        rgi card_annotation -i "$DB_DIR/rgi/card_dir/card.json"
    mkdir -p "$DB_DIR/rgi/card_database_processed"
    mv "$WORKDIR"/card*.fasta "$DB_DIR/rgi/card_database_processed/"
    cp "$DB_DIR/rgi/card_dir"/* "$DB_DIR/rgi/card_database_processed/"
    cd - > /dev/null
    rmdir "$WORKDIR"
else
    echo "   already present, skipping"
fi

echo
echo "== Step 5: work around AMRFinderPlus's self-deleting mv (issue 5/4) =="
echo "   by pointing at a differently-named symlink to the same DB dir =="
if [ ! -e "$DB_DIR/amrfinderplus/amrfinderdb_data" ]; then
    ln -s "$DB_DIR/amrfinderplus/amrfinderdb" "$DB_DIR/amrfinderplus/amrfinderdb_data"
else
    echo "   already present, skipping"
fi

echo
echo "All databases ready under $DB_DIR"
echo "my_paths.config (already committed) points at all of the above -- no further action needed."
