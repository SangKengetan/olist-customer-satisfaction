-- =============================================================================
-- 03_deteksi_masalah.sql  |  Deteksi masalah kualitas data (HANYA MEMBACA, tidak mengubah apa pun)
-- Jalankan: python src/run_sql.py sql/03_deteksi_masalah.sql
-- Keputusan cleaning untuk tiap temuan ada di docs/data_cleaning_log.md
-- =============================================================================

-- ---------- M1. NULL pada orders, dirinci per status order ----------
-- NULL pada tanggal di status selain delivered itu WAJAR (barang memang belum sampai tahap itu).
SELECT order_status,
       COUNT(*)                                                         AS jumlah_order,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS persen_order,
       COUNT(*) FILTER (WHERE order_approved_at IS NULL)                AS null_approved,
       COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)     AS null_carrier,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)    AS null_tgl_tiba
FROM orders
GROUP BY 1
ORDER BY 2 DESC;

-- ---------- M2. NULL yang TIDAK wajar (bertentangan dengan status order) ----------
SELECT 'delivered tapi tanggal tiba NULL' AS masalah, COUNT(*) AS jumlah
FROM orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
UNION ALL
SELECT 'delivered tapi tanggal serah ke kurir NULL', COUNT(*)
FROM orders WHERE order_status = 'delivered' AND order_delivered_carrier_date IS NULL
UNION ALL
SELECT 'delivered tapi approved_at NULL', COUNT(*)
FROM orders WHERE order_status = 'delivered' AND order_approved_at IS NULL
UNION ALL
SELECT 'bukan delivered tapi tanggal tiba terisi', COUNT(*)
FROM orders WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- ---------- M3. Status order vs ketersediaan review dan item (dasar penentuan ruang lingkup) ----------
SELECT order_status,
       COUNT(*)                                                                AS jumlah_order,
       COUNT(*) FILTER (WHERE order_id IN (SELECT order_id FROM reviews))      AS punya_review,
       COUNT(*) FILTER (WHERE order_id IN (SELECT order_id FROM order_items))  AS punya_item,
       COUNT(*) FILTER (WHERE order_id IN (SELECT order_id FROM payments))     AS punya_payment
FROM orders
GROUP BY 1
ORDER BY 2 DESC;

-- ---------- M4. Duplikasi pada reviews ----------
SELECT 'review_id muncul di lebih dari 1 order' AS masalah, COUNT(*) AS jumlah
FROM (SELECT review_id FROM reviews GROUP BY 1 HAVING COUNT(DISTINCT order_id) > 1)
UNION ALL
SELECT 'order yang punya lebih dari 1 review', COUNT(*)
FROM (SELECT order_id FROM reviews GROUP BY 1 HAVING COUNT(*) > 1)
UNION ALL
SELECT 'baris review berlebih (baris - order unik)', COUNT(*) - COUNT(DISTINCT order_id)
FROM reviews
UNION ALL
SELECT 'baris duplikat persis (semua kolom sama)',
       (SELECT COUNT(*) FROM reviews) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM reviews));

-- ---------- M4b. Pada order dengan banyak review, apakah skornya berbeda? ----------
SELECT COUNT(*)                                  AS order_multi_review,
       COUNT(*) FILTER (WHERE n_skor > 1)        AS skor_berbeda,
       COUNT(*) FILTER (WHERE n_skor = 1)        AS skor_sama
FROM (SELECT order_id, COUNT(DISTINCT review_score) AS n_skor
      FROM reviews GROUP BY 1 HAVING COUNT(*) > 1);

-- ---------- M5. Duplikasi dan koordinat tidak valid pada geolocation ----------
SELECT COUNT(*)                                                              AS baris,
       COUNT(DISTINCT geolocation_zip_code_prefix)                           AS kode_pos_unik,
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM geolocation)) AS baris_duplikat_persis,
       COUNT(*) FILTER (WHERE geolocation_lat NOT BETWEEN -34 AND 6
                           OR geolocation_lng NOT BETWEEN -74 AND -34)       AS koordinat_di_luar_brasil
FROM geolocation;

-- ---------- M5b. Kode pos customer dan seller yang tidak ada di geolocation ----------
SELECT 'customers' AS tabel, COUNT(*) AS baris,
       COUNT(*) FILTER (WHERE customer_zip_code_prefix NOT IN (SELECT geolocation_zip_code_prefix FROM geolocation)) AS tanpa_geolokasi
FROM customers
UNION ALL
SELECT 'sellers', COUNT(*),
       COUNT(*) FILTER (WHERE seller_zip_code_prefix NOT IN (SELECT geolocation_zip_code_prefix FROM geolocation))
FROM sellers;

-- ---------- M6. Pembayaran janggal ----------
SELECT payment_type,
       COUNT(*)                                          AS jumlah,
       COUNT(*) FILTER (WHERE payment_value = 0)         AS nilai_nol,
       COUNT(*) FILTER (WHERE payment_installments = 0)  AS cicilan_nol
