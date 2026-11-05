-- ==============================================================================
-- 01_profil_tabel.sql  |  Profil tiap tabel: jumlah baris, jumlah kolom,
-- tipe data, dan jumlah NULL per kolom.  (DuckDB)
--
-- Satu blok query per tabel. Output: 1 baris per kolom, dengan kolom:
--   tabel | total_baris | total_kolom | no | kolom | tipe_data | jumlah_null | persen_null
--
-- Cara kerja:
--   COUNT(*) - COUNT(kolom)  = jumlah NULL (COUNT(kolom) tidak menghitung NULL)
--   COLUMNS(*)               = terapkan ekspresi ke SEMUA kolom sekaligus
--   UNPIVOT                  = ubah hasil 1 baris lebar jadi 1 baris per kolom
--   information_schema       = sumber nama kolom, urutan, dan tipe data
-- ==============================================================================

-- ---------- customers ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'customers'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM customers)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM customers)
SELECT
    'customers'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- geolocation ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'geolocation'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM geolocation)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM geolocation)
SELECT
    'geolocation'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- orders ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'orders'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM orders)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM orders)
SELECT
    'orders'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- order_items ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'order_items'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM order_items)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM order_items)
SELECT
    'order_items'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- payments ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'payments'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM payments)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM payments)
SELECT
    'payments'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- reviews ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'reviews'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM reviews)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM reviews)
SELECT
    'reviews'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- products ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'products'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM products)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM products)
SELECT
    'products'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- sellers ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'sellers'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM sellers)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM sellers)
SELECT
    'sellers'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;

-- ---------- category_translation ----------
WITH info AS (
    SELECT column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_schema = 'main' AND table_name = 'category_translation'
),
nulls AS (
    UNPIVOT (SELECT COUNT(*) - COUNT(COLUMNS(*)) AS "\0" FROM category_translation)
    ON COLUMNS(*) INTO NAME column_name VALUE null_count
),
tot AS (SELECT COUNT(*) AS total_rows FROM category_translation)
SELECT
    'category_translation'                                               AS tabel,
    tot.total_rows                                     AS total_baris,
    COUNT(*) OVER ()                                   AS total_kolom,
    info.ordinal_position                              AS no,
    info.column_name                                   AS kolom,
    info.data_type                                     AS tipe_data,
    nulls.null_count                                   AS jumlah_null,
    ROUND(100.0 * nulls.null_count / tot.total_rows, 2) AS persen_null
FROM info
JOIN nulls USING (column_name)
CROSS JOIN tot
ORDER BY info.ordinal_position;
