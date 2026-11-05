# Panduan Dashboard Power BI

Tujuan: menyajikan 6 pertanyaan bisnis sebagai dashboard interaktif di **Power BI Desktop**. Data memakai file yang sama dengan panduan Looker Studio (`exports/looker/*.csv`), yang sudah diverifikasi sama persis dengan `reports/tables/` (22 pengecekan otomatis di `src/export_for_looker.py`).

> Setiap halaman punya **angka acuan**. Setelah membuat sebuah visual, cocokkan angkanya. Kalau berbeda, ada filter, tipe data, atau relasi yang salah.

Power BI Desktop gratis, hanya untuk Windows, dan data sebesar ini (sekitar 23 MB CSV) ringan untuk RAM 8 GB.

## 0. Persiapan data

Jalankan di PowerShell dengan venv aktif (bila belum):
```powershell
python src/build_clean.py
python src/run_analysis.py
python src/export_for_looker.py
```
Skrip harus berakhir dengan "SEMUA CEK LULUS (22/22)". Hasilnya `exports/looker/fact_orders.csv` dan `exports/looker/fact_order_items.csv`.

## 1. Impor CSV

1. Buka Power BI Desktop → **Get data** → **Text/CSV**.
2. Pilih `fact_orders.csv` → **Transform Data** (jangan langsung Load).
3. Ulangi untuk `fact_order_items.csv`: **New Source** → **Text/CSV**.

Power BI membaca file ini sebagai UTF-8 secara otomatis. Kolom kosong menjadi `null`, dan itu memang diinginkan (misalnya `is_late` kosong untuk order di luar ruang lingkup pengiriman).

## 2. Rapikan tipe data di Power Query

Di editor Power Query, pada query **fact_orders**:

| Kolom | Tipe |
|---|---|
| `order_id`, `customer_unique_id`, `customer_state`, `state_iso`, `order_status`, `delay_bucket` | Text |
| `purchase_ym`, `in_trend_period`, `is_valid_order`, `is_revenue_order`, `n_items`, `is_in_scope`, `is_late`, `review_score`, `order_seq`, `customer_total_orders`, `is_repeat_customer` | Whole Number |
| `revenue`, `delay_days`, `delivery_days` | Decimal Number |
| `purchase_date` | **Date** (lihat langkah di bawah) |

`purchase_date` berformat YYYYMMDD (misalnya `20170115`) dan terbaca sebagai angka. Ubah ke tanggal: pilih kolomnya → **Transform → Data Type → Text**, lalu buka **Advanced Editor** atau tambahkan langkah baru (**fx**) dengan rumus:

```
= Table.TransformColumns(#"Changed Type", {{"purchase_date", each Date.FromText(_, [Format="yyyyMMdd"]), type date}})
```
(Nama langkah sebelumnya, `#"Changed Type"`, bisa berbeda di file Anda. Pakai nama langkah terakhir yang ada.)

Pada query **fact_order_items**: `price` → Decimal Number, `is_revenue_order`, `in_trend_period`, `order_item_id` → Whole Number, sisanya Text.

Klik **Close & Apply**.

## 3. Model data

Di tampilan **Model**:

1. Pastikan relasi `fact_orders[order_id]` → `fact_order_items[order_id]` ada: **One (1) ke Many (*)**, arah filter **Single** (dari orders ke items). Kalau tidak terbentuk otomatis, tarik kolom `order_id` dari satu tabel ke yang lain.
2. Dengan relasi ini, filter periode, negara bagian, dan status pada `fact_orders` otomatis ikut memfilter grafik kategori. Itu keunggulan dibanding Looker Studio.
3. Buat tabel kalender: **Table view → New table**:
```
Kalender =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2016, 9, 1 ), DATE ( 2018, 10, 31 ) ),
    "TahunBulan", FORMAT ( [Date], "YYYY-MM" )
)
```
4. Klik tabel `Kalender` → **Table tools → Mark as date table** → pilih kolom `Date`.
5. Hubungkan `Kalender[Date]` → `fact_orders[purchase_date]` (**One ke Many**, Single).
6. Kolom `Kalender[TahunBulan]` tidak perlu diatur urutannya: teks berformat `YYYY-MM` sudah berurutan benar.

Disarankan juga mematikan **File → Options → Current File → Data Load → Time intelligence → Auto date/time** agar model tidak membuat tabel tanggal tersembunyi.

