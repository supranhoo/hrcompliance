import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean_common import *
import clean_grc, clean_contractor, clean_liaison, clean_plant
os.makedirs(OUT, exist_ok=True)
pseudo = Pseudo()
E, G = clean_liaison.run(pseudo)
only = sys.argv[1] if len(sys.argv) > 1 else None
if only:   # re-issue a single area: reuse the existing pseudonym key so tokens stay consistent
    import openpyxl
    k = openpyxl.load_workbook(OUT + 'PSEUDONYM_KEY_CONFIDENTIAL.xlsx')['KEY_CONFIDENTIAL']
    for kind, tok, raw in k.iter_rows(min_row=2, values_only=True): pseudo.maps[kind][str(raw)] = tok
    n0 = {kd: len(m) for kd, m in pseudo.maps.items()}
areas = {'GRC': clean_grc.run(pseudo), 'CONTRACTOR_COST': clean_contractor.run(pseudo), 'LIAISON_ESIC': E, 'LIAISON_GOVT': G, 'PLANT_VISIT': clean_plant.run(pseudo)}
for n, A in areas.items():
    if only and n != only: continue
    write_book(OUT + f'{n}_cleaned_FULL_CONFIDENTIAL.xlsx', A, pseudo, dev=False)
    write_book(OUT + f'{n}_cleaned_DEV_pseudonymized.xlsx', A, pseudo, dev=True)
    print(n, 'cleaned', len(A.cleaned), 'dups', len(A.duplicates), 'rejected', len(A.rejected), 'review', len(A.review), 'log', len(A.log))
if only: print('pseudonym key entries unchanged:', all(len(m) == n0.get(kd, 0) for kd, m in pseudo.maps.items()))
else: key_book(OUT + 'PSEUDONYM_KEY_CONFIDENTIAL.xlsx', pseudo)
