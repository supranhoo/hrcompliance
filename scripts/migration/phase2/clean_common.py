"""Shared helpers for the Phase 2 conservative source cleaning (read-only on the originals; outputs go OUTSIDE the repository)."""
import re, datetime, hashlib, collections
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

SRC = '/tmp/claude-0/src_orig/'
OUT = '/tmp/claude-0/-home-user-hrcompliance/06613f8d-c946-5045-a997-c15e7c7c78a0/scratchpad/phase2_out/'
WITHHELD = '[WITHHELD - not approved for DEV]'

def ws_norm(s):
    """Trim and collapse runs of spaces/tabs/NBSP inside each line; newlines are kept."""
    if not isinstance(s, str): return s
    lines = [re.sub(r'[ \t ]+', ' ', ln).strip() for ln in s.replace('\r\n', '\n').replace('\r', '\n').split('\n')]
    return '\n'.join(lines).strip('\n').strip()

def ws_norm_single(s):
    if not isinstance(s, str): return s
    return re.sub(r'\s+', ' ', s.replace(' ', ' ')).strip()

def iso(d):
    if isinstance(d, datetime.datetime): return d.date().isoformat()
    if isinstance(d, datetime.date): return d.isoformat()
    return None

class Pseudo:
    """Deterministic, order-of-first-appearance pseudonyms. The key is written to a separate CONFIDENTIAL file outside the repo."""
    def __init__(self): self.maps = collections.defaultdict(dict)
    def tok(self, kind, raw):
        if raw is None or (isinstance(raw, str) and not raw.strip()): return None
        key = ws_norm_single(str(raw))
        m = self.maps[kind]
        if key not in m: m[key] = f'{kind}-{len(m) + 1:04d}'
        return m[key]

class Area:
    """Collects the six required sheets for one source area."""
    def __init__(self, name, columns):
        self.name = name
        self.columns = columns            # list of (field, sens) ; sens in ok|pii:<KIND>|text
        self.cleaned, self.duplicates, self.rejected, self.review, self.log, self.summary = [], [], [], [], [], []
    def log_tf(self, wb, sheet, row, field, rule, before, after, sens='ok', note=''):
        self.log.append(dict(source_workbook=wb, source_sheet=sheet, source_row=row, field=field, rule_id=rule, original_value=before, cleaned_value=after, sens=sens, note=note))

def _safe(cell, v):
    if isinstance(v, str) and v[:1] in '=+-@':
        cell.value = v; cell.data_type = 's'
    else:
        cell.value = v

def write_book(path, area, pseudo, dev):
    wb = Workbook(); wb.remove(wb.active)
    sens = dict(area.columns)
    freq = {f: collections.Counter(ws_norm_single(str(r.get(f))) for r in area.cleaned if r.get(f) is not None) for f, sv in area.columns if sv == 'freq3'}
    def mask(field, v, kind_sens=None):
        s = sens.get(field, 'ok') if kind_sens is None else kind_sens
        if not dev or v is None: return v
        if s == 'ok': return v
        if s == 'text': return WITHHELD
        if s == 'freq3':
            # free-form field that sometimes holds personal names: keep only values shared by >= 3 rows and not matching any pseudonymized original
            if freq[field].get(ws_norm_single(str(v)), 0) < 3: return WITHHELD + ' (rare value)'
            low = str(v).lower()
            for m in pseudo.maps.values():
                for o in m:
                    if len(o) >= 4 and o.lower() in low: return WITHHELD + ' (matches pseudonymized value)'
            return v
        if s.startswith('pii:'): return pseudo.tok(s.split(':', 1)[1], v)
        return v
    def put(title, headers, rows):
        ws = wb.create_sheet(title)
        ws.append(headers)
        for c in ws[1]: c.font = Font(bold=True); c.fill = PatternFill('solid', fgColor='DDDDDD')
        for r in rows:
            ws.append([None] * len(headers))
            for i, h in enumerate(headers): _safe(ws.cell(ws.max_row, i + 1), r.get(h))
        ws.freeze_panes = 'A2'
        for i, h in enumerate(headers): ws.column_dimensions[get_column_letter(i + 1)].width = min(40, max(12, len(str(h)) + 2))
    fields = [f for f, _ in area.columns]
    HIDE_CATS = ('EMP_ID_', 'DUPLICATE_CONTRACTOR_SPELLING', 'SENSITIVE', 'FREE_TEXT')
    def masked_rows(rows, cleaned=False):
        out = []
        for r in rows:
            n = {f: mask(f, r.get(f)) if f in sens else r.get(f) for f in r}
            if dev and not cleaned:
                if any(str(r.get('category', '')).startswith(c) for c in HIDE_CATS) and n.get('original_value') is not None: n['original_value'] = WITHHELD
                if n.get('contractor_as_found'): n['contractor_as_found'] = pseudo.tok('CONTR', r['contractor_as_found'])
                if n.get('raw_cell_A') and str(n['raw_cell_A']).strip("' "): n['raw_cell_A'] = WITHHELD
            out.append(n)
        return out
    put('Cleaned_Data', fields, masked_rows(area.cleaned, True))
    dup_fields = list(dict.fromkeys(k for r in area.duplicates for k in r)) or ['note']
    put('Duplicate_Rows', dup_fields, masked_rows(area.duplicates))
    rej_fields = list(dict.fromkeys(k for r in area.rejected for k in r)) or ['note']
    put('Rejected_or_Invalid', rej_fields, masked_rows(area.rejected))
    rv_fields = list(dict.fromkeys(k for r in area.review for k in r)) or ['note']
    put('Owner_Review', rv_fields, masked_rows(area.review))
    lg = []
    for r in area.log:
        s = r['sens']; hide = dev and s != 'ok'
        lg.append({**{k: v for k, v in r.items() if k != 'sens'}, 'original_value': WITHHELD if hide and r['original_value'] is not None else r['original_value'],
                   'cleaned_value': (mask(r['field'], r['cleaned_value'], s) if hide and r['cleaned_value'] is not None else r['cleaned_value'])})
    put('Transformation_Log', ['source_workbook', 'source_sheet', 'source_row', 'field', 'rule_id', 'original_value', 'cleaned_value', 'note'], lg)
    put('Data_Quality_Summary', ['metric', 'value'], [dict(metric=k, value=v) for k, v in area.summary])
    wb.save(path)

def key_book(path, pseudo):
    wb = Workbook(); ws = wb.active; ws.title = 'KEY_CONFIDENTIAL'; ws.append(['kind', 'pseudonym', 'original_value'])
    for kind, m in pseudo.maps.items():
        for raw, tok in m.items(): ws.append([kind, tok, raw]); _safe(ws.cell(ws.max_row, 3), raw)
    wb.save(path)
