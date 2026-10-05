# Phase 2 conservative cleaning scripts
`python3 run_all.py` reads the five original workbooks (read-only, from `/tmp/claude-0/src_orig/`), and writes cleaned working files to the session scratchpad **outside the repository** (see `OUT` in `clean_common.py`). Nothing is imported, no database is touched, originals are never written.
Per area: `<AREA>_cleaned_FULL_CONFIDENTIAL.xlsx` (source values; contains personal data) and `<AREA>_cleaned_DEV_pseudonymized.xlsx` (personal names/IDs replaced by deterministic pseudonyms, free text withheld), plus one `PSEUDONYM_KEY_CONFIDENTIAL.xlsx`. Never commit the outputs.
Each workbook has the sheets Cleaned_Data, Duplicate_Rows, Rejected_or_Invalid, Owner_Review, Transformation_Log, Data_Quality_Summary.
