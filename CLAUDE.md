# assembly_to_MGE

Downstream module: classify contigs/MAGs from the existing assembly+binning pipeline for
mobile genetic elements (MGE), AMR/VF/BGC content, and plasmid typing, then combine
everything into per-contig/per-gene tables to track AMR-on-plasmid-vs-AMR-on-MAG dynamics
over the longitudinal sample series.

## Goal

- Classify contigs with geNomad (plasmid / chromosome / virus).
- Plasmid typing on top of the geNomad plasmid calls (mob-suite, plus the existing PLSDB
  minimap screen) — MAP (see below) detects plasmids but does not type them, so this stays
  a separate step regardless of which classification pipeline is used.
- AMR, virulence factor, and BGC calling.
- Functional annotation of genes (KEGG/COG/CAZy/GO) — not covered by MAP, see Open questions.
- Combine all of the above with MAG assignment and per-sample bowtie2 coverage so that, for
  a given AMR gene, we know: is it on a plasmid-classified contig or chromosome/MAG contig,
  which MAG/taxon, and how its coverage changes across timepoints.
- Can run on the coassembly + per-sample bowtie2 mappings, or on single assemblies + their
  own mapping — see the coassembly-vs-single-assembly discussion below. Either way,
  quantification is bowtie2-based: self-mapping (each sample's reads against its own
  assembly) for the single-assembly case, vs. all-samples-mapped-against-the-shared-contigs
  for the coassembly case.

Pipeline reference this builds on:
https://github.com/fconstancias/shotgun_metagenomics_binning/tree/dev

**Status (2026-08-24)**: MAP v5.0.0 DB download + a real-data test run (single assembly
`megaS121` + its covering coassembly `co728`, both participant 728) launched — see
[README.md](README.md) for the exact commands/environment and current progress.

## Confirmed state (checked on disk 2026-08-24)

- **Workflow engine**: Snakemake. Assembly/binning pipeline lives in
  `../binning_smk/` (`metagenome_assemble.smk`, `metagenome_binning.smk`,
  `summarise_mags.smk`, `common.smk`), with its own `README.md`, per-run `config_*.yaml`,
  and `results_*` output dirs.
- **Coassembly AND single assembly both exist** — this is not an either/or to decide, both
  are already produced:
  - Coassembly groups: `co728`, `co894`, `cospa728`, `cospa894`, etc.
    (`B01_megahit_co_assembly/`, `B02_metaspades_co_assembly/`)
  - Single-sample assemblies: `megaS*`, `spaS*` (`B01_megahit_single/`, `B02_spades_single*/`)
- **Binning is done**: concoct/VAMB/SemiBin2 → Binette refinement → dRep dereplication →
  GTDB-Tk taxonomy (`gtdbtk_classify/`) → CheckM/CheckM2. Bin-level renamed FASTA files are
  in `../renamed_bins/`, mapped from their raw paths in `../bin_map.tsv`. Note this mapping
  is bin-file-level, not contig-level — there's no scaffolds2bin-style contig→bin table yet
  (see Open questions if this module needs one).
- **anvi'o contigs-dbs already exist**: `../anvio-9.tar.gz`, `../co894_anvio_results.tar.gz`,
  `../co_spa_anvio.tar.gz`, `../megaS121_megaS157_spaS121_spaS157_assemblies_anvio_results.tar.gz`.
- **Old per-sample MGE/AMR precursor runs exist but will NOT be reused** — `../B03_genomad/`,
  `../B04_amrfinder/`, `../B04_IntegronFinder/`, `../B05_PlasmidSearch_PLSDB/` (per-sample,
  `*_fixed` naming). Decision (2026-08-24): rerun fresh via MAP rather than stitch these
  together — see below. `../B05_PlasmidSearch_PLSDB/` (the PLSDB minimap screen) is the
  exception: it isn't produced by MAP, stays as a separate confirmatory track.
