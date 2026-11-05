-- =============================================================================
-- 05_analisis_bisnis.sql  |  Jawaban 6 pertanyaan bisnis + 2 analisis tambahan (DuckDB)
-- Jalankan: python src/run_sql.py sql/05_analisis_bisnis.sql
-- Grafik dan CSV: python src/run_analysis.py
--
-- DEFINISI (berlaku untuk semua query, dicatat juga di reports/laporan_temuan.md)
--   Order valid  : order_status BUKAN 'canceled' dan BUKAN 'unavailable'
--   Pendapatan   : SUM(order_items.price). Tidak termasuk ongkir (freight_value)
--   Ruang lingkup pengiriman : clean_orders.is_analysis_scope (delivered, tanggal logis)
--   Terlambat    : clean_orders.is_late (tanggal tiba > tanggal estimasi)
--   Negara bagian: customers.customer_state (lokasi PEMBELI)
--   Bulan tren   : 2017-01 sampai 2018-08 saja. Bulan lain sangat sedikit order
--                  (2016 hanya 3 bulan dan 2018-09 hanya 1 order), jadi MoM menyesatkan
--
-- ATURAN ANTI-FAN-OUT: order_items punya banyak baris per order. Setiap metrik level order
-- dihitung SEBELUM atau TANPA join ke order_items. Metrik level item di-GROUP BY order dulu
-- =============================================================================

-- ---------- Q1. Tren pendapatan dan jumlah order bulanan + pertumbuhan MoM ----------
WITH pendapatan_per_order AS (
    SELECT o.order_id,
           date_trunc('month', o.order_purchase_timestamp) AS bulan,
           SUM(i.price)                                    AS pendapatan
    FROM clean_orders o
    JOIN order_items i USING (order_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1, 2
),
bulanan AS (
    SELECT bulan,
           COUNT(*)                 AS jumlah_order,
           ROUND(SUM(pendapatan), 2) AS pendapatan
    FROM pendapatan_per_order
    WHERE bulan BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
    GROUP BY 1
)
SELECT strftime(bulan, '%Y-%m') AS bulan,
       jumlah_order,
       pendapatan,
       ROUND(pendapatan / jumlah_order, 2) AS rata2_nilai_order,
       ROUND(100.0 * (pendapatan   - LAG(pendapatan)   OVER w) / NULLIF(LAG(pendapatan)   OVER w, 0), 2) AS mom_pendapatan_pct,
       ROUND(100.0 * (jumlah_order - LAG(jumlah_order) OVER w) / NULLIF(LAG(jumlah_order) OVER w, 0), 2) AS mom_order_pct
FROM bulanan
WINDOW w AS (ORDER BY bulan)
ORDER BY bulan;

-- ---------- Q2. Top 10 kategori berdasarkan pendapatan ----------
WITH per_kategori AS (
    SELECT p.product_category_en        AS kategori,
           SUM(i.price)                 AS pendapatan,
           COUNT(DISTINCT i.order_id)   AS jumlah_order,
           COUNT(*)                     AS item_terjual
    FROM order_items i
    JOIN clean_orders   o USING (order_id)
    JOIN clean_products p USING (product_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
)
SELECT kategori,
       ROUND(pendapatan, 2)                                                      AS pendapatan,
       jumlah_order,
       item_terjual,
       ROUND(pendapatan / item_terjual, 2)                                       AS harga_rata2_per_item,
       ROUND(100.0 * pendapatan / SUM(pendapatan) OVER (), 2)                    AS pct_total,
       ROUND(100.0 * SUM(pendapatan) OVER (ORDER BY pendapatan DESC) / SUM(pendapatan) OVER (), 2) AS pct_kumulatif
FROM per_kategori
ORDER BY pendapatan DESC
LIMIT 10;

-- ---------- Q3a. Persentase order terlambat ----------
SELECT COUNT(*)                                                    AS order_dalam_scope,
       COUNT(*) FILTER (WHERE is_late)                             AS order_terlambat,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS pct_terlambat,
       ROUND(median(delay_days) FILTER (WHERE is_late), 1)          AS median_hari_terlambat,
       ROUND(avg(delay_days)    FILTER (WHERE is_late), 1)          AS rata2_hari_terlambat,
       ROUND(max(delay_days), 1)                                    AS maks_hari_terlambat,
       ROUND(median(delivery_days), 1)                              AS median_hari_pengiriman
FROM clean_orders
WHERE is_analysis_scope;

-- ---------- Q3b. Distribusi hari keterlambatan (hanya order terlambat) ----------
SELECT CASE WHEN delay_days <= 1  THEN '1. hingga 1 hari'
            WHEN delay_days <= 3  THEN '2. 1-3 hari'
            WHEN delay_days <= 7  THEN '3. 3-7 hari'
            WHEN delay_days <= 14 THEN '4. 7-14 hari'
            ELSE                       '5. lebih dari 14 hari' END AS bucket_keterlambatan,
       COUNT(*)                                                    AS jumlah_order,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_dari_order_terlambat
FROM clean_orders
WHERE is_analysis_scope AND is_late
GROUP BY 1
ORDER BY 1;

-- ---------- Q4. Rata-rata review_score: tepat waktu vs terlambat ----------
SELECT CASE WHEN o.is_late THEN 'Terlambat' ELSE 'Tepat waktu' END AS status_pengiriman,
       COUNT(*)                                                      AS order_ber_review,
       ROUND(AVG(r.review_score), 3)                                 AS rata2_skor,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 2) AS pct_skor_1_2,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score = 5)  / COUNT(*), 2) AS pct_skor_5
