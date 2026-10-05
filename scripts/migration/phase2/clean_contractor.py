import openpyxl, re, datetime, collections, difflib
from clean_common import *

WB = 'e8b07389-Contractor_MP_cost_01092026_1_1.xlsx'; WBN = 'Contractor_MP_cost_01092026_1_1.xlsx'; SH = 'Mar 2026'
COLS = [('source_workbook','ok'),('source_sheet','ok'),('source_row','ok'),('row_class','ok'),('flag_codes','ok'),('month_clean','ok'),
        ('contractor_as_found','pii:CONTR'),('contractor_ws_normalized','pii:CONTR'),('suffix_as_found','ok'),('candidate_group_key','pii:CONTR'),
        ('dept_raw','ok'),('work_area_nature_of_work','ok'),('cost_centre_raw','ok'),('ls_pr','ok'),('unit_candidate_raw','ok'),('bill_no_as_found','ok'),('bill_no_type','ok'),
        ('mandays','ok'),('wages','ok'),('pf','ok'),('esi','ok'),('bill_amount','ok'),('performance_incentive','ok'),('bonus','ok'),('production_incentive','ok'),
        ('total_cost_excl_gst','ok'),('hold_amount_25pct','ok'),('other_hold_or_deduction','ok'),('hold_release_month_clean','ok'),('hold_release_raw_if_not_date','ok'),
        ('hold_expected_25pct_of_total','ok'),('hold_difference','ok'),('total_is_formula','ok'),('constant_formula_columns','ok'),('text_number_columns','ok'),('remarks','text')]
LET = {9:'I',10:'J',11:'K',12:'L',13:'M',14:'N',15:'O',16:'P',17:'Q',18:'R',19:'S'}
SUFFIX = re.compile(r'\s*(\(\d+\))\s*$')
CONST_F = re.compile(r'^=[\d.+\-*/() ]+$')

def text_number(s):
    """Indian/western grouped digits only (e.g. 38,83,582); anything else is NOT converted."""
    t = ws_norm_single(s) if isinstance(s, str) else None
    if t and re.fullmatch(r'\d{1,3}(,\d{2,3})*(\.\d+)?|\d+(\.\d+)?', t): return float(t.replace(',', '')) if '.' in t else int(t.replace(',', ''))
    return None

