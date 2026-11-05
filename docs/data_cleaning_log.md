# Data Cleaning Log - Olist Customer Satisfaction

Tanggal: 2026-10-28 | Database: `olist.duckdb` (DuckDB) | Angka di bawah berasal dari data asli yang sudah dijalankan.

## Prinsip

1. **Tabel mentah tidak pernah diubah atau dihapus.** Semua cleaning menghasilkan tabel baru berawalan `clean_`.
2. **Utamakan flag daripada menghapus.** Baris bermasalah diberi kolom `flag_*` supaya bisa disertakan atau dikeluarkan sesuai kebutuhan analisis. Pengecualian: deduplikasi `reviews` dan `geolocation`, yang memang harus diringkas agar JOIN tidak menggandakan baris.
3. **Tidak ada imputasi diam-diam.** Nilai kosong tidak diisi tebakan. Satu-satunya pengisian adalah label `unknown` untuk kategori produk kosong.
4. **Setiap keputusan tercatat di sini**, lengkap dengan alasan dan dampaknya.

## Cara mereproduksi

```
python load_data.py                              # muat CSV mentah
python src/run_sql.py sql/03_deteksi_masalah.sql # deteksi (hanya membaca)
python src/build_clean.py                        # bangun tabel clean_*
```

## Ringkasan keputusan

| ID | Masalah | Temuan | Keputusan | Objek hasil |
|---|---|---|---|---|
| Q1 | Status order tidak relevan | 96.478 delivered (97,02%); 2.963 order status lain | Ruang lingkup utama = `delivered`; status lain dianalisis terpisah | `clean_orders.is_delivered`, `is_analysis_scope` |
| Q2 | NULL tanggal pada orders | 8 delivered tanpa tanggal tiba, 14 tanpa approved, 2 tanpa kurir | Tidak diisi; 8 order dikeluarkan dari metrik pengiriman | `flag_delivered_tanpa_tgl_tiba` |
| Q3 | Tanggal tidak logis | 166 kurir < beli, 23 tiba < kurir; 74 review dibuat < beli | Beri flag, keluarkan dari metrik pengiriman, jangan "memperbaiki" tanggal | `flag_tanggal_tidak_logis`, `flag_review_sebelum_beli` |
| Q4 | Review ganda per order | 547 order punya >1 review (551 baris berlebih); 789 `review_id` dipakai di >1 order | Simpan 1 review terbaru per order | `clean_order_reviews` |
| Q5 | Geolocation duplikat | 1.000.163 baris untuk 19.015 kode pos; 261.831 baris duplikat persis; 42 koordinat di luar Brasil | Ringkas 1 baris per kode pos (median), buang koordinat luar Brasil | `clean_geolocation` |
| Q6 | Kategori tanpa terjemahan | 13 produk di 2 kategori; 610 produk kategori kosong | Tambah 2 terjemahan manual; kosong menjadi `unknown` | `clean_category_translation`, `clean_products` |
| Q7 | NULL pada products selain kategori | Berat NULL 2, berat 0 sebanyak 4 | Beri flag, tidak diisi | `flag_berat_tidak_valid` |
| Q8 | Pembayaran janggal | 3 `not_defined` (nilai 0), 6 voucher bernilai 0, 2 kartu kredit cicilan 0 | Pertahankan, beri flag | `clean_payments` |
| Q9 | NULL pada teks review | Judul NULL 88,3%, pesan NULL 58,7% | Wajar (kolom opsional); tambah `has_comment` | `clean_order_reviews.has_comment` |

---

## Q1. Status order tidak relevan

**(a) Deteksi** - `sql/03_deteksi_masalah.sql` blok M1 dan M3:
```sql
SELECT order_status, COUNT(*) AS jumlah_order,
       COUNT(*) FILTER (WHERE order_id IN (SELECT order_id FROM reviews)) AS punya_review
FROM orders GROUP BY 1 ORDER BY 2 DESC;
```
Hasil: delivered 96.478, shipped 1.107, canceled 625, unavailable 609, invoiced 314, processing 301, created 5, approved 2. Order non-delivered tetap punya review (misalnya canceled 605, unavailable 595).

