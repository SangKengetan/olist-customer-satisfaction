# Panduan Dashboard Looker Studio

Tujuan: menyajikan 6 pertanyaan bisnis sebagai dashboard interaktif. Data berasal dari `exports/looker/` (dibuat oleh `src/export_for_looker.py`).
Looker Studio tidak bisa membaca DuckDB, jadi data diunggah sebagai CSV. Angka yang diekspor sudah diverifikasi sama persis dengan `reports/tables/` (22 pengecekan otomatis).

> Setiap bagian di bawah punya **angka acuan**. Setelah membuat sebuah grafik, cocokkan angkanya. Kalau berbeda, ada filter atau definisi yang salah.

## 0. Persiapan data (di laptop)

```powershell
python src/build_clean.py
python src/run_analysis.py
python src/export_for_looker.py
```
Hasilnya: `exports/looker/fact_orders.csv` (99.441 baris, 15 MB) dan `exports/looker/fact_order_items.csv` (112.650 baris, 8 MB). Skrip harus berakhir dengan "SEMUA CEK LULUS (22/22)".

Dua file ini sengaja tidak di-commit ke Git (`exports/` ada di `.gitignore`), karena turunan dari dataset Kaggle. Periksa lisensi dataset di halaman Kaggle-nya sebelum membagikan dashboard secara publik, dan cantumkan sumbernya (Olist, Kaggle).

## 1. Unggah data ke Looker Studio