## 4. Measures (DAX)

Buat tabel kosong untuk menampung measure: **Home → Enter data** → beri nama `_Ukuran`. Lalu **New measure** untuk tiap baris:

```
Pendapatan = SUM ( fact_orders[revenue] )

Jumlah Order =
CALCULATE ( DISTINCTCOUNT ( fact_orders[order_id] ), fact_orders[is_revenue_order] = 1 )

Nilai Rata2 Order = DIVIDE ( [Pendapatan], [Jumlah Order] )

Pct Terlambat = AVERAGE ( fact_orders[is_late] )

Skor Rata2 =
CALCULATE ( AVERAGE ( fact_orders[review_score] ), fact_orders[is_in_scope] = 1 )

Pelanggan Unik =
CALCULATE ( DISTINCTCOUNT ( fact_orders[customer_unique_id] ), fact_orders[is_valid_order] = 1 )

Pelanggan Repeat =
CALCULATE ( DISTINCTCOUNT ( fact_orders[customer_unique_id] ), fact_orders[is_repeat_customer] = 1 )

Pct Pembeli Ulang = DIVIDE ( [Pelanggan Repeat], [Pelanggan Unik] )

Pendapatan Bulan Lalu =
CALCULATE ( [Pendapatan], DATEADD ( Kalender[Date], -1, MONTH ) )

MoM Pendapatan = DIVIDE ( [Pendapatan] - [Pendapatan Bulan Lalu], [Pendapatan Bulan Lalu] )

Pendapatan Kategori =
CALCULATE ( SUM ( fact_order_items[price] ), fact_order_items[is_revenue_order] = 1 )
```

Mengapa begini:
- `revenue` hanya terisi untuk order valid yang punya item, dan `is_late` / `delay_bucket` hanya terisi untuk order dalam ruang lingkup. Jadi `SUM` dan `AVERAGE` (yang mengabaikan kosong) sudah mengikuti definisi di laporan.
- Format: `Pct Terlambat`, `Pct Pembeli Ulang`, `MoM Pendapatan` → **Percentage**. `Skor Rata2` → desimal 2-3 angka.

## 5. Susun halaman

### Halaman 1: Ringkasan dan tren (pertanyaan 1)
- Pasang filter **di halaman ini saja** (panel Filters → *Filters on this page*): `fact_orders[in_trend_period]` bernilai **1** (Jan 2017 - Agu 2018).
- **Card**: Pendapatan, Jumlah Order, Nilai Rata2 Order.
- **Line chart**: sumbu X `Kalender[TahunBulan]`, nilai `Pendapatan`. Satu lagi untuk `Jumlah Order`. Jangan gabungkan dua skala berbeda di satu grafik.
- **Table**: `TahunBulan`, `Pendapatan`, `Jumlah Order`, `MoM Pendapatan`.
- **Slicer**: `customer_state` (dropdown) dan `Kalender[Date]` (Between).

Angka acuan (dengan filter halaman ini): Pendapatan **13.449.530**, Jumlah Order **97.905**. MoM: Jan 2017 kosong, Feb 2017 **+104%**, Mar 2017 **+50,4%**, Nov 2017 **+52,1%**, Des 2017 **-26,1%**.

### Halaman 2: Pengiriman dan kepuasan (pertanyaan 3 dan 4)
Tanpa filter periode.
- **Card**: Pct Terlambat. Acuan **8,13%**.
- **Bar chart** distribusi keterlambatan: sumbu `delay_bucket`, nilai `Jumlah Order`. Filter visual: `delay_bucket` **bukan** "0. Tepat waktu" dan bukan kosong.
- **Bar chart** skor per bucket: sumbu `delay_bucket`, nilai `Skor Rata2`. Filter visual: `delay_bucket` bukan kosong.
- **Dua card** skor untuk `is_late = 0` dan `is_late = 1` (filter visual pada tiap card).

Angka acuan: order per bucket telat **1.294 / 1.370 / 1.818 / 1.786 / 1.555** (ini jumlah order dalam ruang lingkup, bukan hanya order ber-review). Skor: tepat waktu **4,29**, telat hingga 1 hari **4,03**, 1-3 hari **3,51**, 3-7 hari **2,32**, 7-14 hari **1,74**, lebih dari 14 hari **1,71**. Terlambat vs tepat waktu **2,56** vs **4,29**.