**(b) Keputusan:** semua order dipertahankan di `clean_orders`. Kolom `is_analysis_scope` bernilai TRUE hanya untuk order `delivered` dengan tanggal tiba terisi dan urutan tanggal logis (96.282 order). Order non-delivered dianalisis sebagai topik terpisah ("pengalaman gagal").
*Alasan:* review pada order yang dibatalkan atau tidak tersedia menilai kegagalan pemenuhan order, bukan kualitas produk atau pengiriman. Mencampurnya membuat metrik pengiriman dan kepuasan sulit ditafsirkan.

**(c) Dampak:** rata-rata skor review pada order dalam ruang lingkup 4,156, sedangkan semua review 4,086. Selisih 0,07 poin itu adalah bias jika status tidak disaring. Hanya 3% order yang dikeluarkan, tetapi skor mereka jelas lebih rendah, sehingga menyaring atau tidak akan mengubah kesimpulan.

## Q2. NULL pada tanggal di orders

**(a) Deteksi** - blok M1 dan M2:
```sql
SELECT 'delivered tapi tanggal tiba NULL', COUNT(*)
FROM orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;
```
NULL pada `order_approved_at` (160), `order_delivered_carrier_date` (1.783) dan `order_delivered_customer_date` (2.965) sebagian besar WAJAR karena order belum sampai tahap itu (canceled, unavailable, dan sebagainya). Yang tidak wajar hanya pada order `delivered`: 8 tanpa tanggal tiba, 14 tanpa `approved_at`, 2 tanpa tanggal kurir. Ada juga 6 order non-delivered (canceled) yang tanggal tibanya terisi.

**(b) Keputusan:** tidak ada imputasi. Order `delivered` tanpa tanggal tiba diberi `flag_delivered_tanpa_tgl_tiba` dan keluar dari `is_analysis_scope`. NULL `approved_at` dan tanggal kurir tidak dipakai di metrik utama, jadi dibiarkan.
*Alasan:* tanggal tiba tidak bisa ditebak dengan jujur, dan mengisi dengan tanggal estimasi akan membuat pengiriman tampak selalu tepat waktu.

**(c) Dampak:** hanya 8 order (0,008%) hilang dari metrik lama pengiriman dan keterlambatan, tidak material.

## Q3. Tanggal tidak logis

**(a) Deteksi** - blok M7 dan M7b. Urutan seharusnya: beli, approved, kurir, tiba.
```sql
SELECT 'tiba < serah ke kurir', COUNT(*) FROM orders
WHERE order_delivered_customer_date < order_delivered_carrier_date;
```
Temuan: serah ke kurir < beli = 166; tiba < serah ke kurir = 23; review dibuat < beli = 74. Pelanggaran lain (approved < beli, tiba < beli, estimasi < beli, review dijawab < dibuat, batas kirim item < beli) berjumlah 0. Dua temuan informasional tidak diperlakukan sebagai error: kurir < approved (1.359) dan review dibuat sebelum barang tiba (8.320; survei kepuasan bisa dikirim sebelum barang sampai).
Sebaran lama pengiriman pada tanggal valid: median 10,2 hari, p99 46,1 hari, maksimum 209,6 hari, 306 order lebih dari 60 hari.

**(b) Keputusan:** empat aturan inti dijadikan `flag_tanggal_tidak_logis` (189 order, 188 di antaranya `delivered`) dan dikeluarkan dari `is_analysis_scope`. Tanggal tidak ditukar atau diperbaiki. Pengiriman yang sangat lama (maks 209 hari) **dipertahankan**, tidak di-winsorize.
*Alasan:* kita tidak tahu tanggal mana yang salah, jadi memperbaikinya berarti menebak. Pengiriman lambat adalah fenomena nyata yang justru relevan dengan kepuasan.

