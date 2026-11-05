-- =============================================================================
-- 04_buat_tabel_bersih.sql  |  Membuat tabel bersih (prefix clean_)
-- PRINSIP: tabel mentah (orders, reviews, dst.) TIDAK diubah atau dihapus.
-- Baris bermasalah diberi FLAG, bukan dibuang, kecuali untuk deduplikasi yang
-- memang wajib (reviews dan geolocation). Alasan tiap keputusan: docs/data_cleaning_log.md
-- Jalankan: python src/build_clean.py   (aman diulang, tabel lama ditimpa)
-- =============================================================================

-- ---------- clean_category_translation: tambah 2 kategori yang hilang dari file terjemahan ----------
CREATE OR REPLACE TABLE clean_category_translation AS
SELECT product_category_name, product_category_name_english
FROM category_translation
UNION ALL
SELECT v.product_category_name, v.product_category_name_english
FROM (VALUES
        ('pc_gamer', 'pc_gamer'),
        ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers')
     ) AS v(product_category_name, product_category_name_english)
WHERE v.product_category_name NOT IN (SELECT product_category_name FROM category_translation);

-- ---------- clean_products: nama kategori Inggris (NULL jadi 'unknown'), perbaiki typo nama kolom ----------
CREATE OR REPLACE TABLE clean_products AS
SELECT p.product_id,
       p.product_category_name,
       COALESCE(t.product_category_name_english, 'unknown')        AS product_category_en,
       (p.product_category_name IS NULL)                           AS flag_kategori_kosong,
       p.product_name_lenght                                       AS product_name_length,
       p.product_description_lenght                                AS product_description_length,
       p.product_photos_qty,
       p.product_weight_g,
       p.product_length_cm,
       p.product_height_cm,
       p.product_width_cm,
       (p.product_weight_g IS NULL OR p.product_weight_g = 0)      AS flag_berat_tidak_valid
FROM products p
LEFT JOIN clean_category_translation t ON p.product_category_name = t.product_category_name;

-- ---------- clean_orders: SEMUA order dipertahankan, ditambah flag dan metrik pengiriman ----------
-- is_analysis_scope = TRUE hanya untuk order delivered, tanggal tiba terisi, dan urutan tanggal logis.
CREATE OR REPLACE TABLE clean_orders AS
WITH f AS (
    SELECT o.*,
           (order_status = 'delivered') AS is_delivered,
           COALESCE(order_status = 'delivered' AND order_delivered_customer_date IS NULL, FALSE) AS flag_delivered_tanpa_tgl_tiba,
           COALESCE(order_approved_at < order_purchase_timestamp, FALSE)                         AS flag_approved_sebelum_beli,
           COALESCE(order_delivered_carrier_date < order_purchase_timestamp, FALSE)              AS flag_kurir_sebelum_beli,
           COALESCE(order_delivered_customer_date < order_purchase_timestamp, FALSE)             AS flag_tiba_sebelum_beli,
           COALESCE(order_delivered_customer_date < order_delivered_carrier_date, FALSE)         AS flag_tiba_sebelum_kurir,
           COALESCE(order_delivered_carrier_date < order_approved_at, FALSE)                     AS flag_kurir_sebelum_approved
    FROM orders o
),
g AS (
    SELECT *,
           (flag_approved_sebelum_beli OR flag_kurir_sebelum_beli
            OR flag_tiba_sebelum_beli OR flag_tiba_sebelum_kurir) AS flag_tanggal_tidak_logis
    FROM f
),
h AS (
    SELECT *,
           (is_delivered AND order_delivered_customer_date IS NOT NULL AND NOT flag_tanggal_tidak_logis) AS is_analysis_scope
    FROM g
)
SELECT h.*,
       CASE WHEN is_analysis_scope
            THEN ROUND(EXTRACT(epoch FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0, 2) END AS delivery_days,
       CASE WHEN is_analysis_scope
            THEN ROUND(EXTRACT(epoch FROM (order_delivered_customer_date - order_estimated_delivery_date)) / 86400.0, 2) END AS delay_days,
       CASE WHEN is_analysis_scope
            THEN order_delivered_customer_date > order_estimated_delivery_date END AS is_late
FROM h;

-- ---------- clean_order_reviews: tepat 1 review per order (yang terbaru) ----------
CREATE OR REPLACE TABLE clean_order_reviews AS
SELECT order_id,
       review_id,
       review_score,
       review_comment_title,
       review_comment_message,
       review_creation_date,
       review_answer_timestamp,
       (review_comment_message IS NOT NULL)  AS has_comment,
       n_review_asli                         AS jumlah_review_asli,
       (skor_maks <> skor_min)               AS flag_skor_berbeda_antar_review,
       flag_review_sebelum_beli
FROM (
    SELECT r.*,
           COUNT(*)            OVER (PARTITION BY r.order_id) AS n_review_asli,
           MAX(r.review_score) OVER (PARTITION BY r.order_id) AS skor_maks,
           MIN(r.review_score) OVER (PARTITION BY r.order_id) AS skor_min,
           COALESCE(r.review_creation_date < o.order_purchase_timestamp, FALSE) AS flag_review_sebelum_beli,
           ROW_NUMBER() OVER (PARTITION BY r.order_id
                              ORDER BY r.review_answer_timestamp DESC, r.review_creation_date DESC, r.review_id DESC) AS rn
    FROM reviews r
    JOIN orders o USING (order_id)
)
WHERE rn = 1;

-- ---------- clean_payments: semua baris dipertahankan, ditambah flag ----------
CREATE OR REPLACE TABLE clean_payments AS
SELECT *,
       (payment_type = 'not_defined') AS flag_tipe_tidak_terdefinisi,
       (payment_value = 0)            AS flag_nilai_nol
FROM payments;

-- ---------- clean_geolocation: 1 baris per kode pos (median koordinat), buang koordinat di luar Brasil ----------
CREATE OR REPLACE TABLE clean_geolocation AS
SELECT geolocation_zip_code_prefix  AS zip_code_prefix,
       median(geolocation_lat)      AS lat,
       median(geolocation_lng)      AS lng,
       mode(geolocation_city)       AS city,
       mode(geolocation_state)      AS state,
       COUNT(*)                     AS jumlah_titik_asli
FROM geolocation
WHERE geolocation_lat BETWEEN -34 AND 6
  AND geolocation_lng BETWEEN -74 AND -34
GROUP BY 1;
