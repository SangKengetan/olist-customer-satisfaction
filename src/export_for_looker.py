"""Mengekspor data siap-dashboard untuk Looker Studio (CSV, UTF-8) dan memverifikasinya.

Jalankan dari folder project (venv aktif), SETELAH build_clean.py dan run_analysis.py:
    python src/export_for_looker.py
Opsional: argumen ke-1 = lokasi database lain.

Keluaran di exports/looker/ (tidak di-commit):
    fact_orders.csv        1 baris per order  (tren, keterlambatan, skor, negara bagian, pelanggan)
    fact_order_items.csv   1 baris per item   (kategori produk)

Setelah ekspor, angka dihitung ulang dari CSV dan dibandingkan dengan reports/tables/*.csv
(hasil run_analysis.py). Skrip berhenti dengan kode 1 jika ada yang tidak cocok.
"""
import sys
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DB = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "olist.duckdb"
OUT = ROOT / "exports" / "looker"
REF = ROOT / "reports" / "tables"
OUT.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(DB), read_only=True)
ada = {r[0] for r in con.execute("SELECT table_name FROM information_schema.tables").fetchall()}
if "clean_orders" not in ada:
    sys.exit("Tabel clean_* belum ada. Jalankan dulu: python src/build_clean.py")

# Definisi sama persis dengan sql/05_analisis_bisnis.sql:
#   order valid     = status bukan canceled/unavailable
#   order pendapatan = order valid yang punya item (pendapatan = SUM(price), tanpa ongkir)
#   ruang lingkup pengiriman = clean_orders.is_analysis_scope
# Nama kolom hanya huruf/angka/garis bawah (syarat Looker Studio). Tanggal dalam format
# YYYYMMDD / YYYYMM supaya bisa dipilih sebagai tipe Date di Looker Studio.
SQL_ORDERS = """
WITH items AS (
    SELECT order_id, COUNT(*) AS n_items, SUM(price) AS revenue
    FROM order_items GROUP BY 1
),
dasar AS (
    SELECT o.*, c.customer_unique_id, c.customer_state,
           (o.order_status NOT IN ('canceled', 'unavailable')) AS valid
    FROM clean_orders o
    JOIN customers c USING (customer_id)
),
urutan AS (
    SELECT order_id,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id) AS order_seq,
           COUNT(*)     OVER (PARTITION BY customer_unique_id)                                             AS customer_total_orders
    FROM dasar WHERE valid
)
SELECT d.order_id,
       strftime(d.order_purchase_timestamp, '%Y%m%d')                          AS purchase_date,
       strftime(d.order_purchase_timestamp, '%Y%m')                            AS purchase_ym,
       (strftime(d.order_purchase_timestamp, '%Y%m') BETWEEN '201701' AND '201808')::INT AS in_trend_period,
       d.order_status,
       d.valid::INT                                                            AS is_valid_order,
       (d.valid AND i.order_id IS NOT NULL)::INT                               AS is_revenue_order,
       d.customer_unique_id,
       d.customer_state,
       'BR-' || d.customer_state                                               AS state_iso,
       COALESCE(i.n_items, 0)                                                  AS n_items,
       CASE WHEN d.valid AND i.order_id IS NOT NULL THEN ROUND(i.revenue, 2) END AS revenue,
       d.is_analysis_scope::INT                                                AS is_in_scope,
       CASE WHEN d.is_analysis_scope THEN d.is_late::INT END                   AS is_late,
       CASE WHEN d.is_analysis_scope THEN d.delay_days END                     AS delay_days,
       CASE WHEN d.is_analysis_scope THEN d.delivery_days END                  AS delivery_days,
       CASE WHEN NOT d.is_analysis_scope THEN NULL
            WHEN NOT d.is_late           THEN '0. Tepat waktu'
            WHEN d.delay_days <= 1       THEN '1. Telat hingga 1 hari'
            WHEN d.delay_days <= 3       THEN '2. Telat 1-3 hari'
            WHEN d.delay_days <= 7       THEN '3. Telat 3-7 hari'
            WHEN d.delay_days <= 14      THEN '4. Telat 7-14 hari'
            ELSE                              '5. Telat lebih dari 14 hari' END AS delay_bucket,
       r.review_score,
       u.order_seq,
       u.customer_total_orders,
       CASE WHEN d.valid THEN (u.customer_total_orders > 1)::INT END           AS is_repeat_customer
FROM dasar d
LEFT JOIN items i USING (order_id)
LEFT JOIN clean_order_reviews r USING (order_id)
LEFT JOIN urutan u USING (order_id)
ORDER BY d.order_purchase_timestamp, d.order_id
"""