**(c) Dampak:** 188 order delivered keluar dari metrik pengiriman. Di ruang lingkup: rata-rata pengiriman 12,57 hari, 8,13% terlambat dari estimasi. Karena ada ekor panjang, laporkan **median** di samping rata-rata. Metrik non-pengiriman tetap bisa memakai 188 order itu lewat `is_delivered`.

## Q4. Review ganda

**(a) Deteksi** - blok M4 dan M4b:
```sql
SELECT order_id FROM reviews GROUP BY 1 HAVING COUNT(*) > 1;           -- 547 order
SELECT review_id FROM reviews GROUP BY 1 HAVING COUNT(DISTINCT order_id) > 1;  -- 789 review_id
```
Tidak ada baris duplikat persis. Dari 547 order ber-review ganda, 202 punya skor berbeda dan 345 skor sama. `review_id` tidak unik (98.410 nilai untuk 99.224 baris), kunci yang benar adalah `(review_id, order_id)`.

**(b) Keputusan:** `clean_order_reviews` berisi tepat 1 review per order (98.673 baris), dipilih yang `review_answer_timestamp` paling baru (lalu `review_creation_date`, lalu `review_id` sebagai pemutus seri). Kolom `jumlah_review_asli` dan `flag_skor_berbeda_antar_review` disimpan agar bisa diaudit.
*Alasan:* review terbaru mencerminkan opini akhir pelanggan, dan satu order satu suara mencegah order tertentu dihitung berkali-kali. Alternatif (rata-rata skor atau review pertama) layak dicoba sebagai uji sensitivitas, dan dampaknya kecil karena hanya 202 order (0,2%) yang skornya berbeda.

**(c) Dampak:** 551 baris berlebih hilang. JOIN `orders` ke `clean_order_reviews` aman (tidak ada fan-out). Jangan pakai `review_id` sebagai kunci JOIN.

## Q5. Geolocation duplikat dan koordinat tidak valid

**(a) Deteksi** - blok M5 dan M5b:
```sql
SELECT COUNT(*), COUNT(DISTINCT geolocation_zip_code_prefix),
       COUNT(*) FILTER (WHERE geolocation_lat NOT BETWEEN -34 AND 6 OR geolocation_lng NOT BETWEEN -74 AND -34)
FROM geolocation;
```
Hasil: 1.000.163 baris, 19.015 kode pos unik, 261.831 baris duplikat persis, 42 titik di luar Brasil.

**(b) Keputusan:** `clean_geolocation` memiliki 1 baris per kode pos dengan koordinat **median**, kota dan negara bagian modus. Titik di luar kotak batas Brasil dibuang dulu (lat -34 sampai 6, lng -74 sampai -34). Hasilnya 19.010 kode pos (5 kode pos hanya punya titik di luar Brasil).
*Alasan:* satu kode pos punya banyak titik, sehingga JOIN langsung menggandakan baris customer. Median lebih tahan terhadap titik pencilan daripada rata-rata.

**(c) Dampak:** 279 customer (278 sebelum cleaning) dan 7 seller tidak punya koordinat. Mereka tetap di tabel, hanya tidak muncul pada analisis peta. Koordinat adalah pusat kode pos (perkiraan), bukan alamat, jadi jarak yang dihitung bersifat kasar.

## Q6. Kategori tanpa terjemahan

**(a) Deteksi** - blok M8, M8b, M8c:
```sql
SELECT p.product_category_name, COUNT(*) FROM products p
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NULL OR t.product_category_name IS NULL GROUP BY 1;
```
Hasil: `pc_gamer` (3 produk) dan `portateis_cozinha_e_preparadores_de_alimentos` (10 produk) tidak ada di file terjemahan. Selain itu 610 produk berkategori NULL, dan pada ke-610 produk itu nama, deskripsi dan jumlah foto juga NULL bersamaan (pola data hilang, bukan kebetulan).