def run(pseudo):
    A = Area('CONTRACTOR_COST', COLS)
    wv = openpyxl.load_workbook(SRC + WB, data_only=True); wf = openpyxl.load_workbook(SRC + WB)
    ws, wsf = wv[SH], wf[SH]
    rows = []
    for r in range(2, ws.max_row + 1):
        v = [ws.cell(r, c).value for c in range(1, 22)]
        if any(x is not None for x in v): rows.append((r, v))
    A.summary.append(('source_non_empty_rows', len(rows)))
    def gkey(n): return ws_norm_single(SUFFIX.sub('', n or '')).casefold()
    keys = collections.Counter(gkey(v[1]) for r, v in rows if v[1])
    ks = sorted(keys); cand = []
    for i, a in enumerate(ks):
        for b in ks[i + 1:]:
            if difflib.SequenceMatcher(None, a, b).ratio() >= 0.88: cand.append((a, b))
    exact = collections.defaultdict(list)
    billrows = collections.defaultdict(list)
    for r, v in rows:
        if isinstance(v[0], datetime.datetime): exact[tuple(ws_norm_single(x) if isinstance(x, str) else x for x in v)].append(r)
        b = v[7]
        if b is not None and not (isinstance(b, str) and re.search(r'work|bill is not', b, re.I)): billrows[ws_norm_single(str(b)).casefold()].append(r)
    hm = wv['May 2025']; hid = {}
    for r in range(2, hm.max_row + 1):
        hv = [hm.cell(r, c).value for c in range(1, 21)]
        if isinstance(hv[0], datetime.datetime): hid[r] = hv
    rowsd = dict(rows)
    cons_may = [(r, v) for r, v in rows if isinstance(v[0], datetime.datetime) and v[0].strftime('%Y-%m') == '2025-05']
    for r, v in rows:
        flags = []
        if not isinstance(v[0], datetime.datetime):
            A.rejected.append(dict(reject_reason='NO_MONTH', source_workbook=WBN, source_sheet=SH, source_row=r, contractor_as_found=v[1], dept_raw=v[2], bill_no_as_found=v[7], note='row has no Month value; left out of Cleaned_Data (not deleted from source), values preserved here'))
            A.review.append(dict(category='NO_MONTH_ROW', source_workbook=WBN, source_sheet=SH, source_row=r, original_value='(no month)', detail='cannot place in a period; columns appear shifted left', proposed_action='owner to supply month/layout'))
            A.log_tf(WBN, SH, r, 'row', 'EXCLUDE_NO_MONTH', None, None, note='moved to Rejected_or_Invalid')
            continue
        found = v[1]; wsn = ws_norm_single(found) if isinstance(found, str) else found
        m = SUFFIX.search(wsn or '')
        if wsn != found: flags.append('CONTRACTOR_WS_NORMALIZED'); A.log_tf(WBN, SH, r, 'contractor', 'WS_TRIM', found, wsn, sens='pii:CONTR')
        suffix = m.group(1) if m else None
        if suffix: flags.append('N_SUFFIX_PRESENT')
        bill = v[7]; btype = None; bill_s = None
        if bill is not None:
            btype = 'number' if isinstance(bill, (int, float)) else 'text'
            bill_s = ws_norm_single(str(bill))
            if isinstance(bill, str) and re.search(r'work|bill is not|worked|upto', bill, re.I): btype = 'note_in_bill_column'
        placeholder = isinstance(bill, str) and re.search(r'work not done|work done upto|worked upto|not yet finalized', bill, re.I)
        vals = {}; tcols = []; cconst = []
        for c in range(9, 20):
            x = v[c - 1]; L = LET[c]
            fx = wsf.cell(r, c).value
            if isinstance(fx, str) and CONST_F.match(fx): cconst.append(L)
            if isinstance(x, str):
                n = text_number(x)
                if n is not None: vals[c] = n; tcols.append(L); A.log_tf(WBN, SH, r, f'col {L}', 'TEXT_NUMBER_TO_NUMBER', x, n); flags.append('NUMBER_STORED_AS_TEXT')
                else:
                    vals[c] = None; tcols.append(L + '!'); flags.append('NON_NUMERIC_TEXT_IN_NUMBER_COLUMN')
                    A.review.append(dict(category='NON_NUMERIC_TEXT_IN_NUMBER_COLUMN', source_workbook=WBN, source_sheet=SH, source_row=r, original_value=x, detail=f'column {L} ({ws.cell(1, c).value}); value kept blank in Cleaned_Data, raw preserved here', proposed_action='owner to supply value'))
            else: vals[c] = x
        if cconst: flags.append('HAND_TYPED_NUMBERS_IN_FORMULA')
        total = vals[17]; hold = vals[18]
        tf = isinstance(wsf.cell(r, 17).value, str) and str(wsf.cell(r, 17).value).startswith('=')
        if total is not None and not tf: flags.append('HARDCODED_TOTAL')
        hexp = round(total * 0.25, 2) if isinstance(total, (int, float)) else None
        hdiff = round(hold - hexp, 2) if isinstance(hold, (int, float)) and hexp is not None else None
        if hdiff is not None and abs(hdiff) > 1: flags.append('HOLD_DISCREPANCY')
        rel = v[19]; reld = iso(rel) if isinstance(rel, datetime.datetime) else None; relraw = rel if rel is not None and reld is None else None
        if relraw is not None: flags.append('RELEASE_MONTH_NOT_A_DATE')
        if placeholder: flags.append('WORK_NOT_DONE_PLACEHOLDER')
        key = tuple(ws_norm_single(x) if isinstance(x, str) else x for x in v)
        if len(exact[key]) > 1: flags.append('EXACT_DUPLICATE_ROW')
        if bill_s and len(billrows[bill_s.casefold()]) > 1:
            flags.append('REPEATED_BILL_NO')
            if sum(1 for rr in billrows[bill_s.casefold()] if gkey(rowsd[rr][1]) == gkey(found)) > 1: flags.append('REPEATED_BILL_NO_SAME_CONTRACTOR_KEY')
        if v[0].strftime('%Y-%m') == '2025-05': flags.append('MAY_2025_CONSOLIDATED_VS_HIDDEN_REVIEW')
        rowd = dict(source_workbook=WBN, source_sheet=SH, source_row=r, row_class='PLACEHOLDER_NO_WORK' if placeholder else 'DATA', month_clean=iso(v[0]),
                    contractor_as_found=found, contractor_ws_normalized=wsn, suffix_as_found=suffix, candidate_group_key=gkey(wsn),
                    dept_raw=ws_norm_single(v[2]), work_area_nature_of_work=ws_norm_single(v[3]), cost_centre_raw=ws_norm_single(v[4]), ls_pr=ws_norm_single(v[5]), unit_candidate_raw=ws_norm_single(v[6]),
                    bill_no_as_found=bill_s, bill_no_type=btype, mandays=vals[9], wages=vals[10], pf=vals[11], esi=vals[12], bill_amount=vals[13], performance_incentive=vals[14], bonus=vals[15],
                    production_incentive=vals[16], total_cost_excl_gst=total, hold_amount_25pct=hold, other_hold_or_deduction=vals[19], hold_release_month_clean=reld, hold_release_raw_if_not_date=relraw,
                    hold_expected_25pct_of_total=hexp, hold_difference=hdiff, total_is_formula=tf if total is not None else None, constant_formula_columns=','.join(cconst) or None,
                    text_number_columns=','.join(tcols) or None, remarks=ws_norm(v[20]))
        for f, raw in (('dept_raw', v[2]), ('work_area', v[3]), ('cost_centre', v[4]), ('ls_pr', v[5]), ('unit', v[6])):
            if isinstance(raw, str) and ws_norm_single(raw) != raw: A.log_tf(WBN, SH, r, f, 'WS_TRIM', raw, ws_norm_single(raw))
        rowd['flag_codes'] = ';'.join(dict.fromkeys(flags)) or None
        A.cleaned.append(rowd)
    for key, rs in exact.items():
        if len(rs) > 1:
            for r in rs: A.duplicates.append(dict(duplicate_type='EXACT_DUPLICATE_ROW', source_workbook=WBN, source_sheet=SH, source_row=r, group_rows=','.join(map(str, rs)), resolution='NOT RESOLVED - both kept in Cleaned_Data flagged; owner to confirm duplicate vs two real lines'))
    for b, rs in billrows.items():
        if len(rs) > 1: A.duplicates.append(dict(duplicate_type='REPEATED_BILL_NO', source_workbook=WBN, source_sheet=SH, source_row=','.join(map(str, rs)), group_key=b, group_rows=','.join(map(str, rs)), resolution='NOT RESOLVED - rows kept'))
    for a, b in cand:
        rs = [r for r, v in rows if v[1] and gkey(v[1]) in (a, b)]
        A.review.append(dict(category='DUPLICATE_CONTRACTOR_SPELLING_CANDIDATE', source_workbook=WBN, source_sheet=SH, source_row=f'{len(rs)} rows (see Cleaned_Data candidate_group_key)', original_value=f'{a} | {b}', detail='similar names; NOT merged', proposed_action='owner to confirm same/different contractor and legal spelling'))
    nrows = [rd['source_row'] for rd in A.cleaned if rd['suffix_as_found']]
    A.review.append(dict(category='N_SUFFIX_MEANING_UNCONFIRMED', source_workbook=WBN, source_sheet=SH, source_row=f'{len(nrows)} rows (flag N_SUFFIX_PRESENT)', original_value='(n) kept exactly as found in contractor_as_found and suffix_as_found', detail='not removed, not interpreted', proposed_action='owner to state what (n) means'))
    for rd in A.cleaned:
        if 'HOLD_DISCREPANCY' in (rd['flag_codes'] or ''):
            A.review.append(dict(category='HOLD_DISCREPANCY', source_workbook=WBN, source_sheet=SH, source_row=rd['source_row'], original_value=rd['hold_amount_25pct'], detail=f"expected 25% of total = {rd['hold_expected_25pct_of_total']}; difference {rd['hold_difference']}; amounts unchanged", proposed_action='owner ruling'))
    ndiff = 0; prod_shift = 0; cc_eq_dept = 0; dept_eq_cc = 0; tot_may = 0
    for (cr, cv), (hr, hv) in zip(cons_may, sorted(hid.items())):
        tot_may += 1
        pairs = [('Wages', cv[9], hv[7]), ('Bill amount', cv[12], hv[10]), ('Total cost excl GST', cv[16], hv[14]), ('Hold amount', cv[17], hv[15])]
        same = lambda a, b: (a is None and b is None) or (isinstance(a, (int, float)) and isinstance(b, (int, float)) and abs(a - b) < 0.01)
        diffs = [(n, a, b) for n, a, b in pairs if not same(a, b)]
        if not same(cv[15], hv[13]): prod_shift += 1
        if ws_norm_single(cv[4] or '') == ws_norm_single(hv[2] or ''): cc_eq_dept += 1
        if ws_norm_single(cv[2] or '') == ws_norm_single(hv[3] or ''): dept_eq_cc += 1
        if diffs:
            ndiff += 1
            A.review.append(dict(category='MAY_2025_CONSOLIDATED_VS_HIDDEN_CONFLICT', source_workbook=WBN, source_sheet=f"{SH} row {cr} vs 'May 2025' row {hr}", source_row=cr, original_value='; '.join(f'{n}: consolidated={a} hidden={b}' for n, a, b in diffs), detail='both versions preserved; nothing resolved', proposed_action='owner to state authoritative values'))
    A.review.append(dict(category='MAY_2025_PRODUCTION_INCENTIVE_COLUMN_SHIFT', source_workbook=WBN, source_sheet=SH, source_row='May 2025 rows', original_value=f'{prod_shift} of {tot_may} consolidated rows carry a value in Production Incentive where the hidden sheet has none (value equals Total)', detail='looks like a column shift from consolidation; nothing changed', proposed_action='owner ruling together with the May conflict'))
    A.review.append(dict(category='DEPT_VS_COST_CENTRE_ROLE_DIFFERENCE', source_workbook=WBN, source_sheet=SH, source_row='May 2025 rows (2-23)', original_value=f'consolidated Cost Centre equals hidden-sheet Dept in {cc_eq_dept} of {tot_may} rows; consolidated Dept equals hidden-sheet Cost Centre in {dept_eq_cc} of {tot_may}', detail='Dept/Cost Centre/Nature of work columns do not carry the same meaning in early rows as in later rows; nothing changed', proposed_action='owner to define the three columns'))
    cnt = collections.Counter()
    for rd in A.cleaned:
        for f in (rd['flag_codes'] or '').split(';'):
            if f: cnt[f] += 1
    A.summary += [('cleaned_rows', len(A.cleaned)), ('rows_with_no_month_rejected', len(A.rejected)), ('rows_flagged_at_least_once', sum(1 for r in A.cleaned if r['flag_codes'])), ('exact_duplicate_row_groups', sum(1 for x in exact.values() if len(x) > 1)),
                  ('repeated_bill_no_values', sum(1 for x in billrows.values() if len(x) > 1)), ('contractor_strings_as_found', len(set(r['contractor_as_found'] for r in A.cleaned))), ('contractor_candidate_groups', len(set(r['candidate_group_key'] for r in A.cleaned))),
                  ('spelling_candidate_pairs_for_owner', len(cand)), ('may_2025_rows_with_differences_vs_hidden', ndiff), ('may_2025_production_incentive_shift_rows', f'{prod_shift} of {tot_may}'), ('owner_review_items', len(A.review)), ('transformations_logged', len(A.log))]
    A.summary += [(f'flag_{k}', n) for k, n in sorted(cnt.items())]
    mon = collections.Counter(r['month_clean'][:7] for r in A.cleaned); A.summary.append(('rows_per_month', str(dict(sorted(mon.items())))))
    for hs, tcol in (('June 2025', 15), ('July 2025', 15), ('Aug 2025', 16), ('Sept 2025', 16)):
        h = wv[hs]; ht = 0.0; hn = 0; mo = None
        for r in range(2, h.max_row + 1):
            if isinstance(h.cell(r, 1).value, datetime.datetime):
                hn += 1; x = h.cell(r, tcol).value; mo = h.cell(r, 1).value.strftime('%Y-%m')
                if isinstance(x, (int, float)): ht += x
        ct = sum(rd['total_cost_excl_gst'] for rd in A.cleaned if rd['month_clean'][:7] == mo and isinstance(rd['total_cost_excl_gst'], (int, float)))
        A.summary.append((f'reconcile_{hs}', f'hidden rows {hn} total {ht:,.2f}; consolidated total {ct:,.2f}; difference {ht - ct:,.2f}'))
    return A