SQL_ITEMS = """
SELECT i.order_id,
       i.order_item_id,
       strftime(o.order_purchase_timestamp, '%Y%m')                           AS purchase_ym,
       (strftime(o.order_purchase_timestamp, '%Y%m') BETWEEN '201701' AND '201808')::INT AS in_trend_period,
       (o.order_status NOT IN ('canceled', 'unavailable'))::INT               AS is_revenue_order,
       p.product_category_en,
       c.customer_state,
       'BR-' || c.customer_state                                              AS state_iso,
       ROUND(i.price, 2)                                                      AS price
FROM order_items i
JOIN clean_orders   o USING (order_id)
JOIN customers      c USING (customer_id)
JOIN clean_products p USING (product_id)
ORDER BY i.order_id, i.order_item_id
"""

for nama, sql in [("fact_orders", SQL_ORDERS), ("fact_order_items", SQL_ITEMS)]:
    path = (OUT / f"{nama}.csv").as_posix()
    con.execute(f"COPY ({sql}) TO '{path}' (FORMAT CSV, HEADER, DELIMITER ',')")
    n = con.execute(f"SELECT COUNT(*) FROM read_csv('{path}')").fetchone()[0]
    mb = (OUT / f"{nama}.csv").stat().st_size / 1e6
    print(f"{nama}.csv  {n:>8,} baris  {mb:5.1f} MB")

# ----------------------------------------------------------------- verifikasi
print("\nVerifikasi terhadap reports/tables (hasil sql/05):")
if not (REF / "q1_tren_bulanan.csv").exists():
    sys.exit("reports/tables belum ada. Jalankan dulu: python src/run_analysis.py")

fo = (OUT / "fact_orders.csv").as_posix()
fi = (OUT / "fact_order_items.csv").as_posix()
q = lambda s: con.execute(s).df()
hasil = []


def cek(nama, nilai_csv, nilai_ref, tol=0.011):
    ok = abs(float(nilai_csv) - float(nilai_ref)) <= tol
    hasil.append(ok)
    print(f"  {'OK  ' if ok else 'GAGAL'} {nama:<52} csv={nilai_csv:<14,.2f} ref={nilai_ref:,.2f}")


# Q1 tren bulanan (hanya periode tren)
ref = pd.read_csv(REF / "q1_tren_bulanan.csv")
got = q(f"""SELECT CAST(purchase_ym AS VARCHAR) AS purchase_ym, COUNT(*) n, SUM(revenue) rev FROM read_csv('{fo}')
            WHERE is_revenue_order = 1 AND in_trend_period = 1 GROUP BY 1 ORDER BY 1""")
ref["ym"] = ref.bulan.str.replace("-", "")
m = ref.merge(got, left_on="ym", right_on="purchase_ym")
cek("Q1 jumlah bulan", len(m), len(ref), 0)
cek("Q1 total order 20 bulan", m.n.sum(), ref.jumlah_order.sum(), 0)
cek("Q1 total pendapatan 20 bulan", m.rev.sum(), ref.pendapatan.sum())
cek("Q1 selisih terbesar per bulan (pendapatan)", (m.rev - m.pendapatan).abs().max(), 0)

# Q2 top 10 kategori (dari fact_order_items)
ref = pd.read_csv(REF / "q2_top10_kategori.csv")
got = q(f"""SELECT product_category_en k, SUM(price) rev, COUNT(DISTINCT order_id) n FROM read_csv('{fi}')
            WHERE is_revenue_order = 1 GROUP BY 1 ORDER BY 2 DESC LIMIT 10""")
cek("Q2 urutan 10 kategori sama (1=ya)", int(list(got.k) == list(ref.kategori)), 1, 0)
cek("Q2 total pendapatan top 10", got.rev.sum(), ref.pendapatan.sum())
cek("Q2 total order top 10", got.n.sum(), ref.jumlah_order.sum(), 0)

