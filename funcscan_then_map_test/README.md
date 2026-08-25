# funcscan → MAP: shared-gene-calling test

Tests the architecture decided in [`../CLAUDE.md`](../CLAUDE.md) open question 7: run
[nf-core/funcscan](https://github.com/nf-core/funcscan) (tag `4.0.0`) **first**, doing the
one gene-calling pass both pipelines need, then feed its protein predictions into
[MAP](../CLAUDE.md) instead of letting MAP re-call genes with its own Prodigal step. Same two
test assemblies as `../` (`megaS121` + `co728`, participant 728) for direct comparability.

**Why this order, not MAP-first**: either pipeline can supply the shared gene calls in
principle, but funcscan needs to run its own annotation step regardless to get contig/protein
IDs its AMR/AMP/BGC/CAZyme tools expect, whereas MAP explicitly supports *accepting* external
gene calls via its `proteins_gff`/`proteins_faa` samplesheet columns and is verified (by
reading `workflows/mobilomeannotation.nf` directly — see `../CLAUDE.md` item 7) to route
AMR/BGC/virulence annotation onto the **original, non-renamed** contig IDs when given them.
So: funcscan calls genes once (Pyrodigal, not Prokka — Prokka truncates/renames contig
headers via its 20-char locus-tag limit, which would break original-ID traceability), MAP
consumes that output, and everything downstream — from both pipelines — lands on our
original contig/gene IDs with no translation layer to build ourselves.

## Why this split of tools, not "run both pipelines in full"

| Category | Runs via | Why |
|---|---|---|
| MGE, plasmid/virus, virulence | MAP only | funcscan has no equivalent at all |
| BGC: antiSMASH, GECCO | MAP only | `bgc_skip_*` in funcscan — antiSMASH alone ran ~3h on `co728` in `../`, not worth doubling |
| AMR: **all 5** (ABRicate, AMRFinderPlus, fARGene, RGI, DeepARG) + argNorm | **both** — funcscan (all 5) *and* MAP (AMRFinderPlus/RGI/DeepARG) | decided 2026-08-25: run the full ARG set in funcscan too, even though 3 of the 5 duplicate MAP, specifically to get **one hAMRonization table covering all 5 tools in a single normalized schema** — MAP's own `combined_report.tsv` only lists each hit with a bare `amr_tool` field, no cross-tool harmonization. These 3 tools are individually cheap (unlike antiSMASH), so the redundant compute is an acceptable trade for that. |
| BGC: DeepBGC | funcscan only | zero overlap tool |
| AMP screening (ampir, Macrel, AMPlify) | funcscan only | MAP has zero AMP coverage |
| CAZymes (dbCAN) | funcscan only | MAP has zero CAZyme coverage |
| Gene calling | funcscan's Pyrodigal, fed to MAP | avoids double gene-calling; see above for why this makes MAP preserve original IDs |

BiG-SLiCE (`bgc_run_bigslice`) is opt-in in funcscan and off by default — not explicitly
disabled, just never turned on, so nothing to do there.

## Steps

```bash
source scripts/00_env.sh
bash scripts/00b_apply_local_patches.sh  # one-time: patches/ applied to funcscan itself
bash scripts/01_run_funcscan.sh          # ARG(full)/AMP/BGC(partial)/CAZyme screening
# scripts/02_prep_map_input.sh           # TODO once step 1's real output paths are known
# scripts/03_run_map.sh                  # TODO
```

**Status (2026-08-25): step 1 running.** Gene-calling (Pyrodigal) completed and verified for
both samples early on — confirmed below, this is no longer an open question. ARG (all 5
tools) and part of CAZyme/BGC/AMP have also completed; the rest is still in progress as of
this writing (see `nohup_funcscan.log`). Hit one real bug along the way —
`ampcombi_download.py` crashing on a NaN row in DRAMP's live TSV export — fixed via
`patches/ampcombi_download_nan_sequence_fix.patch`, full writeup in
[`github_issue_drafts.md`](github_issue_drafts.md) (this directory's own, separate from
`../github_issue_drafts.md` which is MAP-specific). Steps 2-3
aren't written yet — writing them requires seeing funcscan's actual Pyrodigal output paths
in full (already partially inspected, see below) and confirming the rest of the run's output
layout first, same lesson as MAP's own docs earlier in `../`. Plan once step 1 completes:

1. Locate funcscan's per-sample Pyrodigal `.faa` and `.gff` in `results/01_funcscan_participant728/`.
2. Confirm contig IDs in that GFF match the *original* `megaS121_fixed.fa`/`co728_fixed.fa`
   headers (not renamed) — this is the entire premise of the test; verify it before trusting it.
3. Build a MAP samplesheet with `proteins_gff`/`proteins_faa` pointing at those files (MAP's
   own samplesheet columns: `sample,assembly,proteins_gff,proteins_faa,virify_gff,interproscan_tsv`).
4. Run MAP (reusing `../nextflow.config`/`../my_paths.config`/`../scripts/02_apply_local_patches.sh`
   patches — same DBs, same fixes, no need to redo any of that setup) against this new
   samplesheet, into a separate `results/02_map_participant728/` here (not `../results/`, to
   keep this comparison test's outputs separate from the baseline MAP-only run).
5. Compare `../results/01_map_test_participant728/*/combined_report.tsv` (MAP-only,
   `contig_N` IDs) against this run's combined report (should have original contig IDs) for
   the same AMR/virulence/MGE calls, to confirm the shared-gene-calling handoff didn't change
   MAP's own results — only its ID scheme and its added funcscan columns.

## Verified so far

- **Original contig IDs preserved, confirmed by reading the actual output** (not assumed):
  Pyrodigal's GFF for `megaS121` uses `seqhdr="megaS121_000000000013"` — the real original
  contig ID from the source FASTA, not a renamed scheme. Gene IDs are
  `<original_contig_id>_<n>` (e.g. `megaS121_000000000013_1`). The whole premise of this test
  holds.
- Both samples' Pyrodigal (`PYRODIGAL_GFF`/`PYRODIGAL_GBK`) completed successfully — this is
  the one step everything else in this test depends on, and it's done.

## Open questions / still to verify

- Does funcscan's Pyrodigal step run genome-wide (matching MAP's own Prodigal scope) or does
  it restrict to specific contig length cutoffs the way MAP's `RENAME` does (1kb/5kb/100kb)?
  If different, gene sets between the two pipelines won't match exactly. (Contig-ID format is
  now confirmed per above; this is specifically about *which* contigs get genes called, not
  what they're named.)
- Exact GFF attribute style Pyrodigal produces (seen directly, e.g. `partial=`/`start_type=`/
  `rbs_motif=`/`conf=`/`score=` fields) — still need to confirm MAP's `proteins_gff` parser
  ("PROKKA or equivalent") tolerates these extra attributes rather than expecting a stricter
  Prodigal-only format.
- DB placement: `--save_db` puts everything in this run's own `results/` first (funcscan has
  no separate `--download_dbs`-style pre-fetch mode like MAP) — move to a shared
  `scratch/funcscan_db/` afterward per this project's DB convention, same as `../mobilome_db/`.
