-- =====================================================================
-- Consumer Behavior Data Warehouse (3NF) - PostgreSQL
-- Source : POS export Jul 2024 - Jun 2025 (coffee & bakery chain, Vietnam)
-- Run    : psql -U postgres -f Consumer_Behavior_SQL.sql   (from the repository root)
-- =====================================================================

-- 1) DATABASE
DROP DATABASE IF EXISTS consumer_behavior_dw;
CREATE DATABASE consumer_behavior_dw;
\c consumer_behavior_dw

-- 2) DIMENSION TABLES
CREATE TABLE dim_gender (
  gender_id            SMALLINT PRIMARY KEY,
  gender               VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE dim_time (
  time_id              INTEGER PRIMARY KEY,
  time_of_purchase     TIMESTAMP NOT NULL UNIQUE,
  date                 DATE NOT NULL,
  year                 SMALLINT NOT NULL,
  quarter              SMALLINT NOT NULL CHECK (quarter BETWEEN 1 AND 4),
  month                SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
  month_name           CHAR(3) NOT NULL,
  day                  SMALLINT NOT NULL CHECK (day BETWEEN 1 AND 31),
  day_name             VARCHAR(10) NOT NULL,
  hour                 SMALLINT NOT NULL CHECK (hour BETWEEN 0 AND 23),
  is_weekend           BOOLEAN NOT NULL
);

CREATE TABLE dim_payment_method (
  payment_method_id    SMALLINT PRIMARY KEY,
  payment_method       VARCHAR(30) NOT NULL UNIQUE,
  payment_type         VARCHAR(20) NOT NULL
);

CREATE TABLE dim_product_category (
  product_category_id  SMALLINT PRIMARY KEY,
  product_category     VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE dim_location (
  location_id          SMALLINT PRIMARY KEY,
  city                 VARCHAR(40) NOT NULL UNIQUE,
  region               VARCHAR(10) NOT NULL CHECK (region IN ('North', 'Central', 'South'))
);

-- 3) FACT TABLE
CREATE TABLE main_fact (
  main_id              INTEGER PRIMARY KEY,
  transaction_id       VARCHAR(20) NOT NULL UNIQUE,
  age                  SMALLINT NOT NULL CHECK (age BETWEEN 15 AND 80),
  quantity             SMALLINT NOT NULL CHECK (quantity > 0),
  discount_pct         NUMERIC(4,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 1),
  purchase_amount      NUMERIC(12,0) NOT NULL CHECK (purchase_amount > 0),   -- VND
  customer_rating      SMALLINT CHECK (customer_rating BETWEEN 1 AND 5),     -- NULL = not rated
  gender_id            SMALLINT NOT NULL REFERENCES dim_gender(gender_id),
  time_id              INTEGER  NOT NULL REFERENCES dim_time(time_id),
  payment_method_id    SMALLINT NOT NULL REFERENCES dim_payment_method(payment_method_id),
  product_category_id  SMALLINT NOT NULL REFERENCES dim_product_category(product_category_id),
  location_id          SMALLINT NOT NULL REFERENCES dim_location(location_id)
);

CREATE INDEX idx_fact_time     ON main_fact(time_id);
CREATE INDEX idx_fact_gender   ON main_fact(gender_id);
CREATE INDEX idx_fact_payment  ON main_fact(payment_method_id);
CREATE INDEX idx_fact_product  ON main_fact(product_category_id);
CREATE INDEX idx_fact_location ON main_fact(location_id);

-- 4) LOAD DATA (client-side \copy; dimensions first, fact last)
--    Server-side alternative: COPY dim_gender FROM '/absolute/path/dim_gender.csv' CSV HEADER;
\copy dim_gender           FROM 'consumer_behavior/tables/dim_gender.csv'           CSV HEADER
\copy dim_time             FROM 'consumer_behavior/tables/dim_time.csv'             CSV HEADER
\copy dim_payment_method   FROM 'consumer_behavior/tables/dim_payment_method.csv'   CSV HEADER
\copy dim_product_category FROM 'consumer_behavior/tables/dim_product_category.csv' CSV HEADER
\copy dim_location         FROM 'consumer_behavior/tables/dim_location.csv'         CSV HEADER
\copy main_fact            FROM 'consumer_behavior/tables/main_fact.csv'            CSV HEADER

-- 5) ANALYTICS VIEW (derived columns are computed, not stored -> keeps the tables in 3NF)
CREATE VIEW v_main_fact_enriched AS
SELECT f.*,
       CASE WHEN f.purchase_amount < 60000  THEN 'low'
            WHEN f.purchase_amount < 150000 THEN 'mid'
            ELSE 'high' END                         AS categorical_purchase_amount,
       g.gender, t.time_of_purchase, t.date, t.year, t.month, t.hour, t.day_name, t.is_weekend,
       p.payment_method, p.payment_type, c.product_category, l.city, l.region
FROM main_fact f
JOIN dim_gender g           ON f.gender_id = g.gender_id
JOIN dim_time t             ON f.time_id = t.time_id
JOIN dim_payment_method p   ON f.payment_method_id = p.payment_method_id
JOIN dim_product_category c ON f.product_category_id = c.product_category_id
JOIN dim_location l         ON f.location_id = l.location_id;

-- 6) TEST QUERIES
-- Row counts
SELECT 'main_fact' AS table_name, COUNT(*) FROM main_fact
UNION ALL SELECT 'dim_time', COUNT(*) FROM dim_time
UNION ALL SELECT 'dim_gender', COUNT(*) FROM dim_gender
UNION ALL SELECT 'dim_payment_method', COUNT(*) FROM dim_payment_method
UNION ALL SELECT 'dim_product_category', COUNT(*) FROM dim_product_category
UNION ALL SELECT 'dim_location', COUNT(*) FROM dim_location;

-- a) Total Purchase Amount by Gender, Age <= 30
SELECT g.gender,
       SUM(f.purchase_amount) AS total_purchase_amount,
       COUNT(*)               AS transactions
FROM main_fact f
JOIN dim_gender g ON f.gender_id = g.gender_id
WHERE f.age <= 30
GROUP BY g.gender
ORDER BY total_purchase_amount DESC;

-- b) Avg / Min / Max Purchase Amount by Product Category
SELECT p.product_category,
       ROUND(AVG(f.purchase_amount), 2) AS avg_amount,
       MIN(f.purchase_amount)           AS min_amount,
       MAX(f.purchase_amount)           AS max_amount,
       COUNT(*)                         AS transactions
FROM main_fact f
JOIN dim_product_category p ON f.product_category_id = p.product_category_id
GROUP BY p.product_category
ORDER BY avg_amount DESC;
