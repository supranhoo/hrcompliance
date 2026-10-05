"""Regression/reconciliation checks for the re-issued contractor outputs (read-only; prints only counts and PASS/FAIL)."""
import openpyxl, hashlib, glob, re, os, datetime, collections
from clean_common import SRC, OUT
OLD = OUT + 'SUPERSEDED_DO_NOT_USE__CONTRACTOR_COST_cleaned_FULL_CONFIDENTIAL.xlsx'
NEW = OUT + 'CONTRACTOR_COST_cleaned_FULL_CONFIDENTIAL.xlsx'
NEWDEV = OUT + 'CONTRACTOR_COST_cleaned_DEV_pseudonymized.xlsx'
CONFLICT = [316, 317, 361, 362, 409, 410, 458, 459, 512, 513, 566, 567, 621, 622, 678, 679]
FIN = ['mandays', 'wages', 'pf', 'esi', 'bill_amount', 'performance_incentive', 'bonus', 'production_incentive', 'total_cost_excl_gst', 'hold_amount_25pct', 'other_hold_or_deduction', 'hold_release_month_clean', 'bill_no_as_found']
ok = True
def check(name, cond, detail=''):
    global ok; ok &= bool(cond); print(('PASS' if cond else 'FAIL'), '-', name, detail)
def sheet(path, name):
    ws = openpyxl.load_workbook(path)[name]; h = [c.value for c in ws[1]]
    return h, [dict(zip(h, r)) for r in ws.iter_rows(min_row=2, values_only=True)]
oh, old = sheet(OLD, 'Cleaned_Data'); nh, new = sheet(NEW, 'Cleaned_Data')
o = {r['source_row']: r for r in old}; n = {r['source_row']: r for r in new}
check('row count unchanged (685 cleaned)', len(old) == len(new) == 685, f'old {len(old)} new {len(new)}')
check('same set of source rows', set(o) == set(n))
check('rejected/no-month rows unchanged (2)', len(sheet(OLD, 'Rejected_or_Invalid')[1]) == len(sheet(NEW, 'Rejected_or_Invalid')[1]) == 2)
chg = [(r, f) for r in o for f in FIN + ['source_row', 'month_clean', 'flag_codes_dummy'] if f in o[r] and o[r][f] != n[r].get(f)]
check('no financial/bill-number/month value changed in any row', not chg, f'{len(chg)} differences')
other = [c for c in oh if c not in ('row_class', 'flag_codes') and c in nh and any(o[r][c] != n[r][c] for r in o)]
check('every other cleaned column identical row by row (excl. reclassified fields)', not other, str(other))
# classification
check('16 rows carry CONFLICTING_NOTE_WITH_AMOUNTS', all(n[r]['classification'] == 'CONFLICTING_NOTE_WITH_AMOUNTS' for r in CONFLICT))
check('exactly 16 rows carry that classification', sum(1 for r in new if r['classification'] == 'CONFLICTING_NOTE_WITH_AMOUNTS') == 16)
check('none of the 16 is PLACEHOLDER_NO_WORK', all(n[r]['classification'] != 'PLACEHOLDER_NO_WORK' for r in CONFLICT))
check('16 rows: note=WORK_NOT_DONE, has amounts=YES, owner review=YES', all(n[r]['bill_note_category'] == 'WORK_NOT_DONE' and n[r]['has_financial_amounts'] == 'YES' and n[r]['owner_review_required'] == 'YES' for r in CONFLICT))
check('16 rows keep original Bill No. text', all(str(n[r]['bill_no_as_found']).strip().lower() == 'work not done' for r in CONFLICT))
rest = [r for r in o if r not in CONFLICT]
check('all other rows: classification equals the previous row_class', all(o[r]['row_class'] == n[r]['classification'] for r in rest), f"{sum(1 for r in rest if o[r]['row_class'] != n[r]['classification'])} differ")
check('other placeholder rows unchanged (194 PLACEHOLDER_NO_WORK)', sum(1 for r in rest if n[r]['classification'] == 'PLACEHOLDER_NO_WORK') == 194 == sum(1 for r in rest if o[r]['row_class'] == 'PLACEHOLDER_NO_WORK'))
check('flags: 16 carry the new flag, none carries WORK_NOT_DONE_PLACEHOLDER', all('WORK_NOT_DONE_NOTE_BUT_AMOUNTS_PRESENT' in (n[r]['flag_codes'] or '') and 'WORK_NOT_DONE_PLACEHOLDER' not in (n[r]['flag_codes'] or '') for r in CONFLICT))
# totals vs the ORIGINAL workbook
src = openpyxl.load_workbook(SRC + 'e8b07389-Contractor_MP_cost_01092026_1_1.xlsx', data_only=True)['Mar 2026']
st = sum(src.cell(r, 17).value for r in range(2, src.max_row + 1) if isinstance(src.cell(r, 17).value, (int, float)) and isinstance(src.cell(r, 1).value, datetime.datetime))
ct = sum(r['total_cost_excl_gst'] for r in new if isinstance(r['total_cost_excl_gst'], (int, float)))
check('source Total vs cleaned Total difference = 0.00', abs(st - ct) < 0.005, f'source {st:,.2f} cleaned {ct:,.2f} diff {st - ct:.2f}')
srcb = {r: src.cell(r, 13).value for r in range(2, src.max_row + 1)}
diffs = [abs(n[r]['bill_amount'] - srcb[r]) for r in n if isinstance(srcb[r], (int, float)) and isinstance(n[r]['bill_amount'], (int, float))]
miss = [r for r in n if isinstance(srcb[r], (int, float)) and not isinstance(n[r]['bill_amount'], (int, float))]
check('Bill amount equals source on every numeric source cell (xlsx stores 16 significant digits; tolerance 1e-6)', not miss and max(diffs) < 1e-6, f'max abs difference {max(diffs):.2e} over {len(diffs)} cells')
tdiff = [abs(n[r]['total_cost_excl_gst'] - src.cell(r, 17).value) for r in n if isinstance(src.cell(r, 17).value, (int, float)) and isinstance(n[r]['total_cost_excl_gst'], (int, float))]
check('Total equals source cell by cell', max(tdiff) < 1e-6, f'max abs difference {max(tdiff):.2e} over {len(tdiff)} cells')
# summary metrics
h, summ = sheet(NEW, 'Data_Quality_Summary'); m = {r['metric']: r['value'] for r in summ}
exp = {'AUTH_contractor_rows_non_empty_total': 687, 'AUTH_contractor_rows_dated': 685, 'AUTH_contractor_rows_undated': 2, 'AUTH_no_amount_rows_phase1_definition (no numeric Bill amount and no numeric Total)': 195,
       'AUTH_bill_no_cells_with_placeholder_type_notes': 210, 'AUTH_note_rows_with_no_amounts': 194, 'AUTH_conflicting_note_plus_amounts': 16, 'AUTH_exact_Work_Not_done_text': 203,
       'AUTH_repeated_bill_no_values_dated_rows': 27, 'AUTH_repeated_bill_no_values_including_undated_row_166': 28}
