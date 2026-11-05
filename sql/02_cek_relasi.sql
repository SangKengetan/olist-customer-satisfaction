-- =============================================================================
-- 02_cek_relasi.sql  |  Membuktikan Primary Key & Foreign Key dengan data asli
-- Jalankan: python src/run_sql.py sql/02_cek_relasi.sql
-- =============================================================================

-- ---------- A. Uji Primary Key: apakah kolom/kombinasi kolom benar-benar unik? ----------
-- unik = TRUE artinya jumlah baris == jumlah nilai berbeda  -> layak jadi PK
SELECT 'customers'            AS tabel, 'customer_id'                  AS kandidat_pk, COUNT(*) AS baris, COUNT(DISTINCT customer_id) AS nilai_unik, COUNT(*) = COUNT(DISTINCT customer_id) AS unik FROM customers
UNION ALL SELECT 'orders',               'order_id',                   COUNT(*), COUNT(DISTINCT order_id),    COUNT(*) = COUNT(DISTINCT order_id)    FROM orders
UNION ALL SELECT 'order_items',          'order_id + order_item_id',   COUNT(*), COUNT(DISTINCT (order_id, order_item_id)),      COUNT(*) = COUNT(DISTINCT (order_id, order_item_id))      FROM order_items
UNION ALL SELECT 'payments',             'order_id + payment_sequential', COUNT(*), COUNT(DISTINCT (order_id, payment_sequential)), COUNT(*) = COUNT(DISTINCT (order_id, payment_sequential)) FROM payments
UNION ALL SELECT 'reviews',              'review_id',                  COUNT(*), COUNT(DISTINCT review_id),   COUNT(*) = COUNT(DISTINCT review_id)   FROM reviews
UNION ALL SELECT 'reviews',              'review_id + order_id',       COUNT(*), COUNT(DISTINCT (review_id, order_id)),          COUNT(*) = COUNT(DISTINCT (review_id, order_id))          FROM reviews
UNION ALL SELECT 'reviews',              'order_id',                   COUNT(*), COUNT(DISTINCT order_id),    COUNT(*) = COUNT(DISTINCT order_id)    FROM reviews
UNION ALL SELECT 'products',             'product_id',                 COUNT(*), COUNT(DISTINCT product_id),  COUNT(*) = COUNT(DISTINCT product_id)  FROM products
UNION ALL SELECT 'sellers',              'seller_id',                  COUNT(*), COUNT(DISTINCT seller_id),   COUNT(*) = COUNT(DISTINCT seller_id)   FROM sellers
UNION ALL SELECT 'category_translation','product_category_name',      COUNT(*), COUNT(DISTINCT product_category_name), COUNT(*) = COUNT(DISTINCT product_category_name) FROM category_translation
UNION ALL SELECT 'geolocation',          'geolocation_zip_code_prefix',COUNT(*), COUNT(DISTINCT geolocation_zip_code_prefix), COUNT(*) = COUNT(DISTINCT geolocation_zip_code_prefix) FROM geolocation;

-- ---------- B. Uji Foreign Key: berapa baris "yatim" (orphan) yang tidak punya induk? ----------
-- baris_orphan = 0 artinya FK bersih. NULL pada kolom FK tidak dihitung.
SELECT 'orders.customer_id -> customers.customer_id' AS relasi,
       COUNT(*) AS baris_anak,
       COUNT(*) FILTER (WHERE p.customer_id IS NULL) AS baris_orphan
FROM orders c LEFT JOIN customers p USING (customer_id)
UNION ALL
SELECT 'order_items.order_id -> orders.order_id', COUNT(*), COUNT(*) FILTER (WHERE p.order_id IS NULL)
FROM order_items c LEFT JOIN orders p USING (order_id)
UNION ALL
SELECT 'order_items.product_id -> products.product_id', COUNT(*), COUNT(*) FILTER (WHERE p.product_id IS NULL)
FROM order_items c LEFT JOIN products p USING (product_id)
UNION ALL
SELECT 'order_items.seller_id -> sellers.seller_id', COUNT(*), COUNT(*) FILTER (WHERE p.seller_id IS NULL)
FROM order_items c LEFT JOIN sellers p USING (seller_id)
UNION ALL
SELECT 'payments.order_id -> orders.order_id', COUNT(*), COUNT(*) FILTER (WHERE p.order_id IS NULL)
FROM payments c LEFT JOIN orders p USING (order_id)
UNION ALL
SELECT 'reviews.order_id -> orders.order_id', COUNT(*), COUNT(*) FILTER (WHERE p.order_id IS NULL)
FROM reviews c LEFT JOIN orders p USING (order_id)
UNION ALL
SELECT 'products.product_category_name -> category_translation', COUNT(*) FILTER (WHERE c.product_category_name IS NOT NULL),
       COUNT(*) FILTER (WHERE c.product_category_name IS NOT NULL AND p.product_category_name IS NULL)
FROM products c LEFT JOIN category_translation p USING (product_category_name)
UNION ALL
SELECT 'customers.zip -> geolocation.zip (hubungan longgar)', COUNT(*),
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM geolocation g WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix))
FROM customers c
UNION ALL
SELECT 'sellers.zip -> geolocation.zip (hubungan longgar)', COUNT(*),
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM geolocation g WHERE g.geolocation_zip_code_prefix = c.seller_zip_code_prefix))
FROM sellers c;

-- ---------- C. Kardinalitas: berapa "anak" per "induk"? (hati-hati fan-out saat JOIN) ----------
SELECT 'item per order'    AS ukuran, MIN(n) AS min, ROUND(AVG(n),2) AS rata2, MAX(n) AS maks, COUNT(*) AS jumlah_induk
FROM (SELECT order_id, COUNT(*) AS n FROM order_items GROUP BY 1)
UNION ALL
SELECT 'payment per order', MIN(n), ROUND(AVG(n),2), MAX(n), COUNT(*)
FROM (SELECT order_id, COUNT(*) AS n FROM payments GROUP BY 1)
UNION ALL
SELECT 'review per order (yang punya review)', MIN(n), ROUND(AVG(n),2), MAX(n), COUNT(*)
FROM (SELECT order_id, COUNT(*) AS n FROM reviews GROUP BY 1);

-- ---------- D. Order tanpa review & tanpa item ----------
SELECT
  (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM reviews r WHERE r.order_id = o.order_id))      AS order_tanpa_review,
  (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id))  AS order_tanpa_item,
  (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.order_id))     AS order_tanpa_payment;

-- ---------- E. customer_id vs customer_unique_id ----------
SELECT
  COUNT(*)                                        AS baris_customers,
  COUNT(DISTINCT customer_id)                     AS customer_id_unik,
  COUNT(DISTINCT customer_unique_id)              AS customer_unique_id_unik,
  COUNT(*) - COUNT(DISTINCT customer_unique_id)   AS selisih
FROM customers;

-- Distribusi: berapa order yang dibuat tiap ORANG ASLI (customer_unique_id)?
SELECT jumlah_order, COUNT(*) AS jumlah_orang, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS persen
FROM (
    SELECT c.customer_unique_id, COUNT(o.order_id) AS jumlah_order
    FROM customers c JOIN orders o USING (customer_id)
    GROUP BY 1
)
GROUP BY 1
ORDER BY 1;

-- Berapa order yang dibuat tiap customer_id? (seharusnya selalu 1)
SELECT jumlah_order, COUNT(*) AS jumlah_customer_id
FROM (SELECT customer_id, COUNT(*) AS jumlah_order FROM orders GROUP BY 1)
GROUP BY 1
ORDER BY 1;