FROM clean_orders o
JOIN clean_order_reviews r USING (order_id)
WHERE o.is_analysis_scope
GROUP BY 1
ORDER BY 1 DESC;

-- ---------- Q4b. Tambahan: skor review menurut lamanya keterlambatan ----------
SELECT CASE WHEN NOT o.is_late      THEN '0. tepat waktu / lebih awal'
            WHEN o.delay_days <= 1  THEN '1. terlambat hingga 1 hari'
            WHEN o.delay_days <= 3  THEN '2. terlambat 1-3 hari'
            WHEN o.delay_days <= 7  THEN '3. terlambat 3-7 hari'
            WHEN o.delay_days <= 14 THEN '4. terlambat 7-14 hari'
            ELSE                         '5. terlambat lebih dari 14 hari' END AS kelompok,
       COUNT(*)                       AS order_ber_review,
       ROUND(AVG(r.review_score), 3)  AS rata2_skor,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 2) AS pct_skor_1_2
FROM clean_orders o
JOIN clean_order_reviews r USING (order_id)
WHERE o.is_analysis_scope
GROUP BY 1
ORDER BY 1;

-- ---------- Q5. Pendapatan dan tingkat keterlambatan per negara bagian ----------
-- Dua metrik berbeda granularitas, jadi dihitung di CTE terpisah lalu digabung (anti fan-out)
WITH pendapatan_order AS (
    SELECT o.order_id, o.customer_id, SUM(i.price) AS pendapatan
    FROM clean_orders o
    JOIN order_items i USING (order_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1, 2
),
pendapatan_negara AS (
    SELECT c.customer_state AS negara_bagian,
           SUM(po.pendapatan) AS pendapatan,
           COUNT(*)           AS jumlah_order
    FROM pendapatan_order po
    JOIN customers c USING (customer_id)
    GROUP BY 1
),
keterlambatan_negara AS (
    SELECT c.customer_state AS negara_bagian,
           COUNT(*)                          AS order_dalam_scope,
           AVG(o.is_late::INT)               AS rasio_terlambat,
           median(o.delivery_days)           AS median_hari_pengiriman
    FROM clean_orders o
    JOIN customers c USING (customer_id)
    WHERE o.is_analysis_scope
    GROUP BY 1
)
SELECT p.negara_bagian,
       ROUND(p.pendapatan, 2)                                  AS pendapatan,
       ROUND(100.0 * p.pendapatan / SUM(p.pendapatan) OVER (), 2) AS pct_pendapatan,
       p.jumlah_order,
       ROUND(p.pendapatan / p.jumlah_order, 2)                 AS rata2_nilai_order,
       k.order_dalam_scope,
       ROUND(100.0 * k.rasio_terlambat, 2)                     AS pct_terlambat,
       ROUND(k.median_hari_pengiriman, 1)                      AS median_hari_pengiriman
FROM pendapatan_negara p
LEFT JOIN keterlambatan_negara k USING (negara_bagian)
ORDER BY p.pendapatan DESC;

-- ---------- Q6. Persentase pelanggan dengan lebih dari 1 order (customer_unique_id) ----------
-- Tiga definisi order supaya terlihat sensitivitasnya. Yang utama: order valid
WITH order_pelanggan AS (
    SELECT c.customer_unique_id, o.order_id, o.order_status
    FROM clean_orders o
    JOIN customers c USING (customer_id)
),
skenario AS (
    SELECT 'A. semua order'                       AS definisi_order, customer_unique_id, COUNT(*) AS n
    FROM order_pelanggan GROUP BY 2
    UNION ALL
    SELECT 'B. order valid (utama)', customer_unique_id, COUNT(*)
    FROM order_pelanggan WHERE order_status NOT IN ('canceled', 'unavailable') GROUP BY 2
    UNION ALL
    SELECT 'C. hanya delivered', customer_unique_id, COUNT(*)
    FROM order_pelanggan WHERE order_status = 'delivered' GROUP BY 2
)
SELECT definisi_order,
       COUNT(*)                                                  AS total_pelanggan,
       COUNT(*) FILTER (WHERE n > 1)                             AS pelanggan_repeat,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n > 1) / COUNT(*), 2) AS pct_repeat,
       MAX(n)                                                    AS maks_order_per_pelanggan
FROM skenario
GROUP BY 1
ORDER BY 1;

-- ---------- Q6b. Tambahan: apakah skor review order PERTAMA memengaruhi pembelian ulang? ----------
WITH urutan AS (
    SELECT c.customer_unique_id, o.order_id,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp, o.order_id) AS urutan_order,
           COUNT(*)     OVER (PARTITION BY c.customer_unique_id)                                                 AS total_order
    FROM clean_orders o
    JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
)
SELECT r.review_score                                   AS skor_order_pertama,
       COUNT(*)                                         AS pelanggan,
       ROUND(100.0 * AVG((u.total_order > 1)::INT), 2)  AS pct_repeat
FROM urutan u
JOIN clean_order_reviews r USING (order_id)
WHERE u.urutan_order = 1
GROUP BY 1
ORDER BY 1;