- **Shared resource DB convention**: large reference DBs live directly under
  `scratch/` (not per-project), e.g. `../../genomad_db/`, `../../checkm2/`, `../../GTDB/`,
  `../../MOTUSDB/`. MAP's own DB bundle (see below) should follow the same convention —
  download once under `scratch/` and share the resulting `-c my_paths.config` across projects.

## Decision: adopt MAP (mobilome-annotation-pipeline) as the core classification/AMR/BGC engine

Decided 2026-08-24: rather than hand-assemble geNomad + mob-suite + PathoFact2 +
AMRFinderPlus + antiSMASH as separate steps, test and adopt EBI Metagenomics'
[`mobilome-annotation-pipeline`](https://github.com/EBI-Metagenomics/mobilome-annotation-pipeline)
(MAP) — a maintained Nextflow pipeline that already runs this combination end to end.
It replaces the earlier "run these tools separately" plan below for everything except
plasmid *typing* (mob-suite) and functional annotation (KEGG/eggNOG), which it doesn't do.

### What MAP actually runs (verified against `main.nf`/`workflows/mobilomeannotation.nf`, not just docs)

- **Preprocessing**: contigs filtered/renamed by length; CDS via Prodigal, tRNA via ARAGORN
  (or use your own `proteins_gff`/`proteins_faa` via the samplesheet to skip Prodigal).
- **MGE prediction** (parallel): geNomad (plasmid/phage), ICEfinder2-lite (ICE/IME),
  Integron_Finder (integrons), ISEScan (insertion sequences), compositional-outlier detection
  on contigs ≥100 kb, optional VIRify GFF ingestion for prophages. Merged into one
  `sample_mobilome.gff.gz`; predictions <500 bp or with no CDS are discarded.
- **Functional annotation — confirmed genome-wide, not MGE-restricted**: the channel of
  *all* Prodigal-predicted proteins for the whole assembly (`ch_proteins_source`) is fed
  directly into both `PATHOFACT2(...)` and `AMR_ANNOTATION(...)` in
  `workflows/mobilomeannotation.nf` — there is no upstream filter to plasmid/MGE contigs
  only. So this directly answers "does PathoFact2 run on all contigs or just plasmid
  contigs?" → **all contigs**. AMR = AMRFinderPlus + DeepARG + RGI(CARD); virulence/toxin =
  PathoFact2 ML models + DIAMOND vs VFDB; BGCs = SanntiS + GECCO + antiSMASH (also
  genome-wide, not MGE-restricted).
  - The MGE relationship is added **after the fact**, not as a pre-filter: the integrator
    step produces `sample_combined_report.tsv`, one row per "seed protein" (from
    PathoFact2 and/or AMR hits), with an `mge_type` column set when that protein has ≥90%
    CDS-length overlap with a mobilome feature on the same contig, else `-`. This table is
    essentially the AMR-gene ↔ plasmid/MGE join we were going to build ourselves in
    `10_integration/` — worth checking whether it can BE that table, or just feed it.
- **No KEGG or eggNOG-mapper annotation anywhere in MAP.** Confirmed absent from both the
  docs and the DB-download list. If we want KO/COG/CAZy/GO for all contigs, run eggNOG-mapper
  (or `anvi-run-kegg-kofams`) as a separate step. MAP's own Prodigal `.faa`/`.gff` (or our
  supplied `proteins_faa`) is the natural input — check the published `results/` tree from a
  real run for where the merged protein FASTA actually lands (the documented output tree
  doesn't show it as a top-level file — may need `-resume`/work-dir access or
  `--publish_dir_mode copy` on that channel).
- **No coverage/read-quantification anywhere in MAP.** Confirmed absent — this is entirely
  our own step, see below.

### Combined report columns (from `docs/outputs.md`)

