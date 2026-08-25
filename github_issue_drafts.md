# Draft GitHub issues for EBI-Metagenomics/mobilome-annotation-pipeline

Four separate issues, one per root cause, found running MAP v5.0.0 (tag `v5.0.0`, revision
`da3177576d`) end to end for the first time (`--download_dbs` + a real `--input` run) on an
HPC cluster with Nextflow 25.10.4 + Singularity 3.8.7. Each is reproducible from a clean
checkout; copy/paste each section as its own issue at
https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/issues/new

---

## Issue 1/4

**Title:** `DB_DOWNLOAD_VFDB` fails with `curl: command not found` — script uses curl, container only ships wget

**Body:**

`--download_dbs` always fails on the VFDB step:

```
nextflow run EBI-Metagenomics/mobilome-annotation-pipeline -r v5.0.0 \
    --download_dbs /path/to/dbs -profile singularity
```

```
Command error:
  .command.sh: line 2: curl: command not found

Command exit status:
  127
```

**Root cause:** [`modules/local/db_download_vfdb.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/local/db_download_vfdb.nf)'s script calls `curl -L -o VFDB_setB_pro.fas.gz ...`, but the process container is `depot.galaxyproject.org/singularity/diamond:2.1.16--h13889ed_0`, which only ships `wget` (confirmed directly: `singularity exec <diamond image> which curl wget` → only `wget` found; no `curl`, `python3`, or `python` either).

**Suggested fix:** swap `curl -L -o <file> <url>` for `wget -O <file> <url>` — consistent with the wget-based approach already used in [`db_download_mobilome_dbs.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/local/db_download_mobilome_dbs.nf), which correctly uses `wget` against a container that has it.

**Workaround used:** set `errorStrategy = 'ignore'` for this process and built `VFDB_setB_pro.dmnd` by hand (`curl` on the host + `diamond makedb` via the same cached container), then pointed `--virulencefactors_db` at that file directly.

---

## Issue 2/4

**Title:** `DB_DOWNLOAD_MOBILOME_DBS` reports "missing output" `genomad_db_v1.9/` even though the download/extraction succeeds — tarball's internal folder is named `genomad_db/`, not `genomad_db_v1.9/`

**Body:**

Same `--download_dbs` run as above; after VFDB is worked around, this is the next failure:

```
ERROR ~ Error executing process > 'DOWNLOAD_DATABASES:DB_DOWNLOAD_MOBILOME_DBS'
Caused by:
  Missing output file(s) `genomad_db_v1.9/` expected by process `DOWNLOAD_DATABASES:DB_DOWNLOAD_MOBILOME_DBS`
Command exit status:
  0
```

The command itself succeeds (`wget` reports the full 842023773/842023773 bytes, 100%, and `tar -xzf` runs without error) — the task's declared output path just doesn't match what actually lands on disk. Inspecting the work directory directly shows the extracted geNomad DB is a fully valid, complete database, just under a directory literally named `genomad_db/`, not `genomad_db_v1.9/`:

```
$ ls work/<hash>/genomad_db/
genomad_db  genomad_db.dbtype  genomad_db_h  genomad_db_h.dbtype  genomad_db_h.index
genomad_db.index  genomad_db.lookup  genomad_db_mapping  genomad_db.source
genomad_db_taxonomy  genomad_integrase_db  ...  version.txt
```

