import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean_common import *
import clean_grc, clean_contractor, clean_liaison, clean_plant
os.makedirs(OUT, exist_ok=True)
pseudo = Pseudo()
E, G = clean_liaison.run(pseudo)
areas = {'GRC': clean_grc.run(pseudo), 'CONTRACTOR_COST': clean_contractor.run(pseudo), 'LIAISON_ESIC': E, 'LIAISON_GOVT': G, 'PLANT_VISIT': clean_plant.run(pseudo)}
for n, A in areas.items():
    write_book(OUT + f'{n}_cleaned_FULL_CONFIDENTIAL.xlsx', A, pseudo, dev=False)
    write_book(OUT + f'{n}_cleaned_DEV_pseudonymized.xlsx', A, pseudo, dev=True)
    print(n, 'cleaned', len(A.cleaned), 'dups', len(A.duplicates), 'rejected', len(A.rejected), 'review', len(A.review), 'log', len(A.log))
key_book(OUT + 'PSEUDONYM_KEY_CONFIDENTIAL.xlsx', pseudo)
