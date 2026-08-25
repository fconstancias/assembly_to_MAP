#!/usr/bin/env bash
# Optional, heavy (~7GB download / ~17GB on disk): core InterProScan data, needed to run
# with --skip_sanntis false (real SanntiS BGC predictions). Not needed for the base test
# run in scripts/03 with --skip_sanntis true.
#
# Does NOT set up the licensed SignalP hook (see below) -- getting that also requires
# --interpro_licensed_software true in my_paths.config. SanntiS itself only needs the core
# `data/` databases handled by this script.
#
#   source scripts/00_env.sh && bash scripts/01b_download_interproscan.sh
set -euo pipefail

DB_DIR="/maps/projects/hansen_ol-AUDIT/scratch/mobilome_db"
IPS_VERSION="5.76-107.0"   # must match params.interproscan_db_version in my_paths.config
IPS_DIR="$DB_DIR/interproscan"
TARGET="$IPS_DIR/interproscan_db"

if [ -d "$TARGET/data" ]; then
    echo "Already present: $TARGET/data -- skipping"
else
    mkdir -p "$IPS_DIR"
    cd "$IPS_DIR"
    curl -L -o "interproscan-${IPS_VERSION}-64-bit.tar.gz" \
        "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/${IPS_VERSION}/interproscan-${IPS_VERSION}-64-bit.tar.gz"
    curl -L -o "interproscan-${IPS_VERSION}-64-bit.tar.gz.md5" \
        "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/${IPS_VERSION}/interproscan-${IPS_VERSION}-64-bit.tar.gz.md5"
    md5sum -c "interproscan-${IPS_VERSION}-64-bit.tar.gz.md5"
    tar -pxzf "interproscan-${IPS_VERSION}-64-bit.tar.gz"
    mv "interproscan-${IPS_VERSION}" "interproscan_db"
    rm "interproscan-${IPS_VERSION}-64-bit.tar.gz" "interproscan-${IPS_VERSION}-64-bit.tar.gz.md5"
fi

echo
echo "=================================================================================="
echo "SignalP (licensed, optional -- for the signalP column in the combined report):"
echo
echo "MAP's patched container (microbiome-informatics/interproscan:${IPS_VERSION}_patch1)"
echo "needs SignalP **4.1** specifically (legacy Perl), NOT SignalP 6 -- despite docs/usage.md"
echo "linking to the SignalP 6 page (see github_issue_drafts.md issue 9/4). Confirmed working"
echo "end to end with real SignalP 4.1:"
echo
echo "1. Get 'signalp-4.1g.Linux.tar.gz' from DTU's academic download portal"
echo "   (https://services.healthtech.dtu.dk/services/SignalP-4.1/) -- generates a personal,"
echo "   one-time download link; can't be scripted/hardcoded here."
echo "2. tar xzf signalp-4.1g.Linux.tar.gz"
echo "3. mv signalp-4.1 $TARGET/licensed/signalp"
echo "   (its signalp-4.1/{signalp,lib/} become licensed/signalp/{signalp,lib/} directly --"
echo "   exact match for interproscan.properties' binary.signalp.path /"
echo "   signalp.perl.library.dir, no shim/edit needed)"
echo "4. Set interpro_licensed_software = true in my_paths.config"
echo
echo "Not done by this script (needs the manual DTU download in step 1) -- this script only"
echo "sets up the core (unlicensed) data/ used by SanntiS."
echo "=================================================================================="