**Root cause:** [`modules/local/db_download_mobilome_dbs.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/local/db_download_mobilome_dbs.nf) downloads `genomad_db_v1.9.tar.gz` from Zenodo and declares `output: path "genomad_db_v1.9/"`, but the archive's internal top-level directory (as geNomad itself names it) is just `genomad_db/`. The version suffix is only in the *tarball's filename*, not the extracted folder name.

**Suggested fix:** add `mv genomad_db genomad_db_v1.9` (or equivalent) after the `tar -xzf` step, or change the declared output to match the actual extracted name.

**Workaround used:** rescued the already-correctly-downloaded data from the task's work directory by hand, `cp -r work/<hash>/genomad_db  <dbdir>/genomad/genomad_db_v1.9`, and set `errorStrategy = 'ignore'` for this process so the rest of `--download_dbs` could still complete.

---

## Issue 3/4

**Title:** `deeparg_db_version`, `deeparg_model`, `deeparg_tool_version` have no default anywhere (not even in the `--download_dbs` printed config template) but are required — null crashes AMR_ANNOTATION

**Body:**

A normal real-data run (`--input samplesheet.csv`, `skip_deeparg` left at its default `false`) crashes:

```
ERROR ~ A process input channel evaluates to null -- Invalid declaration `val software_version`
 -- Check script '.../subworkflows/ebi-metagenomics/amr_annotation/main.nf' at line: 126
```

**Root cause:** `nextflow.config` sets these three to `null` with no default:

```
deeparg_db_version   = null
deeparg_model        = null
deeparg_tool_version = null
```

They're required inputs to `HAMRONIZATION_DEEPARG` inside [`subworkflows/ebi-metagenomics/amr_annotation/main.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/subworkflows/ebi-metagenomics/amr_annotation/main.nf#L126), but critically: **the `params { ... }` config block that `--download_dbs` prints for users to paste into `my_paths.config` (documented in `docs/usage.md`) only includes `deeparg_db` — not these three.** So following the documented workflow exactly (`--download_dbs` → paste the printed block → run) still crashes on the very first real run, for anyone not passing `--skip_deeparg true`.

**Suggested fix:** either give these three real defaults in `nextflow.config` (e.g. `deeparg_tool_version = "1.0.4"`, matching the pinned container tag in [`modules/nf-core/deeparg/downloaddata/main.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/nf-core/deeparg/downloaddata/main.nf)), or have `--download_dbs`'s printed config template include all three explicitly so users aren't silently missing required params.

**Workaround used:** set `deeparg_db_version = 1`, `deeparg_model = "LS"` (genes/proteins, matching Prodigal-predicted-protein input rather than raw reads), `deeparg_tool_version = "1.0.4"` in `my_paths.config`.

---

## Issue 4/4

**Title:** `icefinder_hmm_models` config path in docs doesn't match the actual DB bundle's filenames — HMMSCAN fails with "HMM file ... not found"

**Body:**

Using the documented config path convention for `icefinder_hmm_models` (`docs/usage.md`'s printed template: `"/path/to/dbs/icefinder2/icf2_dbs/icehmm/icescan"`) against the DB bundle `--download_dbs` itself produces (from `ftp://ftp.ebi.ac.uk/pub/databases/metagenomics/pipelines/tool-dbs/icefinder2lite/icf2_dbs.tar.gz`), the very first `ICEFINDER2_LITE:HMMSCAN` task fails:

```
Command error:
  Error: File existence/permissions problem in trying to open HMM file icescan.
  HMM file icescan not found (nor an .h3m binary of it); also looked in PFAMDB
```

**Root cause:** the pressed HMMER3 index files this DB bundle actually ships are named `icescan.hmm.h3f`, `icescan.hmm.h3i`, `icescan.hmm.h3m`, `icescan.hmm.h3p` (plus `icescan.hmm.gz`) — i.e. the basename prefix is `icescan.hmm`, not `icescan`. [`workflows/mobilomeannotation.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/workflows/mobilomeannotation.nf#L141) stages files via `channel.fromPath("${params.icefinder_hmm_models}.*")` and passes `file(params.icefinder_hmm_models).name` as the literal argument to `hmmscan`, which requires that argument to exactly match the `.h3*` files' prefix. With the documented `.../icehmm/icescan` path, `hmmscan` is invoked with basename `icescan`, which doesn't match any of the staged `icescan.hmm.h3*` files.

**Suggested fix:** either correct the documented template path to `.../icehmm/icescan.hmm` (matches the DB bundle as currently packaged), or repackage/rename the `icf2_dbs.tar.gz` bundle's files to drop the `.hmm` infix so they match the documented `icescan` convention.

**Workaround used:** set `icefinder_hmm_models = ".../icf2_dbs/icehmm/icescan.hmm"` (verified against the actual filenames with `ls`).

---

## Issue 5/4 (bonus — likely belongs upstream in nf-core/modules too)

**Title:** `AMRFINDERPLUS_RUN` deletes its own staged DB when the input basename is literally `amrfinderdb` (as MAP's own docs recommend naming it) — `mv $db amrfinderdb` self-move silently removes the symlink

**Body:**

Following MAP's own documented `my_paths.config` convention exactly —

```
amrfinderplus_db = "/path/to/dbs/amrfinderplus/amrfinderdb"
```

(i.e. naming the directory `amrfinderdb`, as the docs' printed template does) — makes `AMRFINDERPLUS_RUN` fail on every sample:

```
Command error:
  ...
  *** ERROR ***
  No valid AMRFinder database is found.
  This directory (or symbolic link to directory) is not found: amrfinderdb
```

**Root cause:** [`modules/nf-core/amrfinderplus/run/main.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/nf-core/amrfinderplus/run/main.nf) (a vendored nf-core/modules component) does:

```
if [ "${is_compressed_db}" == "true" ]; then
    mkdir amrfinderdb
    tar xzvf ${db} -C amrfinderdb
else
    mv ${db} amrfinderdb
fi
```

Nextflow stages `db` into the task directory as a symlink named after its own basename (`nxf_stage()`: `ln -s <real path> amrfinderdb`, since our directory is itself named `amrfinderdb`). The script then runs `mv amrfinderdb amrfinderdb` — source and destination are the *same literal path*. Verified empirically outside the pipeline that this is not a no-op:

```
$ mkdir realdir && ln -s "$PWD/realdir" mylink
$ mv mylink mylink; echo "exit: $?"
exit: 0
$ ls
realdir          # mylink is gone — silently deleted, no error
```

So any run where the AMRFinderPlus DB directory happens to already be named `amrfinderdb` (exactly what this pipeline's own docs recommend) loses its DB input with no error until `amrfinder` itself complains it can't find the directory.

**Suggested fix:** guard the `mv` with a same-path check (`[ "$(readlink -f ${db})" != "$(readlink -f amrfinderdb)" ] && mv ${db} amrfinderdb || true`), or stage explicitly under a fixed different name (`path db, stageAs: 'db_input'` on the input declaration) so the `mv` target never collides with the source. Since this module is a vendored copy of an nf-core/modules component, the same bug likely affects other pipelines using it (e.g. nf-core/funcscan) whenever a user's AMRFinderPlus DB directory happens to be named `amrfinderdb` — worth checking/reporting upstream in nf-core/modules too, not just here.

**Workaround used:** created a second symlink with a different basename pointing at the same DB directory (`amrfinderdb_data -> amrfinderdb`) and pointed `--amrfinderplus_db` at that instead, so the `mv` becomes a real (non-colliding) rename.

---

## Issue 6/4 (also bonus — `--download_dbs` / `--rgi_db` mismatch)

**Title:** `--download_dbs` publishes RGI's raw `card.json`, but `AMR_ANNOTATION` assumes an externally-supplied `--rgi_db` is already the fully preprocessed `card_database_processed/` — `RGI_MAIN` fails with a missing-file glob

**Body:**

Pointing `--rgi_db` at exactly what `--download_dbs` publishes (the RGI DB directory it downloads) makes `RGI_MAIN` fail on every sample:

```
Command executed:
  DB_VERSION=$(ls card_dir/card_database_*_all.fasta | sed "...")
  rgi load --card_json card_dir/card.json --debug --local \
      --card_annotation card_dir/card_database_v$DB_VERSION.fasta \
      --card_annotation_all_models card_dir/card_database_v$DB_VERSION\_all.fasta
```

fails immediately because `card_dir/` only contains `card.json` — no `card_database_*.fasta` files exist to glob.

**Root cause, two-sided:**

1. [`subworkflows/local/download_databases.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/subworkflows/local/download_databases.nf) calls only `RGI_DOWNLOADDB()` for `--download_dbs` — it never calls `RGI_CARDANNOTATION`, so the published `rgi_db` directory is always just the raw `card.json`.
2. [`subworkflows/ebi-metagenomics/amr_annotation/main.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/subworkflows/ebi-metagenomics/amr_annotation/main.nf#L74-L91)'s RGI branch, when a user supplies `ch_rgi_db` externally, does `card = ch_rgi_db` directly with **no preprocessing** — the commented-out code right above it shows this was clearly intended at some point (`//if (!rgi_db.contains("card_database_processed")) { RGI_CARDANNOTATION(rgi_db) ... }`) but is currently dead:

```groovy
else {
    // Use user-supplied database
    //rgi_db = ch_rgi_db
    //if (!rgi_db.contains("card_database_processed")) {
    //    RGI_CARDANNOTATION(rgi_db)
    //    card = RGI_CARDANNOTATION.out.db
    //    ch_versions = ch_versions.mix(RGI_CARDANNOTATION.out.versions.first())
    //}
    //else {
    card = ch_rgi_db
    //}
}
```

So the DB `--download_dbs` produces and the DB `--rgi_db` requires are two different things, and nothing in the pipeline bridges them.

**Suggested fix:** either uncomment/restore the auto-preprocessing branch in `amr_annotation/main.nf` (detecting a raw vs. processed dir, e.g. by checking for `card_database_processed` in the path or checking whether `card_database_*.fasta` exists), or have `download_databases.nf` call `RGI_CARDANNOTATION` after `RGI_DOWNLOADDB` and publish *that* as the `rgi_db` path in its printed config template instead.

**Workaround used:** ran `rgi card_annotation -i card_dir/card.json` by hand via the cached RGI container (`depot.galaxyproject.org/singularity/rgi:6.0.5--pyh05cac1d_0`), matching `RGI_CARDANNOTATION`'s own script exactly, then assembled `card_database_processed/` (fasta outputs + a copy of `card.json`) and pointed `--rgi_db` at that instead.

---

## Issue 9/4 — MAP's patched InterProScan container's SignalP hook is wired for SignalP 4.1, but only SignalP 6 is obtainable under academic license today

**Title:** `interproscan.properties` in `microbiome-informatics/interproscan:5.76-107.0_patch1` hardwires `binary.signalp.path`/`signalp.perl.library.dir` to a legacy Perl SignalP 4.1 layout — incompatible with SignalP 6, the only version DTU still distributes under academic license

**Body:**

`--interpro_licensed_software true` is documented (`docs/usage.md`) as the flag that adds SignalP into MAP's internal InterProScan run. Inspecting the actual patched container MAP uses (`quay.io/microbiome-informatics/interproscan:5.76-107.0_patch1`) directly:

```
$ singularity exec ips_container.img grep -i signalp /opt/interproscan/interproscan.properties
binary.signalp.path=/opt/interproscan/licensed/signalp/signalp
signalp.perl.library.dir=/opt/interproscan/licensed/signalp/lib
```

This is InterProScan's legacy **SignalP 4.1** integration convention: a Perl script named `signalp` plus a `lib/` directory of Perl modules. But the SignalP obtainable today from [DTU's academic download portal](https://services.healthtech.dtu.dk/services/SignalP-6.0/) is **SignalP 6** — a `pip install`-able Python package built on PyTorch (`signalp6_fast/signalp-6-package/{setup.py,signalp/predict.py,models/*.pt}`), with a completely different CLI and I/O format. It is not drop-in compatible with what `interproscan.properties` expects, and the mismatch isn't superficial (different language, different runtime, different invocation) — a correct fix means either (a) a translation shim at `licensed/signalp/signalp` that reimplements the expected legacy interface on top of SignalP 6 and produces output IPS's Perl integration code can still parse, or (b) updating the container's InterProScan build/config to call SignalP 6 the way IPS itself does in its newer releases (if any), rather than the SignalP-4.1-era hook. Neither is a config change on the pipeline-user side.

Checked other public EBI-Metagenomics pipelines for a working reference (e.g. `mettannotator`, which also runs InterProScan) — its `INTERPROSCAN` module doesn't wire in licensed software at all (`modules/local/interproscan.nf` only mounts `${interproscan_db}/data`), so there's no existing example anywhere in EBI's public pipelines of this hook actually working end-to-end.

**Reproduce:** download core InterProScan 5.76-107.0 data (`--download_dbs` doesn't cover this — fully manual, see `docs/usage.md`), obtain SignalP 6 under academic license, set `--interpro_licensed_software true` with `licensed/signalp/` populated from the SignalP 6 tarball, run any sample. Either it fails outright (wrong binary name/interface) or — worse — appears to run but silently produces no/wrong SignalP calls, since the Perl-vs-Python mismatch isn't something IPS's own error handling is likely to catch cleanly.

**Suggested fix:** update the `_patch1` container's SignalP integration to target SignalP 6 (matching what's actually available under license now), or clearly document in `docs/usage.md` that `--interpro_licensed_software true` currently requires the no-longer-generally-distributed SignalP 4.1, not the current SignalP 6.

**Workaround used:** none — deliberately left `--interpro_licensed_software` unset/false. SanntiS BGC prediction itself only needs the core (unlicensed) `data/` databases, so real BGC results are still obtainable; only the `signalP` combined-report column is affected.

---

## Issue 7/4 — high severity: PathoFact2's final virulence GFF is silently empty for any real assembly

**Title:** `pathofact2_integrator.py`'s GFF validity check only scans the first 200 lines — silently produces no output for any assembly with >~200 contigs (i.e. basically all real metagenome assemblies)

**Body:**

On both a single-sample assembly (10,697 contigs) and a coassembly (46,391 contigs), `PATHOFACT2_INTEGRATOR` "succeeds" (exit 0) but produces no `*_pathofact2.gff` at all:

```
INFO - GFF has no valid 9-column feature records → megaS121_merged.gff
INFO - 1 invalid input files detected
INFO - gff file is invalid due to: No valid GFF records (no 9-column features found)
INFO - The output file is not generated
```

This is **wrong** — the input GFF is completely valid. Manually inspected `megaS121_merged.gff`: 383,661 lines total, 337,354 of them well-formed tab-separated 9-column CDS/tRNA/tmRNA feature records, no corruption, no encoding issues. Since the process output is declared `optional: true` in [`modules/ebi-metagenomics/pathofact2/integrator/main.nf`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/ebi-metagenomics/pathofact2/integrator/main.nf), the pipeline doesn't hard-fail — it just silently drops all PathoFact2 virulence/toxin output for that sample and continues, which is easy to miss since nothing errors.

**Root cause:** [`modules/ebi-metagenomics/pathofact2/integrator/resources/usr/bin/pathofact2_integrator.py`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline/blob/main/modules/ebi-metagenomics/pathofact2/integrator/resources/usr/bin/pathofact2_integrator.py), `_has_gff_record_9cols()`:

```python
def _has_gff_record_9cols(path: str, max_lines: int = 200) -> bool:
    """
    Return True if at least one non-comment, non-empty line with exactly 9 tab-separated
    columns exists within the first `max_lines` lines.
    """
    with fileinput.hook_compressed(path, "r", encoding="utf-8", errors="ignore") as fh:
        for _, line in zip(range(max_lines), fh):
            ...
```

GFF3 convention (and this pipeline's own `RENAME`/`TRNAS_INTEGRATOR` output) writes every `##sequence-region` pragma line up front, one per contig, *before* any feature line. Any assembly with more than ~200 contigs (essentially all real single-sample or coassembly metagenomic data — MAP's own CI test fixture has only 8) has its first real feature line past line 200, so this check always returns `False` and the tool believes the file has zero features, even when it has hundreds of thousands.

**Impact:** with the default `annot_type=cdd` (no InterProScan), and with an InterProScan run, this affects every real run of the pipeline — the headline virulence-factor/toxin output (`prediction/virulence/sample_pathofact2.gff`, and the `vf`/`arg` `pathofact2_tox_prob`/`pathofact2_vf_prob` contributions to `sample_combined_report.tsv`) is silently missing for real data, even though `PATHOFACT2_TOXINS`/`PATHOFACT2_VIRULENCE` (the actual ML predictions) run and succeed — the predictions exist, they just never get merged back into the GFF/report.

**Suggested fix:** drop the `max_lines` cap entirely (scan the whole file, or at least until the first non-comment line, which is a cheap streaming check either way), or count `#`-prefixed lines separately from the scan budget so pragma lines don't consume it.

**Workaround:** none applied yet — flagging as-is; a "no cap" or "count only past the header block" fix needs to land upstream in `pathofact2_integrator.py`. In the meantime, real runs of this pipeline should be assumed to be missing PathoFact2 virulence/toxin integration entirely.

---

## Issue 8/4 — design gap, not a bug: MAP requires the full ~100GB InterProScan DB just for the SignalP column, when PathoFact2 itself runs SignalP6 natively without InterProScan at all

**Title:** SignalP annotation is wired exclusively through InterProScan, but the wrapped tool (PathoFact2) has its own native, independent SignalP6 integration — consider exposing that instead

**Body:**

`docs/usage.md` states InterProScan (~100 GB, not included in `--download_dbs`) is needed for two things: SanntiS BGC prediction, and the `signalP` column in `sample_combined_report.tsv`. Skipping IPS (e.g. via `--skip_sanntis`, or just not supplying `interproscan_db`/`interproscan_tsv`) means the SignalP column is always `-`.

But PathoFact2 — the tool this pipeline wraps for virulence/toxin prediction — has its **own native, standalone SignalP6 integration**, entirely independent of InterProScan: see [PathoFact2's own README](https://gitlab.com/uniluxembourg/lcsb/systems-ecology/pathofact2/-/blob/submission/Readme.md), step 5 ("Install SignalP 6 (Optional)") and its documented output tree, which has a dedicated `SignalP/<sample>/{AMR,TOX,VF}/` directory. InterProScan is never mentioned anywhere in PathoFact2's own documentation — SignalP6 is a separate, much lighter, directly-installable tool (an academic-license download, not a ~100GB database).

**Suggested fix / question for maintainers:** was wiring SignalP through IPS instead of through PathoFact2's own native SignalP6 step a deliberate simplification (e.g. to reuse IPS output already computed for SanntiS/other MGnify pipelines), or would it be worth exposing PathoFact2's native SignalP6 step directly as a lighter-weight path to populate the `signalP` column without requiring the full IPS database? For anyone who wants SignalP-informed virulence/toxin calls but doesn't need SanntiS or already has an IPS-heavy setup elsewhere, this would meaningfully lower the barrier to a complete run.