`sample_combined_report.tsv`: `protein_id`, `contig_id`, `summary_string` (fixed order
`vf,arg,mge,bgc`), `vfdb_hit`, `vfdb_blastp_eval`, `pathofact2_tox_prob`,
`pathofact2_vf_prob`, `cdd_annotation`, `amr_drug_class`, `amr_tool`, `amr_tool_ident`,
`mge_type` (plasmid/prophage/insertion_sequence/etc., or `-`), plus BGC and SignalP columns
when resolved. Rows require a PathoFact2 or AMR hit — BGC-only or MGE-only proteins aren't
included as rows (so a plasmid contig with no AMR/VF hit won't show up here; join against
`genomad/*_plasmid_summary.tsv` separately if "all plasmid contigs" is needed, not just
"plasmid contigs with an AMR/VF hit").

### Running it

- Prereqs: Nextflow ≥24.04.0 + Docker or Singularity.
- Databases (one-time, shared): `nextflow run EBI-Metagenomics/mobilome-annotation-pipeline
  --download_dbs /path/to/dbs -profile singularity` — downloads geNomad, CheckV, ICEfinder2,
  PathoFact2 models, VFDB (dmnd), CDD, AMRFinderPlus DB, DeepARG DB, CARD (RGI), antiSMASH DB
  in parallel, then prints a ready-to-paste `params { ... }` config block — save as
  `my_paths.config` and pass with `-c` on every run. InterProScan (~100 GB) is *not*
  included; only needed for SanntiS BGC prediction, pipeline runs fine without it.
- Real run: samplesheet CSV, header `sample,assembly,proteins_gff,proteins_faa,virify_gff,interproscan_tsv`
  — only `sample`+`assembly` mandatory. `nextflow run EBI-Metagenomics/mobilome-annotation-pipeline
  --input samplesheet.csv -c my_paths.config -profile singularity`.
- Individual steps can be skipped (`--skip_virulence`, `--skip_amrfinderplus`,
  `--skip_deeparg`, `--skip_rgi`, `--skip_sanntis`, `--skip_gecco`, `--skip_antismash`) to
  run mobilome-detection-only.
- **Test**: clone the repo, then `nf-test test --profile test,singularity` (or `,docker`);
  full suite ~10 min, uses pre-trimmed test DBs. Tags let you run a subset:
  `positive` (mobilome-only, exercises IS/integron/ICE/plasmid/prophage detection on an
  8-contig synthetic assembly), `negative` (2-contig assembly with no MGEs, expects an
  empty mobilome GFF), `pathofact` (full functional-annotation run producing a
  `combined_report`, paired with a pre-computed `annotation_manifest.csv` so it doesn't need
  to invoke the AMR/BGC tools directly — the manifest-reuse mechanism only applies to outputs
  from specific other MGnify pipelines, not our own `B03`–`B05`, hence the decision above to
  rerun fresh).

## Coverage / quantification (outside MAP — MAP does none of this)

Goal: per-gene and per-contig coverage/depth (+ variability) from the existing bowtie2 BAMs,
without building full anvi'o contigs-db + profile-db + merge for every assembly.

- **`anvi-script-get-coverage-from-bam`** — BAM-only, no contigs-db or profile-db needed.
  Modes: `-m pos` (per-nucleotide, single contig), `-m contig` (per-contig average, given a
  contig list), `-m bin` (per-bin aggregate, given a collection/bin-membership file — this is
  where a contig→bin table, see Open questions, would be consumed). No gene-level mode.
- **CoverM** (`coverm contig`) — no db needed, single fast binary, handles multiple BAMs in
  one pass. `--methods mean trimmed_mean variance covered_fraction rpkm tpm` gives exactly
  the "coverage + variability" ask per contig, directly from BAM. Worth comparing against
  `anvi-script-get-coverage-from-bam -m contig` for the per-contig case; CoverM is likely the
  better fit for multi-sample coassembly coverage tables given its native multi-BAM handling.