**(b) Keputusan:**
- Dua kategori ditambahkan ke `clean_category_translation`: `pc_gamer` menjadi `pc_gamer`, dan `portateis_cozinha_e_preparadores_de_alimentos` menjadi `portable_kitchen_and_food_preparers` (terjemahan manual saya, silakan sesuaikan).
- Kategori NULL menjadi `unknown` di `clean_products.product_category_en`, dengan `flag_kategori_kosong`. Kolom aslinya tidak diubah.
- Kolom bertypo `product_name_lenght` dan `product_description_lenght` diganti namanya menjadi `..._length` di tabel bersih saja.
*Alasan:* menghapus 610 produk berarti menghilangkan penjualan nyata. Kategori tidak bisa ditebak dari kolom lain.

**(c) Dampak:** produk `unknown` mencakup 1.603 baris item (1,42% dari 112.650) di 1.451 order. Dua kategori tanpa terjemahan mencakup 24 baris item di 22 order. Dalam laporan per kategori, tampilkan `unknown` sebagai kategori tersendiri dan sebutkan porsinya.

## Q7. NULL dan nilai nol pada atribut produk

**(a) Deteksi** - blok M8c: `product_weight_g` NULL = 2, bernilai 0 = 4.

**(b) Keputusan:** diberi `flag_berat_tidak_valid` (6 produk). Tidak diisi dengan median kategori.
*Alasan:* berat 0 gram tidak mungkin, tetapi pengisian tebakan bisa menyesatkan analisis ongkir.

**(c) Dampak:** minimal. Hanya analisis berat atau ongkir yang terpengaruh, cukup saring dengan flag.

## Q8. Pembayaran janggal

**(a) Deteksi** - blok M6: tipe `not_defined` = 3 baris (semuanya bernilai 0); voucher bernilai 0 = 6; kartu kredit dengan cicilan 0 = 2. Satu order `delivered` tidak punya baris payment.

**(b) Keputusan:** semua baris dipertahankan di `clean_payments` dengan `flag_tipe_tidak_terdefinisi` dan `flag_nilai_nol`.
*Alasan:* nilainya 0 sehingga tidak mengubah total pendapatan. Menghapusnya hanya membuat jumlah baris tidak cocok dengan sumber.

**(c) Dampak:** nyaris nol. Perlu diingat satu order bisa punya banyak baris payment (maks 29), jadi agregasi per `order_id` dulu sebelum JOIN.

## Q9. NULL pada teks review

**(a) Deteksi** - profil tabel: `review_comment_title` NULL 87.656 (88,3%), `review_comment_message` NULL 58.247 (58,7%).

**(b) Keputusan:** dibiarkan NULL, karena kolom komentar memang opsional. Ditambah `has_comment` pada `clean_order_reviews` (40.775 dari 98.673 review, 41,3%).
*Alasan:* NULL di sini berarti "tidak menulis komentar", bukan data hilang.

**(c) Dampak:** analisis teks hanya mencakup sekitar 41% review. Pelanggan yang menulis komentar kemungkinan tidak mewakili semua pelanggan (hipotesis, perlu diuji dengan membandingkan sebaran skor pada kelompok `has_comment`), jadi sebutkan batasan ini di laporan.

---

## Yang sengaja TIDAK dibersihkan

- `customer_unique_id` berulang di `customers`: bukan duplikat, itu pelanggan yang sama dengan `customer_id` berbeda (lihat `sql/02_cek_relasi.sql` blok E).
- `order_item_id` > 1 dalam satu order: bukan duplikat, itu jumlah unit atau item ke-n pada order.
- Pengiriman sangat lama (maks 209,6 hari): fenomena nyata, bukan error.
- Penulisan nama kota (huruf, aksen, salah ketik): di luar kebutuhan analisis kepuasan, pakai kode pos dan negara bagian.

## Catatan untuk analisis berikutnya

- Untuk analisis kepuasan, titik awal: `clean_orders` (filter `is_analysis_scope`) JOIN `clean_order_reviews` (`order_id`) JOIN `customers` (`customer_id`), lalu hitung per `customer_unique_id`.
- Agregasi `order_items` dan `clean_payments` per `order_id` **sebelum** JOIN, supaya baris tidak berlipat ganda.
- Order dalam ruang lingkup yang punya review: 95.637 dari 96.282.
