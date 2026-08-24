# Running MAP (mobilome-annotation-pipeline) for assembly_to_MGE

This directory runs [EBI-Metagenomics/mobilome-annotation-pipeline](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline)
(MAP) — see [CLAUDE.md](CLAUDE.md) for why it was picked and what it does/doesn't cover.

Cluster: esrum (Slurm). Account `cbmr`, partition `standardqueue` (see
[nextflow.config](nextflow.config)).

## Reproducing this from scratch

Everything needed to redo this end to end is checked into this repo — run in order:

```bash
source scripts/00_env.sh                       # modules + TMPDIR fix, every time
bash scripts/01_download_databases.sh          # one-time: DBs + all 5 DB-level fixups
bash scripts/02_apply_local_patches.sh         # one-time: patches/ applied to MAP itself
bash scripts/03_run_test_participant728.sh     # the actual run (safe to re-run, -resume)
```

- [`nextflow.config`](nextflow.config) + [`my_paths.config`](my_paths.config) — Slurm/Singularity
  setup and every resolved DB path (both required on every run, both already committed;
  `scripts/03_run_test_participant728.sh` passes both via `-c`).
- [`patches/`](patches/) — the one real code fix (PathoFact2's 200-line GFF-scan cap,
  issue 7/4) as a clean `git apply`-able diff against MAP `v5.0.0`, not a full forked
  clone — see `scripts/02_apply_local_patches.sh`'s docstring for exactly where and how
  it needs to be applied (this one has real gotchas around Nextflow's resume cache, worth
  reading before assuming a plain re-run picks it up).
- Everything else broken in MAP itself (issues 1–6 in [github_issue_drafts.md](github_issue_drafts.md))
  is a database-path or database-content problem, not a code problem — fully handled by
  `scripts/01_download_databases.sh`, nothing to patch.
- If you change any script here, keep it in `scripts/` and commit it — this section is the
  contract for "how to redo this," so it needs to stay runnable, not just documented in prose.

The sections below explain *why* each piece exists and go into troubleshooting depth; the
scripts above are the actual up-to-date commands to run.

## Environment

