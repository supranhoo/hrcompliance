import openpyxl, re, datetime, collections
from clean_common import *
WB = '24e69e81-1788633743447_Daily_Plant_Visit.xlsx'; WBN = 'Daily_Plant_Visit.xlsx'
COLS = [('source_workbook','ok'),('source_sheet','ok'),('source_row','ok'),('source_row_hidden','ok'),('flag_codes','ok'),('visit_date_clean','ok'),('entry_type_hint','ok'),('observation_text','text'),('remarks_text','text'),
        ('sheet_title_as_found','ok'),('also_present_in','ok')]
PAT = [(re.compile(r'^no grievance(s)?( is| was)?( observed| received)?\.?$', re.I), 'NO_GRIEVANCE_OBSERVED'), (re.compile(r'^weekly off( day)?\.?$', re.I), 'WEEKLY_OFF'), (re.compile(r'^(on )?authori[sz]ed leave\.?$', re.I), 'AUTHORIZED_LEAVE')]
def hint(t):
    if not t: return 'BLANK'
    s = ws_norm_single(t)
    for p, n in PAT:
        if p.match(s): return n
    return 'OTHER_TEXT'

def run(pseudo):
    A = Area('PLANT_VISIT', COLS)
    wv = openpyxl.load_workbook(SRC + WB, data_only=True); wf = openpyxl.load_workbook(SRC + WB)
    seen = {}; alsoin = collections.defaultdict(list); total_rows = 0
    for ws in wv:
        wsf = wf[ws.title]; title = ws['A1'].value
        for r in range(3, ws.max_row + 1):
            d, b, c = ws.cell(r, 1).value, ws.cell(r, 2).value, ws.cell(r, 3).value
            if d is None and b is None and c is None: continue
            total_rows += 1
            hidden = bool(wsf.row_dimensions[r].hidden)
            flags = []
            if not isinstance(d, datetime.datetime):
                A.rejected.append(dict(reject_reason='DATE_NOT_A_DATE_OR_BLANK', source_workbook=WBN, source_sheet=ws.title, source_row=r, note='kept out of Cleaned_Data; owner review')); continue
            bn = ws_norm(b) if isinstance(b, str) else b; cn = ws_norm(c) if isinstance(c, str) else c
            for fld, raw, n in (('observation', b, bn), ('remarks', c, cn)):
                if isinstance(raw, str) and raw != n: A.log_tf(WBN, ws.title, r, fld, 'WS_NORMALIZE', '[free text]', '[free text]', sens='text', note='trailing/repeated whitespace only')
            A.log_tf(WBN, ws.title, r, 'date', 'DATE_TO_ISO', str(d), iso(d))
            if hidden: flags.append('SOURCE_ROW_HIDDEN')
            key = iso(d)
            rec = dict(source_workbook=WBN, source_sheet=ws.title, source_row=r, source_row_hidden=hidden, visit_date_clean=key, entry_type_hint=hint(bn), observation_text=bn, remarks_text=cn, sheet_title_as_found=title)
            if key in seen:
                first = seen[key]
                same = (first['observation_text'] == bn) and (first['remarks_text'] == cn)
                alsoin[key].append(f"{ws.title} row {r}{' (hidden)' if hidden else ''}")
                A.duplicates.append(dict(duplicate_type='SAME_DATE_REPEATED_IN_ANOTHER_SHEET', source_workbook=WBN, source_sheet=ws.title, source_row=r, source_row_hidden=hidden, visit_date_clean=key,
                                         group_rows=f"canonical copy: {first['source_sheet']} row {first['source_row']}{' (hidden)' if first['source_row_hidden'] else ''}", content_identical=same,
                                         resolution='excluded from Cleaned_Data (not double counted); canonical copy kept' if same else 'CONTENT DIFFERS - kept for owner review'))
                if not same: A.review.append(dict(category='SAME_DATE_CONFLICTING_CONTENT', source_workbook=WBN, source_sheet=ws.title, source_row=r, original_value='[free text]', detail=f'conflicts with {first["source_sheet"]} row {first["source_row"]}', proposed_action='owner ruling'))
                continue
            rec['flag_codes'] = ';'.join(flags) or None
            seen[key] = rec; A.cleaned.append(rec)
    for rec in A.cleaned:
        k = rec['visit_date_clean']
        if alsoin.get(k): rec['also_present_in'] = '; '.join(alsoin[k]); rec['flag_codes'] = ';'.join(filter(None, [rec['flag_codes'], 'DUPLICATED_IN_OTHER_SHEET']))
    hidden_june = [r for r in A.cleaned if r['visit_date_clean'].startswith('2026-06')]
    A.review.append(dict(category='JUNE_2026_ONLY_AS_HIDDEN_ROWS', source_workbook=WBN, source_sheet="'July 2026' and 'Aug 2026'", source_row=f'{len(hidden_june)} dates', original_value='June 2026 has no sheet of its own; its 30 days exist as hidden rows duplicated in both sheets', detail='one canonical copy kept (July sheet); the Aug copies are in Duplicate_Rows', proposed_action='owner: is there a June sheet elsewhere? (OC-25)'))
    A.review.append(dict(category='SHEET_TITLE_INCONSISTENT', source_workbook=WBN, source_sheet='all', source_row='row 1', original_value='titles differ by sheet ("Tracker Towards Observation of Daily Plant Visit" vs "Grievance Handling & Employee Relations for <month>")', detail='title values preserved in sheet_title_as_found', proposed_action='owner: confirm purpose of the log (OC-26)'))
    A.review.append(dict(category='FREE_TEXT_WITH_PERSONAL_NAMES', source_workbook=WBN, source_sheet='all', source_row='observation/remarks columns', original_value='[withheld]', detail='free text not prepared for DEV; entry_type_hint covers only exact boilerplate phrases', proposed_action='owner decision (OC-27)'))
    cnt = collections.Counter(r['entry_type_hint'] for r in A.cleaned)
    A.summary += [('source_data_rows_all_sheets', total_rows), ('cleaned_unique_dates', len(A.cleaned)), ('duplicate_rows_excluded', len(A.duplicates)), ('hidden_source_rows_in_cleaned', sum(1 for r in A.cleaned if r['source_row_hidden'])),
                  ('june_2026_dates_cleaned', len(hidden_june)), ('june_2026_copies_in_other_sheet_identical', sum(1 for d in A.duplicates if d.get('content_identical'))), ('owner_review_items', len(A.review)), ('transformations_logged', len(A.log))]
    A.summary += [(f'entry_type_{k}', n) for k, n in sorted(cnt.items())]
    if not A.rejected: A.rejected.append(dict(note='no rows rejected'))
    return A
