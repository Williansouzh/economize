"""Rendimento habitual de todos os trabalhos (VD4019) por faixa de idade, a partir dos microdados da PNAD Contínua."""
import json, subprocess, sys
from collections import defaultdict

zip_path = sys.argv[1]
GROUPS = [(18, 24), (25, 29), (30, 39), (40, 49), (50, 59), (60, 200)]
REGION = {"1": "N", "2": "NE", "3": "SE", "4": "S", "5": "CO"}
data = defaultdict(list)  # chave -> [(renda, peso)]
p = subprocess.Popen(["unzip", "-p", zip_path], stdout=subprocess.PIPE)
n = 0
for line in p.stdout:
    if line[409:410] != b"1":  # VD4002 @0410: ocupado
        continue
    inc = line[443:451].strip()
    if not inc:
        continue
    inc = float(inc)
    if inc <= 0:
        continue
    age = int(line[103:106])
    w = float(line[49:64])
    reg = REGION[chr(line[5])]
    jobs = line[133:134] if False else None
    g = next((f"{a}-{b}" if b < 200 else f"{a}+" for a, b in GROUPS if a <= age <= b), None)
    if g is None:
        continue
    for k in ("BR|all", f"BR|{g}", f"{reg}|all", f"{reg}|{g}"):
        data[k].append((inc, w))
    n += 1

def stats(rows):
    rows.sort()
    total = sum(w for _, w in rows)
    mean = sum(v * w for v, w in rows) / total
    cuts, acc, out = [i / 20 for i in range(1, 20)], 0.0, []
    it = iter(cuts); c = next(it)
    for v, w in rows:
        acc += w
        while c is not None and acc >= c * total:
            out.append(round(v)); c = next(it, None)
    return {"mean": round(mean), "median": out[9], "p5_95": out, "n": len(rows)}

res = {k: stats(v) for k, v in sorted(data.items())}
json.dump(res, open(sys.argv[2], "w"), indent=1)
print(n)
for k, v in res.items():
    print(k, v["mean"], v["median"], v["n"])
