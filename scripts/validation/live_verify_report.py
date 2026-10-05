#!/usr/bin/env python3
"""Turns the raw psql --csv output of the DEV live verification scripts into concise PASS/FAIL lines and a GitHub Job Summary.

Usage:  live_verify_report.py <kind> <csv-file>      kind = audit | gate | attachment | org
Exit status: 0 = PASS, 1 = FAIL (any FAIL / N/A / missing OVERALL row / unexpected shape).

PRIVACY: the organisation inventory is parsed here and ONLY counts and three yes/no flags are printed. No code, name or parent of any record is ever written to the
log, the Job Summary or an artifact. The raw CSV stays in a temp directory on the runner and is deleted by the caller.
"""
import csv, os, re, sys

def rows(path, ncols):
    with open(path, newline='', encoding='utf-8') as fh:
        r = list(csv.reader(fh))
    if not r:
        return None, []
    return r[0], [x for x in r[1:] if len(x) == ncols]

def summary(md):
    p = os.environ.get('GITHUB_STEP_SUMMARY')
    if p:
        with open(p, 'a', encoding='utf-8') as fh:
            fh.write(md + '\n')

def report_checks(title, header, body, status_idx, name_idx, detail_idx, min_rows):
    """Shared grader for the audit / attachment scripts (n, check, result, info) and the gate (n, check, expected, actual, status)."""
    fails = [x for x in body if x[status_idx] in ('FAIL', 'N/A')]
    overall = [x for x in body if x[0] == '99']
    npass = sum(1 for x in body if x[status_idx] == 'PASS')
    ok = bool(overall) and overall[0][status_idx] == 'PASS' and not fails and len(body) >= min_rows
    verdict = 'PASS' if ok else 'FAIL'
    print(f'{verdict} - {title}: {npass} PASS, {len(fails)} FAIL/N-A, {len(body) - 1} checks reported')
    lines = [f'### {"✅" if ok else "❌"} {title}: **{verdict}**  ({npass} PASS, {len(fails)} FAIL/N-A)']
    if len(body) < min_rows:
        print(f'  FAIL - expected at least {min_rows} result rows, got {len(body)}')
        lines.append(f'- result is incomplete: {len(body)} rows (expected at least {min_rows})')
    if not overall:
        print('  FAIL - no OVERALL row in the output')
        lines.append('- no OVERALL row in the output')
    for x in fails:
        d = f' (expected {x[2]}, actual {x[3]})' if status_idx == 4 else (f' ({x[3]})' if x[3] else '')
        print(f'  FAIL #{x[0]}: {x[name_idx]}{d}')
        lines.append(f'- **FAIL #{x[0]}** {x[name_idx]}{d}')
    summary('\n'.join(lines) + '\n')
    return ok

def main():
    kind, path = sys.argv[1], sys.argv[2]
    if kind == 'audit':
        h, b = rows(path, 4); ok = bool(b) and report_checks('verifier role audit', h, b, 2, 1, 3, 16)
    elif kind == 'attachment':
        h, b = rows(path, 4); ok = bool(b) and report_checks('live_attachment_check.sql', h, b, 2, 1, 3, 19)
    elif kind == 'gate':
        h, b = rows(path, 5); ok = bool(b) and report_checks('live_gate.sql', h, b, 4, 1, 3, 24)
    elif kind == 'org':
        ok = report_org(path)
    else:
        print('unknown kind'); ok = False
    sys.exit(0 if ok else 1)

MASTERS = ['entity', 'location', 'business_unit', 'unit', 'department', 'authority']
ALL_MASTERS = MASTERS + ['designation']

def report_org(path):
    h, b = rows(path, 5)
    if h is None:
        print('FAIL - organisation inventory: empty output'); summary('### ❌ Organisation master summary: **FAIL** (empty output)\n'); return False
    counts, listed, flags = {}, {m: 0 for m in ALL_MASTERS}, {'GFA': set(), 'HASP': set(), 'Common': set()}
    pats = {k: re.compile(r'\b' + k + r'\b', re.I) for k in flags}
    for master, code, name, _parent, _active in b:
        if master.startswith('COUNT '):
            counts[master[6:]] = int(name)
            continue
        if master in listed:
            listed[master] += 1
            for k, rx in pats.items():
                if rx.search(code or '') or rx.search(name or ''):
                    flags[k].add(master)
    # consistency: the COUNT rows must agree with the rows that were listed (zero-count masters have no COUNT row)
    ok = all(counts.get(m, 0) == listed[m] for m in ALL_MASTERS)
    lines = [f'### {"✅" if ok else "❌"} Organisation master summary (counts and flags only; no names or codes are published): **{"PASS" if ok else "FAIL"}**', '',
             '| master | records |', '|---|---|']
    print(('PASS' if ok else 'FAIL') + ' - organisation master summary (counts and flags only)')
    for m in MASTERS:
        lines.append(f'| {m} | {listed[m]} |'); print(f'  {m}: {listed[m]}')
    if not ok:
        lines.append('\n- COUNT rows disagree with the listed rows: the inventory output is inconsistent'); print('  FAIL - COUNT rows disagree with listed rows')
    lines += ['', '| reference | found | in master type(s) |', '|---|---|---|']
    for k in ('GFA', 'HASP', 'Common'):
        where = ', '.join(sorted(flags[k])) or '-'
        lines.append(f'| {k} | {"yes" if flags[k] else "no"} | {where} |'); print(f'  {k} exists: {"yes" if flags[k] else "no"}' + (f' (in: {where})' if flags[k] else ''))
    summary('\n'.join(lines) + '\n')
    return ok

if __name__ == '__main__':
    main()