# Q3 keterlambatan
ref = pd.read_csv(REF / "q3a_ringkasan_keterlambatan.csv").iloc[0]
g = q(f"SELECT COUNT(*) n, SUM(is_late) late FROM read_csv('{fo}') WHERE is_in_scope = 1").iloc[0]
cek("Q3a order dalam ruang lingkup", g.n, ref.order_dalam_scope, 0)
cek("Q3a order terlambat", g.late, ref.order_terlambat, 0)
cek("Q3a persen terlambat", round(100 * g.late / g.n, 2), ref.pct_terlambat)
ref = pd.read_csv(REF / "q3b_distribusi_keterlambatan.csv")
got = q(f"""SELECT LEFT(delay_bucket, 1) b, COUNT(*) n FROM read_csv('{fo}')
            WHERE is_in_scope = 1 AND delay_bucket NOT LIKE '0.%' GROUP BY 1 ORDER BY 1""")
cek("Q3b jumlah order per bucket (selisih maks)", (got.n.values - ref.jumlah_order.values).__abs__().max(), 0, 0)

# Q4 skor
ref = pd.read_csv(REF / "q4_skor_tepat_waktu_vs_terlambat.csv").set_index("status_pengiriman")
got = q(f"""SELECT is_late, COUNT(review_score) n, AVG(review_score) s FROM read_csv('{fo}')
            WHERE is_in_scope = 1 GROUP BY 1""").set_index("is_late")
cek("Q4 rata-rata skor terlambat", round(got.loc[1, "s"], 3), ref.loc["Terlambat", "rata2_skor"], 0.0006)
cek("Q4 rata-rata skor tepat waktu", round(got.loc[0, "s"], 3), ref.loc["Tepat waktu", "rata2_skor"], 0.0006)
cek("Q4 jumlah order ber-review terlambat", got.loc[1, "n"], ref.loc["Terlambat", "order_ber_review"], 0)

# Q5 negara bagian
ref = pd.read_csv(REF / "q5_per_negara_bagian.csv")
got = q(f"""SELECT customer_state st, SUM(revenue) rev, AVG(is_late) * 100 late FROM read_csv('{fo}')
            GROUP BY 1""").set_index("st")
r = ref.set_index("negara_bagian")
cek("Q5 jumlah negara bagian", len(got), len(r), 0)
cek("Q5 selisih pendapatan terbesar per negara bagian", (got.rev - r.pendapatan).abs().max(), 0)
cek("Q5 selisih % terlambat terbesar per negara bagian", (got.late.round(2) - r.pct_terlambat).abs().dropna().max(), 0)

# Q6 pembeli ulang (definisi utama: order valid)
ref = pd.read_csv(REF / "q6_pelanggan_repeat.csv")
ref = ref[ref.definisi_order.str.contains("utama")].iloc[0]
g = q(f"""SELECT COUNT(DISTINCT customer_unique_id) tot,
                 COUNT(DISTINCT CASE WHEN is_repeat_customer = 1 THEN customer_unique_id END) rep
          FROM read_csv('{fo}') WHERE is_valid_order = 1""").iloc[0]
cek("Q6 total pelanggan", g.tot, ref.total_pelanggan, 0)
cek("Q6 pelanggan repeat", g.rep, ref.pelanggan_repeat, 0)
cek("Q6 persen repeat", round(100 * g.rep / g.tot, 2), ref.pct_repeat)

# Pemeriksaan struktur CSV
cek("Order ganda di fact_orders (harus 0)",
    q(f"SELECT COUNT(*) - COUNT(DISTINCT order_id) d FROM read_csv('{fo}')").d[0], 0, 0)
cek("Ukuran fact_orders di bawah 100 MB (1=ya)", int((OUT / "fact_orders.csv").stat().st_size < 100e6), 1, 0)

print(f"\n{'SEMUA CEK LULUS' if all(hasil) else 'ADA CEK YANG GAGAL'} ({sum(hasil)}/{len(hasil)})")
con.close()
sys.exit(0 if all(hasil) else 1)
