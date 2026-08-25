# Draft GitHub issue for nf-core/funcscan

Found running funcscan v4.0.0 (tag `4.0.0`) with `--run_amp_screening`. Confirmed still
present on both `main` and `dev` as of 2026-08-25 (checked directly, not assumed) — not a
stale-snapshot issue. Copy/paste at
https://github.com/nf-core/funcscan/issues/new

---

## Issue 1/1

**Title:** `ampcombi_download.py` crashes the whole pipeline on a NaN `Sequence` cell in DRAMP's live TSV export — `TypeError: expected string or bytes-like object, got 'float'`

**Body:**

`--run_amp_screening` (default AMP database is DRAMP) fails outright on `AMP_DATABASE_DOWNLOAD`:

```
Command output:
  File downloaded successfully and saved to amp_DRAMP_database/general_amps_2026_08_25.txt

Command error:
  Traceback (most recent call last):
    File ".../bin/ampcombi_download.py", line 144, in <module>
      download_ref_db(args.database, args.threads)
    File ".../bin/ampcombi_download.py", line 61, in download_ref_db
      if valid_sequence_pattern.match(sequence):
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  TypeError: expected string or bytes-like object, got 'float'
```

The raw TSV download itself succeeds — only the post-processing (filtering to a clean FASTA)
crashes, and since nothing catches it, it takes the entire pipeline run down (all other
independent branches — ARG, BGC, CAZyme — get cancelled too, not just the AMP one).

**Root cause:** [`bin/ampcombi_download.py`](https://github.com/nf-core/funcscan/blob/main/bin/ampcombi_download.py#L59-L63):

```python
db_df = pd.read_csv(f'{db}/general_amps_{date}.txt', sep='\t')
records = []
valid_sequence_pattern = re.compile("^[ACDEFGHIKLMNPQRSTVWY]+$")
for index, row in db_df.iterrows():
    sequence = row['Sequence']
    if valid_sequence_pattern.match(sequence):
        record = SeqRecord(Seq(sequence), id=str(row['DRAMP_ID']), description="")
        records.append(record)
```

`pandas.read_csv` reads an empty/missing cell as `NaN`, which is a `float`, not `""`. DRAMP's
live TSV export (fetched fresh on every pipeline run — there's no pinned/versioned copy) has
at least one row with an empty `Sequence` field as of 2026-08-25, and `re.Pattern.match()`
raises `TypeError` when given a float instead of a string. Since this reference database is
fetched live and unpinned, this isn't a one-off — it'll recur whenever DRAMP's export happens
to contain another such row, for any user running the default AMP screening config.

**Suggested fix:** skip non-string values before the regex check:

```python
for index, row in db_df.iterrows():
    sequence = row['Sequence']
    if not isinstance(sequence, str):
        continue
    if valid_sequence_pattern.match(sequence):
        ...
```

**Workaround used:** patched the line above directly (see `patches/ampcombi_download_nan_sequence_fix.patch`
in this repo) — verified it applies cleanly to a pristine `4.0.0` checkout and produces
byte-identical output to the manually-patched copy that was actually run successfully.