FROM payments
GROUP BY 1
ORDER BY 2 DESC;

-- ---------- M7. Tanggal tidak logis (urutan seharusnya: beli, approved, kurir, tiba) ----------
SELECT 'approved < beli' AS aturan_dilanggar, COUNT(*) AS jumlah
FROM orders WHERE order_approved_at < order_purchase_timestamp
UNION ALL
SELECT 'serah ke kurir < beli', COUNT(*)
FROM orders WHERE order_delivered_carrier_date < order_purchase_timestamp
UNION ALL
SELECT 'serah ke kurir < approved (informasional)', COUNT(*)
FROM orders WHERE order_delivered_carrier_date < order_approved_at
UNION ALL
SELECT 'tiba < beli', COUNT(*)
FROM orders WHERE order_delivered_customer_date < order_purchase_timestamp
UNION ALL
SELECT 'tiba < serah ke kurir', COUNT(*)
FROM orders WHERE order_delivered_customer_date < order_delivered_carrier_date
UNION ALL
SELECT 'estimasi tiba < beli', COUNT(*)
FROM orders WHERE order_estimated_delivery_date < order_purchase_timestamp
UNION ALL
SELECT 'batas kirim item < beli', COUNT(*)
FROM order_items i JOIN orders o USING (order_id) WHERE i.shipping_limit_date < o.order_purchase_timestamp
UNION ALL
SELECT 'review dibuat < beli', COUNT(*)
FROM reviews r JOIN orders o USING (order_id) WHERE r.review_creation_date < o.order_purchase_timestamp
UNION ALL
SELECT 'review dijawab < review dibuat', COUNT(*)
FROM reviews WHERE review_answer_timestamp < review_creation_date
UNION ALL
SELECT 'review dibuat < barang tiba (informasional)', COUNT(*)
FROM reviews r JOIN orders o USING (order_id) WHERE r.review_creation_date < o.order_delivered_customer_date;

-- ---------- M7b. Sebaran lama pengiriman (hari) untuk order delivered dengan tanggal valid ----------
SELECT COUNT(*)                              AS n_order,
       ROUND(MIN(d), 1)                      AS min_hari,
       ROUND(quantile_cont(d, 0.5), 1)       AS median_hari,
       ROUND(quantile_cont(d, 0.99), 1)      AS p99_hari,
       ROUND(MAX(d), 1)                      AS maks_hari,
       COUNT(*) FILTER (WHERE d > 60)        AS lebih_dari_60_hari
FROM (
    SELECT EXTRACT(epoch FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0 AS d
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date >= order_purchase_timestamp
);

-- ---------- M8. Kategori produk tanpa terjemahan atau kosong ----------
SELECT COALESCE(p.product_category_name, '(NULL)') AS kategori_produk,
       CASE WHEN p.product_category_name IS NULL THEN 'kategori kosong' ELSE 'tanpa terjemahan' END AS jenis,
       COUNT(*) AS jumlah_produk
FROM products p
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NULL OR t.product_category_name IS NULL
GROUP BY 1, 2
ORDER BY 3 DESC;

-- ---------- M8b. Dampaknya pada baris order_items ----------
SELECT CASE WHEN p.product_category_name IS NULL THEN 'kategori kosong' ELSE 'tanpa terjemahan' END AS jenis,
       COUNT(*)                  AS baris_item,
       COUNT(DISTINCT i.order_id) AS order_terdampak
FROM order_items i
JOIN products p USING (product_id)
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NULL OR t.product_category_name IS NULL
GROUP BY 1;

-- ---------- M8c. Pola NULL pada products ----------
SELECT COUNT(*) FILTER (WHERE product_category_name IS NULL)                                   AS kategori_null,
       COUNT(*) FILTER (WHERE product_category_name IS NULL AND product_name_lenght IS NULL
                          AND product_description_lenght IS NULL AND product_photos_qty IS NULL) AS keempat_kolom_null_bersamaan,
       COUNT(*) FILTER (WHERE product_weight_g IS NULL)                                        AS berat_null,
       COUNT(*) FILTER (WHERE product_weight_g = 0)                                            AS berat_nol
FROM products;

-- ---------- M9. Pengecekan nilai numerik ----------
SELECT 'order_items: price <= 0' AS pemeriksaan, COUNT(*) AS jumlah FROM order_items WHERE price <= 0
UNION ALL
SELECT 'order_items: freight_value < 0', COUNT(*) FROM order_items WHERE freight_value < 0
UNION ALL
SELECT 'reviews: skor di luar 1-5', COUNT(*) FROM reviews WHERE review_score NOT BETWEEN 1 AND 5
UNION ALL
SELECT 'payments: payment_value < 0', COUNT(*) FROM payments WHERE payment_value < 0;