- **Gene-level**: neither tool above resolves per-gene. Convert MAP's Prodigal/mobilome GFF
  to BED and run `samtools bedcov genes.bed sample.bam` (or `bedtools coverage -mean`)
  against the *same* bowtie2 BAM already produced for contig-level mapping — no separate
  remapping needed.
- **Check first**: the existing binning workflow (`../binning_smk/`) already runs SemiBin2
  and/or VAMB, both of which consume per-contig depth (BAM-derived, MetaBAT2-style
  `jgi_summarize_bam_contig_depths` or aemb). If those per-contig depth tables are retained
  anywhere in `../BINNING/`, they may already cover the per-contig (not per-gene) part of this
  without rerunning anything.

## Design notes still relevant after adopting MAP

- **mob-suite caveat** (plasmid *typing*, not detection — MAP doesn't do this): `mob_recon`/
  `mob_typer` assume single-isolate assemblies and cluster plasmid contigs by coverage
  pattern — that assumption is weaker on metagenomic (co)assembly contigs across taxa. Best
  practice: run mob-suite only on contigs MAP's geNomad step already flagged as plasmid
  (`prediction/genomad/*_plasmid_summary.tsv`), either per-MAG (its plasmid contigs treated
  as one "genome") or per-contig with `mob_typer` in single-sequence mode for anything
  unbinned. Keep the existing PLSDB minimap screen (`../B05_PlasmidSearch_PLSDB/`) as a
  separate confirmatory track (nearest known reference / host range) rather than replacing it.
- **Coassembly vs single-assembly as the primary axis**: recommend running MAP + mob-suite +
  coverage on the coassembly, with per-sample bowtie2 coverage against it for the time-series
  signal. A gene/contig on the coassembly has one fixed ID, one geNomad call, one MOB-type,
  one MAG assignment across the whole series — only coverage varies by timepoint.
  Single-assembly MAGs (already produced) are a secondary strain-resolution check, not the
  primary axis for the longitudinal AMR question — otherwise every plasmid/MAG needs
  cross-timepoint dereplication (dRep) plus a common reference just to compare like-for-like.

## Proposed output layout for this module

Keyed throughout on `contig_id` (and `gene_id`/`protein_id` for gene-level features). MAP's
own `sample_combined_report.tsv` already does most of the AMR/VF/BGC × MGE join, so
`10_integration/` becomes "extend MAP's report" rather than "build the join from scratch":

```
assembly_to_MGE/
  results/
    01_map/                       # MAP's own nextflow --outdir, per sample
      {sample}/sample_combined_report.tsv, gff/, prediction/, preprocessing/
    02_mobsuite/                  # per plasmid-contig or per-MAG: replicon, relaxase, mobility
    03_plsdb_minimap/             # link/reuse ../B05_PlasmidSearch_PLSDB rather than rerun
    04_functional_annotation/
      eggnog/                     # or anvi-run-kegg-kofams output, TBD
    05_coverage/
      bowtie2/{sample}/           # per-sample bam (already produced upstream)
      coverm_contig/               # per-contig mean/variance/trimmed_mean/covered_fraction
      gene_bedcov/                  # per-gene mean depth from samtools bedcov
    10_integration/
      contig_table.tsv            # contig_id, length, MAG_id, MAG_taxonomy, genomad_call, mob_type, plsdb_hit
      gene_table.tsv               # gene_id, contig_id, extends MAP's combined_report with KO/COG + coverage
      coverage_long.tsv            # gene_id or contig_id, sample, timepoint, depth/coverage
```

## Open questions

1. Does `sample_combined_report.tsv` (extended with coverage + KO annotation) fully replace
   the hand-built `gene_table.tsv`, or do we still need a separate table for plasmid contigs
   with no AMR/VF hit (MAP's report only includes rows with a PathoFact2 or AMR hit)?
2. Where does MAP actually publish the merged Prodigal protein FASTA in a real run's
   `results/` tree (not shown in the documented output layout) — needed as eggNOG-mapper's
   input so genes aren't repredicted.
3. Is a contig→bin (scaffolds2bin-style) table needed beyond the current bin-file-level
   `../bin_map.tsv`, both for MAG-level joins and for `anvi-script-get-coverage-from-bam -m bin`?
4. CoverM vs `anvi-script-get-coverage-from-bam` for per-contig coverage — or reuse per-contig
   depth already sitting in `../BINNING/` from SemiBin2/VAMB, if it's still there?
5. Build the glue around MAP (mob-suite, eggNOG, coverage, integration) as a new Snakemake
   module matching `../binning_smk/` conventions, or a lighter script-based workflow that
   just wraps/calls the MAP Nextflow run as one step?
6. ~~mettannotator~~ — considered as a MAG-level functional-annotation complement (needs one
   genome/MAG per input row with a TaxID, not a raw coassembly, so it would run separately on
   our dereplicated MAGs). **Decided against (2026-08-25)**: going with MAP + funcscan
   instead (item 7) — kept here only as a record of why it was considered and dropped, not a
   live option.

7. **Decided (2026-08-25): MAP + [nf-core/funcscan](https://github.com/nf-core/funcscan)**
   (checked at tag `4.0.0`), run as a **shared-gene-calling pair**, not "one feeds the other."
   Call genes once, up front, on the raw assembly — Prodigal or Pyrodigal specifically, not
   Prokka (which has its own history of truncating/renaming contig headers via its 20-char
   locus-tag limit, which would reintroduce exactly the ID problem this design avoids) — then
   supply that same `.faa`/`.gff` to both pipelines: MAP's `proteins_gff`/`proteins_faa`
   samplesheet columns, and funcscan's `protein`/`gbk`/`gff` columns (needs a GFF→GenBank
   conversion too, e.g. via Biopython's `SeqIO` — funcscan's pre-annotated mode wants all
   three). Neither pipeline repeats gene-calling.

   This also fixes contig-ID traceability, not just avoids double compute — confirmed by
   reading `workflows/mobilomeannotation.nf` directly, not just the docs. `RENAME` always
   runs unconditionally (`assembly_filter_rename.py`, contig→`contig_N`), and MAP's own MGE
   detection (geNomad/ICEfinder2/ISEScan/IntegronFinder — its actual unique value) always
   operates on those internally-renamed, length-filtered contigs; that part can't be bypassed.
   But when `proteins_gff`/`proteins_faa` are supplied, `AMR_ANNOTATION`/`BGC_ANNOTATION`/
   `PATHOFACT2` are wired to the **original, non-renamed assembly** instead
   (`tuple(meta, user_gff ? orig_assembly : contigs_1kb)` in the BGC input construction) — so
   AMR/BGC/virulence calls come back on our original contig IDs directly. The final
   `COMBINEREPORTER`/`GFF_MAPPING_COMPRESSION_AND_INDEXING` step then does the renamed-ID ↔
   original-ID join **internally**, via the same `contigID.map` RENAME always produces —
   MAP already contains the exact reconciliation logic the `contigID.map` README section says
   we'd otherwise have to build ourselves. Net effect: `sample_combined_report.tsv`'s
   `contig_id` column comes out as our original contig names, with `mge_type` correctly
   populated from the internally-renamed MGE-detection side, with zero manual translation.

   Per-tool split once this is wired up: AMRFinderPlus/RGI/DeepARG and antiSMASH/GECCO stay
   MAP-only (`arg_skip_amrfinderplus`/`arg_skip_rgi`/`arg_skip_deeparg`,
   `bgc_skip_antismash`/`bgc_skip_gecco` in funcscan — antiSMASH alone ran ~3h on `co728`, not
   worth doubling); funcscan runs only what MAP has zero coverage of — full AMP screening,
   CAZy (dbCAN), plus ABRicate/fARGene/argNorm as a second, ontology-normalized AMR opinion.
