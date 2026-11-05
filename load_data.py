"""Memuat 9 file CSV Olist di folder data/ ke database DuckDB (olist.duckdb).

Cara pakai (dari folder project, venv aktif):
    python load_data.py                 # hasil: olist.duckdb di folder project
    python load_data.py lain.duckdb     # (opsional) nama/lokasi database lain

Skrip aman dijalankan berulang kali: tabel lama akan ditimpa.
"""
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent          # folder tempat skrip ini berada
DATA_DIR = ROOT / "data"
DB_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "olist.duckdb"

# nama_tabel: (nama_file_csv, {kolom: tipe_paksa})
# Kode pos HARUS VARCHAR: aslinya "09790" -> kalau dibaca sebagai angka
# menjadi 9790 dan angka 0 di depan hilang (merusak JOIN antar tabel).
ZIP = "VARCHAR"
TABLES = {
    "customers": ("olist_customers_dataset.csv", {"customer_zip_code_prefix": ZIP}),
    "geolocation": ("olist_geolocation_dataset.csv", {"geolocation_zip_code_prefix": ZIP}),
    "orders": ("olist_orders_dataset.csv", {}),
    "order_items": ("olist_order_items_dataset.csv", {}),
    "payments": ("olist_order_payments_dataset.csv", {}),
    "reviews": ("olist_order_reviews_dataset.csv", {}),
    "products": ("olist_products_dataset.csv", {}),
    "sellers": ("olist_sellers_dataset.csv", {"seller_zip_code_prefix": ZIP}),
    "category_translation": ("product_category_name_translation.csv", {}),
}


def main() -> None:
    missing = [f for f, _ in TABLES.values() if not (DATA_DIR / f).exists()]
    if missing:
        sys.exit(f"File CSV tidak ditemukan di {DATA_DIR}:\n  " + "\n  ".join(missing))

    con = duckdb.connect(str(DB_PATH))
    print(f"Database: {DB_PATH}\n")

    for name, (file, types) in TABLES.items():
        csv_path = (DATA_DIR / file).as_posix()      # garis miring '/' aman di Windows
        t0 = time.time()
        # klausa types hanya ditambahkan jika ada kolom yang perlu dipaksa
        types_sql = ""
        if types:
            pairs = ", ".join(f"'{col}': '{typ}'" for col, typ in types.items())
            types_sql = f", types = {{{pairs}}}"
        con.execute(
            f"""
            CREATE OR REPLACE TABLE {name} AS
            SELECT * FROM read_csv(?, header = true, sample_size = -1{types_sql})
            """,
            [csv_path],
        )
        n = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
        print(f"{name:<22} {n:>9,} baris   ({time.time() - t0:.1f} dtk)")

    con.close()
    print("\nSelesai.")


if __name__ == "__main__":
    main()