Every `nextflow run` in this directory needs these three modules loaded first
(nextflow needs a JDK; MAP's tools run in Singularity containers, not conda):

```bash
module load openjdk/20.0.0
module load nextflow/25.10.4
module load singularity/3.8.7
```

No other env vars are required — the Singularity image cache is pinned in
[nextflow.config](nextflow.config) (`singularity.cacheDir`) to the shared
`/maps/projects/hansen_ol-AUDIT/scratch/singularity_cache`, following this project's
convention of keeping large reused artifacts directly under `scratch/` rather than
per-module (see CLAUDE.md's "Shared resource DB convention").

Run everything from this directory (`assembly_to_MGE/`) so `-c nextflow.config` resolves;
`nextflow.config` sets `process.executor = 'slurm'` with the account/queue above, so plain
`nextflow run ...` on the login node submits each task as its own Slurm job — same pattern
already used for the earlier `nf-core/mag` run in `../` (see `../.nextflow.log`).

## 1. One-time: download MAP's reference databases

Shared across future runs/projects, kept under `scratch/` (not in this module) per the DB
convention:

```bash
nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 \
    --download_dbs /maps/projects/hansen_ol-AUDIT/scratch/mobilome_db \
    -c nextflow.config \
    -profile singularity \
    -with-trace db_download_trace.txt \
    -name map_db_download
```

Pinned to tag `v5.0.0` (latest release as of 2026-08-24) for reproducibility — the CLAUDE.md
notes were verified against this pipeline version's code, not just its docs.

This downloads geNomad, CheckV, ICEfinder2-lite, PathoFact2 models, VFDB (DIAMOND db), CDD,
AMRFinderPlus DB, DeepARG DB, CARD (RGI), and antiSMASH DB in parallel, then is *supposed to*
print a ready-to-paste `params { ... }` config block with the exact resolved paths. On this
run that final summary crashed (see troubleshooting below) — all ten DBs downloaded
correctly regardless (verified directly on disk), so [my_paths.config](my_paths.config) was
hand-built from the actual `scratch/mobilome_db/` layout instead and **is committed here**
(unlike a normal `--download_dbs` run, where it's machine/run-specific scratch output you'd
regenerate yourself). Pass it with `-c my_paths.config` on every subsequent run. InterProScan
(~100 GB) is intentionally not downloaded — only needed for SanntiS BGC prediction, MAP runs
IPS internally when needed and the pipeline works fine without a pre-fetched copy.

**Status: done (2026-08-24)** — `scratch/mobilome_db/` has all 10 databases; two needed
manual intervention around upstream MAP bugs (see troubleshooting below).

## 2. Test run (first trial): one single assembly + its covering coassembly

Both from participant `728` (see `sample_infos.tsv` — samples `S_111, S_117, S_121, S_128,
S_137, S_146, S_160, S_162, S_165, S_187, S_193, S_196, S_198`):

- `megaS121` — single-sample megahit assembly of `S_121` alone
  (`../BINNING/01_ANVIO_DBs/megaS121/megaS121_fixed.fa`)
- `co728` — megahit coassembly of **all** participant 728 samples, including `S_121`
  (`../BINNING/01_ANVIO_DBs/co728/co728_fixed.fa`)

Samplesheet: [samplesheet_participant728_test.csv](samplesheet_participant728_test.csv)
(only `sample`+`assembly` columns filled in — MAP runs its own Prodigal/ARAGORN gene
prediction since we're not supplying `proteins_gff`/`proteins_faa`).

```bash
nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 \
    --input samplesheet_participant728_test.csv \
    --outdir results/01_map_test_participant728 \
    --skip_sanntis true \
    -c nextflow.config \
    -c my_paths.config \
    -profile singularity \
    -with-trace map_test_trace.txt \
    -name map_test_participant728
```

`--skip_sanntis true` is required here since InterProScan (`params.interproscan_db`) wasn't
downloaded (see step 1) — without it, or without skipping SanntiS, MAP crashes immediately
with `Argument of file() function cannot be null` (`workflows/mobilomeannotation.nf:318`).
Every other DB path SanntiS/BGC/AMR/PathoFact2 need is covered by `my_paths.config`;
InterProScan is the one MAP will still try to use unless told not to.

Purpose: compare geNomad/MGE/AMR/VF/BGC calls for the same participant's data assembled two
ways, and sanity-check the pipeline end to end on real (if small-ish) data before committing
to a full-cohort run. `megaS121` is the smaller of the two (~96 MB, 10.7k contigs); `co728`
is the coassembly (~326 MB, 46.4k contigs).

## Contig IDs: MAP discards your assembly's original naming

MAP's `RENAME` step (`bin/assembly_filter_rename.py`) rewrites every contig to a bare
sequential `contig_1`, `contig_2`, ... in **all** of its outputs (GFFs, `<sample>_combined_report.tsv`)
— even though the input FASTAs we feed it already carry the traceable, assembly-specific
naming this project's binning pipeline builds (`megaS121_000000000007`, `co728_000000000004`,
...). The original ID is preserved *only* in a side file, `preprocessing/<sample>_contigID.map`
(`contig_N	<original_id>`), which nothing downstream reads automatically.

**Consequence for integration**: any join back to this project's own naming, `bin_map.tsv`,
MAG assignment, or GTDB-Tk taxonomy has to go through `<sample>_contigID.map` first —
`combined_report.tsv`'s `contig_id` column is MAP's disposable `contig_N`, not ours. When
building the `10_integration/` tables described in [CLAUDE.md](CLAUDE.md), treat
`contigID.map` as a required join key alongside `bin_map.tsv`, not an optional lookup.

## Optional: MAP's own nf-test suite

Only meaningful if you clone the repo locally (nf-test runs from within a checkout, unlike
the `nextflow run EBI-Metagenomics/...` form above which pulls automatically):

```bash
git clone --branch v5.0.0 https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline.git
cd mobilome-annotation-pipeline
nf-test test --profile test,singularity   # ~10 min, pre-trimmed test DBs, no download step needed
```

Tags to run a subset: `--tag positive` (mobilome-only detection), `--tag negative` (no-MGE
assembly, expects empty output), `--tag pathofact` (full functional-annotation report).
Not run yet in this project — real-data test above was prioritized instead.

## Monitoring / troubleshooting

- `squeue -u $USER` — see submitted Slurm tasks (nextflow submits one job per pipeline task).
- `.nextflow.log` (in whichever directory the run was launched from) — full execution log.
- Resume a failed/interrupted run by re-adding `-resume` to the same command — nextflow
  reuses cached results for unchanged tasks via `work/`. If you get `Unable to acquire lock
  on session with ID ...`, an earlier invocation's Nextflow head process (a `java` process,
  not necessarily a Slurm job — check `ps aux | grep nextflow`, not just `squeue`) is still
  alive finishing up; wait for it to exit rather than force-killing it, then resume.
- **`unset TMPDIR` before every `nextflow run`** if launching from an interactive/agent shell
  that sets it to something non-standard (e.g. `/scratch/tmp/`) — Singularity passes host env
  vars into the container by default, and at least `amrfinder_update` fails with `Error
  creating a temporary directory in /scratch/tmp/` if that path doesn't exist inside the
  container. Not an issue in a normal login-node shell, only came up because this project's
  setup was driven from a Claude Code sandbox session with its own `TMPDIR`.
- **Known upstream bug in MAP v5.0.0**: `DOWNLOAD_DATABASES:DB_DOWNLOAD_VFDB` always fails
  (exit 127, `curl: command not found`) — its script calls `curl`, but its container
  (`diamond:2.1.16--h13889ed_0`) only ships `wget`. Worked around via `errorStrategy =
  'ignore'` for that process in `nextflow.config`, plus building
  `scratch/mobilome_db/virulence/VFDB_setB_pro.dmnd` by hand:
  ```bash
  curl -L -o VFDB_setB_pro.fas.gz https://www.mgc.ac.cn/VFs/Down/VFDB_setB_pro.fas.gz
  singularity exec --bind "$PWD:$PWD" --pwd "$PWD" \
      /maps/projects/hansen_ol-AUDIT/scratch/singularity_cache/depot.galaxyproject.org-singularity-diamond-2.1.16--h13889ed_0.img \
      diamond makedb --threads 4 --in VFDB_setB_pro.fas.gz -d VFDB_setB_pro
  rm VFDB_setB_pro.fas.gz
  ```
  When `--download_dbs` finishes and prints its `params { ... }` block for `my_paths.config`,
  manually set/replace `virulencefactors_db` to point at this file rather than whatever (if
  anything) the broken step would have produced.
- **`icefinder_hmm_models` needs the `.hmm` in its path**: this DB bundle's pressed HMMER
  index files are named `icescan.hmm.h3f/h3i/h3m/h3p` (not `icescan.h3*`), so the config value
  must be `.../icehmm/icescan.hmm`, not `.../icehmm/icescan` as the docs' own template
  implies — otherwise `HMMSCAN` fails with `HMM file icescan not found`. Always verify against
  the actual filenames in `scratch/mobilome_db/icefinder2/icf2_dbs/icehmm/` rather than
  trusting the template literally.
- **`deeparg_db_version` / `deeparg_model` / `deeparg_tool_version` have no default anywhere**
  in MAP, not even in its own printed config template, but are required — left null, DeepARG's
  report step crashes with `A process input channel evaluates to null`. Set explicitly in
  `my_paths.config` (`model = "LS"` since our input is Prodigal-predicted proteins, not raw
  reads; `tool_version = "1.0.4"` matching the pinned container).
- **`amrfinderplus_db` must NOT be named literally `amrfinderdb`**, even though that's exactly
  what MAP's own docs template recommends. `AMRFINDERPLUS_RUN`'s script does
  `mv ${db} amrfinderdb`; if the staged input is already named `amrfinderdb` this is a
  same-path self-move which *silently deletes the symlink* (verified empirically — exit 0,
  no error, symlink just gone) rather than being a no-op. `amrfinder` then fails with
  `directory ... not found: amrfinderdb`. Fixed by pointing `--amrfinderplus_db` at a
  second, differently-named symlink to the same directory
  (`scratch/mobilome_db/amrfinderplus/amrfinderdb_data`) instead of the directory itself.
  This is a vendored nf-core/modules component, so likely affects other pipelines too.
- **`rgi_db` needs manual preprocessing that `--download_dbs` never runs**: `--download_dbs`
  only calls `RGI_DOWNLOADDB` (raw `card.json`), never `RGI_CARDANNOTATION` (which builds
  `card_database_v*.fasta`/`..._all.fasta`) — but `AMR_ANNOTATION`'s logic for an
  externally-supplied `--rgi_db` skips preprocessing entirely and assumes the directory is
  already the processed output (the code that would auto-detect and preprocess a raw dir is
  commented out). Fixed by running `rgi card_annotation -i card_dir/card.json` by hand via the
  cached RGI container and assembling the result into
  `scratch/mobilome_db/rgi/card_database_processed/`, pointed at by `rgi_db` instead of the
  raw `card_dir`.
- **PathoFact2's final virulence GFF is silently empty for real data (high-severity, unresolved)**:
  `pathofact2_integrator.py`'s GFF-validity check (`_has_gff_record_9cols`) only scans the
  first 200 lines of the input GFF. Since every `##sequence-region` pragma line (one per
  contig) is written before any feature line, any assembly with >~200 contigs — i.e.
  essentially every real single-sample or coassembly dataset, confirmed on both `megaS121`
  (10.7k contigs) and `co728` (46.4k contigs) — has its first real feature line past line 200,
  so the check always (wrongly) concludes the GFF has zero features. The task "succeeds" (exit
  0, `optional: true` output) and silently produces no `prediction/virulence/*_pathofact2.gff`
  and no `vf`/`tox_prob` contributions to `sample_combined_report.tsv`, even though
  `PATHOFACT2_TOXINS`/`PATHOFACT2_VIRULENCE` (the actual ML predictions) run and succeed —
  the predictions exist but never get merged in. No workaround applied yet; needs an upstream
  fix (drop or raise the 200-line cap in `pathofact2_integrator.py`). **Bottom line: treat
  PathoFact2 virulence/toxin integration as broken for real data on this pipeline version
  until this is fixed.**
- **SignalP is IPS-only in this pipeline, but PathoFact2 itself doesn't need IPS for it**:
  PathoFact2's own README documents a native, standalone SignalP6 integration (optional
  install step, dedicated `SignalP/<sample>/{AMR,TOX,VF}/` output) with zero mention of
  InterProScan anywhere. MAP instead sources the `signalP` combined-report column exclusively
  from InterProScan (~100GB DB) rather than exposing PathoFact2's own lighter-weight SignalP6
  step — worth asking upstream whether that's deliberate.
- `work/` will accumulate per-task scratch directories; safe to `nextflow clean -f` once a
  run's outputs in `results/` are confirmed good, ordinary nf-core-pipeline practice, not
  needed for the test run above given the small assemblies involved.
