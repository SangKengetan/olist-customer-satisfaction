"""Membangun tabel bersih (clean_*) di olist.duckdb dari sql/04_buat_tabel_bersih.sql,
lalu mencetak perbandingan jumlah baris mentah vs bersih.

Jalankan dari folder project (venv aktif):
    python src/build_clean.py
Opsional: argumen ke-1 = lokasi database lain.
Tabel mentah TIDAK diubah. Aman diulang.
"""
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
db_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "olist.duckdb"
sql_file = ROOT / "sql" / "04_buat_tabel_bersih.sql"

con = duckdb.connect(str(db_path))
con.execute(sql_file.read_text(encoding="utf-8"))

pairs = [
    ("orders", "clean_orders"),
    ("reviews", "clean_order_reviews"),
    ("products", "clean_products"),
    ("payments", "clean_payments"),
    ("geolocation", "clean_geolocation"),
    ("category_translation", "clean_category_translation"),
]
print(f"{'mentah':<22}{'baris':>10}   {'bersih':<28}{'baris':>10}")
for raw, clean in pairs:
    n_raw = con.execute(f"SELECT COUNT(*) FROM {raw}").fetchone()[0]
    n_clean = con.execute(f"SELECT COUNT(*) FROM {clean}").fetchone()[0]
    print(f"{raw:<22}{n_raw:>10,}   {clean:<28}{n_clean:>10,}")

print("\nRingkasan flag di clean_orders:")
row = con.execute("""
    SELECT COUNT(*) AS total,
           COUNT(*) FILTER (WHERE is_delivered)                      AS delivered,
           COUNT(*) FILTER (WHERE flag_tanggal_tidak_logis)          AS tanggal_tidak_logis,
           COUNT(*) FILTER (WHERE flag_delivered_tanpa_tgl_tiba)     AS delivered_tanpa_tgl_tiba,
           COUNT(*) FILTER (WHERE is_analysis_scope)                 AS dalam_ruang_lingkup
    FROM clean_orders
""").fetchone()
for k, v in zip(["total order", "delivered", "tanggal tidak logis", "delivered tanpa tgl tiba", "DALAM RUANG LINGKUP"], row):
    print(f"  {k:<26}{v:>8,}")
con.close()
