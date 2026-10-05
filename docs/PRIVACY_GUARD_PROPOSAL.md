# Privacy guard proposal — keep confidential source data out of Git (Phase 4; NOT implemented)

**Status:** proposal for approval (decision PRV-02). Nothing below is implemented yet; no CI or `.gitignore` change has been made in Phase 4.
**Why:** the source workbooks and the cleaned FULL files contain personal and confidential commercial data, and the pseudonym key re-identifies pseudonymised data. They must never enter Git, DEV, CI artifacts or ordinary application storage. Today the only protection is a `.gitignore` line for `data/source/` and discipline; the repository currently tracks **no** spreadsheet or CSV file at all (checked), so a strict rule costs nothing.

## 1. `.gitignore` additions (proposed)
```
# Confidential source/cleaned data and the pseudonym key — never commit
data/
raw/
source-data/
**/source_data/
*PSEUDONYM_KEY*
*_FULL_CONFIDENTIAL*
*CONFIDENTIAL*.xlsx
SUPERSEDED_DO_NOT_USE__*
phase2_out/
phase4_out/
*.xlsx
*.xlsm
*.xlsb
*.xls
*.csv
!apps/web/src/**/fixtures/*.csv
```
(Spreadsheets/CSV are ignored by default; a deliberate synthetic test fixture needs an explicit allow-list line and review.)

## 2. CI guard (proposed script `scripts/validation/check-no-confidential-files.sh`, run first in the `web` and `database` jobs)
Fails the build if **any tracked file** (`git ls-files`) or any file added in the pushed range:
1. has a name or path matching `PSEUDONYM_KEY`, `FULL_CONFIDENTIAL`, `CONFIDENTIAL`, `SUPERSEDED_DO_NOT_USE`, or a directory `data/`, `raw/`, `source-data/`, `source_data/`, `phase2_out/`, `phase4_out/`;
2. is a spreadsheet/CSV (`.xlsx .xlsm .xlsb .xls .csv`) outside an explicit allow-list file (`scripts/validation/confidential-allowlist.txt`, empty by default);
3. contains one of the **known original workbook SHA-256 prefixes** or file names recorded in `docs/migration/PHASE1_SOURCE_AUDIT.md` (their *content* cannot be scanned in a binary file, but a binary spreadsheet is already blocked by rule 2);
4. (text files only) contains high-risk patterns: 10+-digit tokens next to the words "ESIC"/"IP", or the literal marker `KEY_CONFIDENTIAL`. Documentation that only states counts passes.
Also: the CI job must **not upload artifacts** from `phase*_out/`, `data/` or any `.xlsx` (rule enforced by a step that lists artifact paths and fails on those patterns), and the workflow files must contain no `upload-artifact` of such paths.
**Bite test:** like `test-frozen-lock.sh`, a test script creates temporary offending files (in a scratch checkout) and proves each rule fails the guard and that a clean tree passes.

## 3. Local protection (optional but recommended)
A `pre-commit` hook (same script) and a short note in `README`/`docs/MIGRATION_PLAN.md`. Cloud sessions keep working files in the temporary scratchpad, never in the working tree.

## 4. Operational controls (not code)
- **Custody:** the original workbooks, FULL cleaned files and the pseudonym key are held by the owner in an owner-controlled secure location (PRV-03); the session copies are temporary.
- **DEV:** only the DEV-pseudonymised/withheld variants are ever loaded; the key is never loaded to DEV or any application table or storage bucket.
- **Disposal:** retention/disposal of source and cleaned files decided under PRV-04.
- **If a leak happens:** treat as an incident — remove from history with the owner's approval, rotate nothing (no secrets involved) but notify the owner, and record it in `docs/DECISIONS.md`.

## 5. Effort and risk
Small: one shell script, one test script, `.gitignore` lines, two CI steps. Risk: the blanket `*.csv`/`*.xlsx` ignore may hide a legitimate fixture — handled by the allow-list. Implementation waits for approval of PRV-02.
