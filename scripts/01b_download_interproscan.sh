#!/usr/bin/env bash
# Optional, heavy (~7GB download / ~17GB on disk): core InterProScan data, needed to run
# with --skip_sanntis false (real SanntiS BGC predictions). Not needed for the base test
# run in scripts/03 with --skip_sanntis true.
#
# Does NOT set up the licensed SignalP hook (see below) -- --interpro_licensed_software
# stays unset/false. SanntiS itself only needs the core `data/` databases.
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
echo "SignalP (licensed, optional -- for --interpro_licensed_software true later):"
echo
echo "MAP's patched container (microbiome-informatics/interproscan:${IPS_VERSION}_patch1)"
echo "hardwires its SignalP hook to legacy SignalP 4.1 (Perl), confirmed by inspecting"
echo "the container's interproscan.properties directly:"
echo "  binary.signalp.path=/opt/interproscan/licensed/signalp/signalp"
echo "  signalp.perl.library.dir=/opt/interproscan/licensed/signalp/lib"
echo
echo "SignalP 6 (the only version obtainable under academic license today -- Python/PyTorch,"
echo "not Perl) does NOT drop in here as-is; see github_issue_drafts.md issue 9/4. If/when"
echo "SignalP 4.1 is obtained separately, its extracted contents need to land at:"
echo "  $TARGET/licensed/signalp/signalp   (the executable)"
echo "  $TARGET/licensed/signalp/lib/      (its perl library dir)"
echo "then set interpro_licensed_software = true in my_paths.config. Not done yet -- this"
echo "script only sets up the core (unlicensed) data/ used by SanntiS."
echo "=================================================================================="
