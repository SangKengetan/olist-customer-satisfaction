"""Menjalankan file .sql ke olist.duckdb dan mencetak hasil tiap query.

Contoh (dari folder project, venv aktif):
    python src/run_sql.py sql/01_profil_tabel.sql
    python src/run_sql.py sql/02_cek_relasi.sql
Opsional: argumen ke-2 = lokasi database lain.
"""
import sys
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sql_file = Path(sys.argv[1])
db_path = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "olist.duckdb"

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", None)
pd.set_option("display.max_rows", None)

con = duckdb.connect(str(db_path), read_only=True)

# Pisahkan per query. Aman karena tidak ada ';' di dalam komentar/string pada file kita.
queries = [q.strip() for q in sql_file.read_text(encoding="utf-8").split(";") if q.strip()]
for q in queries:
    if not any(line.strip() and not line.strip().startswith("--") for line in q.splitlines()):
        continue  # blok yang hanya berisi komentar
    header = next((l for l in q.splitlines() if l.startswith("-- ----------")), "")
    print("\n" + header)
    print(con.execute(q).df().to_string(index=False))