1. Buka [lookerstudio.google.com](https://lookerstudio.google.com) dan login dengan akun Google.
2. **Create** (Buat) → **Data source** → pilih konektor **File Upload**.
3. Pilih `fact_orders.csv`, lalu beri nama sumber data: `olist_fact_orders`. Hubungkan.
4. Ulangi untuk `fact_order_items.csv` dengan nama `olist_fact_order_items`.

Batas konektor ini: 100 MB per dataset, UTF-8, baris pertama header, nama kolom hanya huruf/angka/garis bawah. Semua sudah dipenuhi file ekspor. **Data tidak diperbarui otomatis.** Kalau Anda mengunggah file baru ke dataset yang sama, barisnya ditambahkan (bukan menimpa), sehingga bisa terduplikasi. Kalau datanya berubah, buat dataset baru atau hapus yang lama.

## 2. Atur tipe kolom (di editor sumber data)

Di editor sumber data `olist_fact_orders`, ubah tipe kolom berikut:

| Kolom | Ubah tipe menjadi | Catatan |
|---|---|---|
| `purchase_date` | Date (YYYYMMDD) | untuk filter rentang tanggal |
| `purchase_ym` | Year Month (YYYYMM) | sumbu x grafik tren |
| `state_iso` | Geo → Country Subdivision (1st level) | untuk peta. Isinya kode ISO seperti `BR-SP` |
| `revenue`, `n_items`, `delay_days`, `delivery_days`, `review_score` | Number | biasanya sudah otomatis |

Pada `olist_fact_order_items`: `purchase_ym` → Year Month (YYYYMM), `state_iso` → Geo (sama seperti di atas).

Kolom `is_...` bernilai 1/0 sehingga bisa dirata-rata. **Peta belum saya uji di Looker Studio.** Kalau peta kosong atau salah, pakai `customer_state` pada diagram batang atau tabel.

## 3. Buat field terhitung (calculated fields)

Di `olist_fact_orders` → **Add a field**. Salin rumus persis (huruf besar-kecil nama kolom penting).

| Nama field | Rumus | Format |
|---|---|---|
| Pendapatan | `SUM(revenue)` | Currency / Number |
| Jumlah Order | `COUNT_DISTINCT(CASE WHEN is_revenue_order = 1 THEN order_id END)` | Number |
| Nilai Rata2 Order | `SUM(revenue) / COUNT_DISTINCT(CASE WHEN is_revenue_order = 1 THEN order_id END)` | Number |
| Pct Terlambat | `AVG(is_late)` | Percent |
| Skor Rata2 | `AVG(CASE WHEN is_in_scope = 1 THEN review_score END)` | Number (3 desimal) |
| Pelanggan Unik | `COUNT_DISTINCT(CASE WHEN is_valid_order = 1 THEN customer_unique_id END)` | Number |
| Pelanggan Repeat | `COUNT_DISTINCT(CASE WHEN is_repeat_customer = 1 THEN customer_unique_id END)` | Number |
| Pct Pembeli Ulang | `COUNT_DISTINCT(CASE WHEN is_repeat_customer = 1 THEN customer_unique_id END) / COUNT_DISTINCT(CASE WHEN is_valid_order = 1 THEN customer_unique_id END)` | Percent |

Mengapa begini: kolom `revenue` hanya terisi untuk order valid yang punya item, dan `is_late` / `delay_bucket` hanya terisi untuk order dalam ruang lingkup pengiriman. Jadi rata-rata dan jumlah otomatis mengikuti definisi di laporan.

## 4. Susun halaman

Gunakan filter berikut pada grafik tren: **`in_trend_period` sama dengan 1** (Jan 2017 - Agu 2018). Bulan lain hanya berisi 1-290 order dan menyesatkan.

### Halaman 1: Ringkasan dan tren (pertanyaan 1)
- **Scorecard** (filter `in_trend_period = 1`): Pendapatan, Jumlah Order, Nilai Rata2 Order, Pct Terlambat.
- **Time series** (dimensi `purchase_ym`, metrik Pendapatan dan di grafik terpisah Jumlah Order). Jangan taruh dua metrik berbeda skala dalam satu grafik dengan dua sumbu.
- **Tabel** untuk MoM: dimensi `purchase_ym` diurutkan naik, metrik Pendapatan, lalu tambahkan **Quick calculation → Percent difference**. Pastikan urutan bulan naik.
- **Kontrol:** *Date range control* pada `purchase_date`, dan *Drop-down* pada `customer_state`.

Angka acuan (filter `in_trend_period = 1`): Pendapatan **13.449.530**, Jumlah Order **97.905**. Feb 2017 MoM pendapatan **+104%**, Mar 2017 **+50,4%**, Nov 2017 **+52,1%**, Des 2017 **-26,1%**.

### Halaman 2: Pengiriman dan kepuasan (pertanyaan 3 dan 4)
- **Scorecard** Pct Terlambat. Acuan: **8,13%**.
- **Diagram batang** distribusi keterlambatan: dimensi `delay_bucket`, metrik Record Count atau Jumlah Order. Filter: `delay_bucket` **bukan** "0. Tepat waktu" dan bukan null.
- **Diagram batang** skor menurut lamanya keterlambatan: dimensi `delay_bucket`, metrik Skor Rata2. Filter: `delay_bucket` tidak null.
- **Scorecard** Skor Rata2 untuk dua kelompok (filter `is_late = 0` dan `is_late = 1`).

Angka acuan: order per bucket telat **1.294 / 1.370 / 1.818 / 1.786 / 1.555**. Skor: tepat waktu **4,29**, telat hingga 1 hari **4,03**, 1-3 hari **3,51**, 3-7 hari **2,32**, 7-14 hari **1,74**, lebih dari 14 hari **1,71**. Terlambat vs tepat waktu: **2,56** vs **4,29**.

### Halaman 3: Wilayah (pertanyaan 5)
- **Peta** (Geo chart) dengan dimensi `state_iso`, ukuran/warna metrik Pendapatan.
- **Tabel** dengan dimensi `customer_state`, metrik Pendapatan, Jumlah Order, Pct Terlambat. Urutkan Pendapatan menurun.
- Tambahkan **kolom Pct Terlambat dengan conditional formatting** (merah untuk nilai di atas rata-rata nasional 8,13%).

Angka acuan: SP pendapatan **5.163.867** (38,3%), terlambat **5,9%**. RJ pendapatan **1.811.623**, terlambat **13,5%**. AL terlambat **23,9%**. Total 27 negara bagian.

### Halaman 4: Kategori dan pelanggan (pertanyaan 2 dan 6)
- **Diagram batang horizontal** top 10 kategori, memakai sumber `olist_fact_order_items`: dimensi `product_category_en`, metrik `SUM(price)`. Filter: `is_revenue_order = 1`. Urutkan menurun, tampilkan 10 baris.
- **Scorecard** Pct Pembeli Ulang (sumber `olist_fact_orders`). Acuan: **3,04%**, Pelanggan Unik **94.990**, Pelanggan Repeat **2.888**.

Angka acuan top 10 (urut): health_beauty 1,26 jt, watches_gifts 1,20 jt, bed_bath_table 1,04 jt, sports_leisure 0,98 jt, computers_accessories 0,90 jt, furniture_decor, housewares, cool_stuff, auto, garden_tools.

**Catatan penting:** kontrol filter hanya berlaku untuk grafik dengan sumber data yang sama. Karena grafik kategori memakai sumber lain, tambahkan kontrol terpisah di halaman itu atau biarkan tanpa filter.

## 5. Merapikan dan membagikan

1. Beri judul yang berupa kesimpulan, misalnya "Order terlambat mendapat skor 2,56 vs 4,29", bukan hanya "Skor Review".
2. Pakai satu warna utama untuk semua grafik, warna kedua hanya untuk pembanding (terlambat vs tepat waktu).
3. Tambahkan teks kecil di tiap halaman: sumber (Olist, Kaggle), periode, dan definisi pendapatan (tanpa ongkir).
4. **Share** → atur akses ke "Anyone with the link can view" bila ingin dilihat perekrut. Pikirkan dulu apakah dataset ini boleh dibagikan publik (lisensi).
5. Pasang tautan dashboard di bagian atas `README.md`, dan screenshot halaman terbaik di `reports/figures/`.

## 6. Memeriksa hasil (checklist)

- [ ] `export_for_looker.py` selesai dengan "SEMUA CEK LULUS (22/22)"
- [ ] Tipe `purchase_date` dan `purchase_ym` sudah diubah ke tipe tanggal
- [ ] Semua angka acuan di atas cocok dengan dashboard
- [ ] Grafik tren memakai filter `in_trend_period = 1`
- [ ] Peta menampilkan 27 negara bagian (atau diganti tabel bila tidak jalan)
- [ ] Dashboard sudah dicoba dibuka lewat jendela incognito sebelum tautannya dikirim