for k, v in exp.items(): check(f'authoritative count {k.split(" ")[0]} = {v}', m.get(k) == v, f'got {m.get(k)}')
rv = [r for r in sheet(NEW, 'Owner_Review')[1] if r['category'] == 'CONFLICTING_NOTE_WITH_AMOUNTS']
check('one Owner_Review item for the 16 rows', len(rv) == 1 and all(str(x) in str(rv[0]['source_row']).split(',') for x in CONFLICT))
# originals + other files
exp_sha = {'24e69e81': 'fa01bd76a7d530f5fe56f094f4b10f3f3939eb5dccf29ed3a4628a24645019bc', '988197ed': '1c406daac51ca2e999b1aac1ab9c84e8487ebaa15e61e625f0e13f09155eebcf', 'b6051f46': 'b97872f68c00158b5eaf3484041ef875e8863ba5ed899e22256554622dba5623',
           'cb910a6c': '0e4cfd9f42646cc882242d76552dfc4c3fbae3fd477c5e371e3c2d1b06e17195', 'e8b07389': '0d9e2a1b37749d28df4cd6f3b94d8bcebbe2bfd91172cbfea1361dfac75a266d'}
for d in ('/root/.claude/uploads/06613f8d-c946-5045-a997-c15e7c7c78a0/', SRC):
    for f in glob.glob(d + '*.xlsx'): check(f'original checksum unchanged ({os.path.basename(f)[:8]} in {"uploads" if "uploads" in d else "working copy"})', hashlib.sha256(open(f, 'rb').read()).hexdigest() == exp_sha[os.path.basename(f)[:8]])
# privacy scan of the new DEV file
key = openpyxl.load_workbook(OUT + 'PSEUDONYM_KEY_CONFIDENTIAL.xlsx')['KEY_CONFIDENTIAL']
orig = [(r[0], str(r[2])) for r in key.iter_rows(min_row=2, values_only=True)]
wb = openpyxl.load_workbook(NEWDEV); hits = 0; cells = 0
for ws in wb:
    for row in ws.iter_rows(values_only=True):
        for x in row:
            t = str(x) if x is not None else ''; cells += bool(t)
            for kind, ov in orig:
                if len(ov) < 4: continue
                if kind in ('PERSON', 'CONTR') and ov.lower() in t.lower(): hits += 1
                if kind == 'EMPID' and re.search(r'(?<![\w-])' + re.escape(ov) + r'(?![\w-])', t): hits += 1
check('privacy scan of re-issued DEV file: 0 hits for original names / IDs / contractor strings', hits == 0, f'{hits} hits over {cells} cells, {len(orig)} protected strings')
allt = ' '.join(str(x) for ws in wb for row in ws.iter_rows(values_only=True) for x in row if x is not None)
check('DEV file has no ESIC-type long digit tokens outside numeric amounts', not re.search(r'\b\d{9,10}\b(?!\.)', re.sub(r'\d+\.\d+', '', allt)))
print('\nOVERALL', 'PASS' if ok else 'FAIL')
for f in sorted(glob.glob(OUT + '*CONTRACTOR_COST*.xlsx')): print(hashlib.sha256(open(f, 'rb').read()).hexdigest(), os.path.basename(f))