Catatan: `Jumlah Order` menghitung order bukan item, dan `Pct Terlambat` hanya menghitung order dalam ruang lingkup karena `is_late` kosong di luar itu.

### Halaman 3: Wilayah (pertanyaan 5)
Tanpa filter periode.
- **Table**: `customer_state`, `Pendapatan`, `Jumlah Order`, `Pct Terlambat`. Urutkan `Pendapatan` menurun. Beri **conditional formatting** (background) pada `Pct Terlambat`: merah bila di atas 8,13%.
- **Peta** (opsional): Filled map dengan lokasi `state_iso` atau `customer_state`. Peta Power BI mencari lokasi lewat layanan Bing, dan kode dua huruf bisa ambigu. Pilih kolom → **Column tools → Data category → State or Province**. Peta mungkin juga perlu diaktifkan di **File → Options → Security → Map and Filled Map visuals**. **Belum saya uji.** Kalau hasilnya salah atau kosong, pakai tabel dan diagram batang saja.

Angka acuan: SP pendapatan **5.163.867**, terlambat **5,9%**. RJ pendapatan **1.811.623**, terlambat **13,5%**. AL terlambat **23,9%**. Total 27 negara bagian.

### Halaman 4: Kategori dan pelanggan (pertanyaan 2 dan 6)
Tanpa filter periode.
- **Bar chart horizontal**: sumbu `fact_order_items[product_category_en]`, nilai `Pendapatan Kategori`. Pada panel Filters, untuk visual ini: `product_category_en` → **Top N** → **Top 10** by `Pendapatan Kategori`.
- **Card**: Pct Pembeli Ulang. Acuan **3,04%**. Tambah card Pelanggan Unik (**94.990**) dan Pelanggan Repeat (**2.888**).

Angka acuan top 10 (urut): health_beauty 1,26 jt, watches_gifts 1,20 jt, bed_bath_table 1,04 jt, sports_leisure 0,98 jt, computers_accessories 0,90 jt, furniture_decor, housewares, cool_stuff, auto, garden_tools.

## 6. Merapikan

1. Beri judul yang berupa kesimpulan, misalnya "Order terlambat mendapat skor 2,56 vs 4,29", bukan hanya "Skor Review".
2. Satu warna utama untuk semua grafik, satu warna kedua hanya untuk pembanding (terlambat vs tepat waktu).
3. Tambahkan kotak teks di tiap halaman: sumber (Olist, Kaggle), periode, dan definisi pendapatan (tanpa ongkir).
4. Beri nama halaman yang jelas dan sembunyikan tabel `_Ukuran` serta kolom teknis dari tampilan laporan.

## 7. Berbagi hasil

| Cara | Catatan |
|---|---|
| **File `.pbix` di GitHub** | Paling mudah. Simpan di folder `dashboards/`. Data ikut tersimpan dalam file (turunan dataset Kaggle), jadi periksa lisensi dataset dulu |
| **Ekspor PDF** | **File → Export → Export to PDF**. Cocok untuk dilampirkan di CV atau README |
| **Screenshot** | Simpan halaman terbaik di `reports/figures/` dan tampilkan di README |
| **Power BI Service** (publikasi online) | Biasanya butuh akun kerja/sekolah, tidak cukup dengan email pribadi. Fitur "Publish to web" membuat laporan terbuka untuk siapa pun yang punya tautan, dan sering dinonaktifkan oleh admin organisasi. Periksa dulu apakah akun Anda bisa |

Kalau tujuannya portofolio dan Anda tidak punya akun kerja, kombinasi **.pbix + PDF + screenshot di README** sudah cukup. Dashboard Looker Studio bisa menjadi versi yang dapat diklik publik.

## 8. Checklist

- [ ] `export_for_looker.py` selesai dengan "SEMUA CEK LULUS (22/22)"
- [ ] `purchase_date` bertipe Date, relasi `fact_orders` → `fact_order_items` dan `Kalender` → `fact_orders` ada
- [ ] Semua measure dibuat dan formatnya benar (persen untuk Pct dan MoM)
- [ ] Semua angka acuan di tiap halaman cocok
- [ ] Filter `in_trend_period = 1` hanya di halaman 1
- [ ] Peta bekerja, atau sudah diganti tabel
- [ ] File `.pbix` dan PDF diekspor, dan screenshot ditambahkan ke README
