-- ========================================================================================================================
-- SUPPLEMENTS SALES - SQL ANALYSIS
-- Dataset: Supplement Sales Data (Kaggle), weekly sales 2020-2025, health & wellness supplements
-- Tool: SQL Server
-- Schema: star schema - fact_sales (fact) + dim_products, dim_platforms, dim_locations (dimensions)
-- ========================================================================================================================


-- ========================================================================================================================
-- QUERY 1: Revenue by category, % change 2020 vs 2024
-- Question: Which category grew or fell the most between 2020 and 2024?
-- Finding: Performance is the only category that fell (-11.86%).
-- All the other categories grew, from +1.03% (Mineral) to +13.52% (Omega).
-- This is the main finding of the project.

WITH category_revenue AS (
    SELECT
        pr.category,
        SUM(CASE WHEN YEAR([date]) = 2020 THEN revenue END) AS revenue_2020,
        SUM(CASE WHEN YEAR([date]) = 2024 THEN revenue END) AS revenue_2024
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    GROUP BY pr.category
)
SELECT
    category,
    revenue_2020,
    revenue_2024,
    CAST((revenue_2024 - revenue_2020) * 100 / revenue_2020 AS DECIMAL(5,2)) AS pct_change_2020_2024
FROM category_revenue
ORDER BY pct_change_2020_2024 ASC;


-- ========================================================================================================================
-- QUERY 2: Average price by category, year over year (2020-2024)
-- Question: Did the average price of any category go down over time?
-- Finding: Performance is one of the few categories with a clear price drop: from $38.15 in 2020 to $32.51 in 2024 (-14.8%).
-- The price goes up and down between years, but it ends clearly lower. This is a second signal that supports Query 1.

SELECT
    pr.category,
    CAST(AVG(CASE WHEN YEAR([date]) = 2020 THEN price END) AS DECIMAL(5,2)) AS avg_price_2020,
    CAST(AVG(CASE WHEN YEAR([date]) = 2021 THEN price END) AS DECIMAL(5,2)) AS avg_price_2021,
    CAST(AVG(CASE WHEN YEAR([date]) = 2022 THEN price END) AS DECIMAL(5,2)) AS avg_price_2022,
    CAST(AVG(CASE WHEN YEAR([date]) = 2023 THEN price END) AS DECIMAL(5,2)) AS avg_price_2023,
    CAST(AVG(CASE WHEN YEAR([date]) = 2024 THEN price END) AS DECIMAL(5,2)) AS avg_price_2024
FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
GROUP BY pr.category
ORDER BY pr.category;


-- ========================================================================================================================
-- QUERY 3: Top 2 products by category (units sold), with the gap between them
-- Question: In each category, how far apart are the #1 and #2 best-selling products?
-- Finding: Performance has the smallest gap of all categories with 2 or more products.
-- Pre-Workout and Creatine sell almost the same number of units (only 54 units apart).
-- So both products have a similar total volume. The country and product queries at the end show where the decline comes from.

WITH units_sold AS (
    SELECT
        pr.product,
        pr.category,
        SUM(units_sold) AS total_units_sold
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    WHERE YEAR([date]) <= 2024
    GROUP BY pr.product, pr.category
),
rank_units_sold AS (
    SELECT
        product, category, total_units_sold,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_units_sold DESC) AS rn
    FROM units_sold
)
SELECT
    r1.product AS product_1, r1.rn AS rank_1,
    r2.product AS product_2, r2.rn AS rank_2,
    (r1.total_units_sold - r2.total_units_sold) AS difference
FROM rank_units_sold r1
JOIN rank_units_sold r2 ON r1.category = r2.category
WHERE r1.rn = 1 AND r2.rn = 2
ORDER BY difference ASC;


-- ========================================================================================================================
-- QUERY 4: Leader by units sold vs. leader by revenue, per category (2020-2024)
-- Question: Is the product that sells the most units also the one that earns the most revenue?
-- Finding: Only in Mineral, no. Magnesium sells the most units, but Zinc earns the most revenue.
-- In Protein, Performance and Vitamin, the same product leads in both.
-- NULL in revenue_leader means that the revenue leader is a different product.
-- Categories with only one product always match.

WITH units_sold AS (
    SELECT pr.product, pr.category, SUM(units_sold) AS total_units_sold
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    WHERE YEAR([date]) <= 2024
    GROUP BY pr.product, pr.category
),
rank_by_units AS (
    SELECT product, category, total_units_sold,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_units_sold DESC) AS rn
    FROM units_sold
),
total_revenue AS (
    SELECT pr.product, pr.category, SUM(revenue) AS total_revenue
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    WHERE YEAR([date]) <= 2024
    GROUP BY pr.product, pr.category
),  
rank_by_revenue AS (
    SELECT product, category, total_revenue,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_revenue DESC) AS rn
    FROM total_revenue
)
SELECT
    ru.category,
    ru.product AS units_leader,
    ru.total_units_sold,
    rr.product AS revenue_leader,
    rr.total_revenue
FROM rank_by_units ru
LEFT JOIN rank_by_revenue rr
    ON ru.product = rr.product AND rr.rn = 1
WHERE ru.rn = 1
ORDER BY ru.category;


-- ========================================================================================================================
-- QUERY 5: Return rate by category, ranked
-- Question: Is the decline in Performance caused by a quality problem (more returns)?
-- Finding: Performance has a return rate of 1.04%, the same as Vitamin and slightly above the average (1.02%).
-- All 10 categories are between 0.94% and 1.07%. Returns are not the cause of the decline.

WITH category_returns AS (
    SELECT
        pr.category,
        SUM(fs.units_sold) AS total_units_sold,
        SUM(fs.units_returned) AS total_units_returned,
        CAST(SUM(units_returned) * 100.0 / SUM(units_sold) AS DECIMAL(5,2)) AS pct_returned
    FROM fact_sales fs
    JOIN dim_products pr ON fs.id_product = pr.id_product
    WHERE YEAR ([date]) <= 2024 
    GROUP BY pr.category
)
SELECT
    category,
    total_units_sold,
    total_units_returned,
    pct_returned,
    RANK() OVER (ORDER BY pct_returned DESC) AS rank_worst_returns
FROM category_returns ;

-- ========================================================================================================================
-- QUERY 6: Top 3 and bottom 3 products by revenue (2020-2024)
-- Question: Where are Performance's products in the product ranking?
-- Finding: Pre-Workout is in the top 3 products by revenue, and no Performance product is in the bottom 3.
-- All products earn between about $1.30M and $1.43M, so Performance is not a weak category.
-- It earns less than in 2020 because of lower prices (see Query 2).

WITH top_3 AS (
    SELECT TOP 3
        pr.product, pr.category, SUM(revenue) AS total_revenue, 'Top 3' AS [group]
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    WHERE YEAR([date]) <= 2024
    GROUP BY pr.product, pr.category
    ORDER BY total_revenue DESC
),
bottom_3 AS (
    SELECT TOP 3
        pr.product, pr.category, SUM(revenue) AS total_revenue, 'Bottom 3' AS [group]
    FROM fact_sales fs
    JOIN dim_products pr ON pr.id_product = fs.id_product
    WHERE YEAR([date]) <= 2024
    GROUP BY pr.product, pr.category
    ORDER BY total_revenue ASC
)
SELECT * FROM top_3
UNION ALL
SELECT * FROM bottom_3;

-- QUERY 7: Revenue jump in Q1 2022 (units vs. price)
-- Question: Why did revenue jump in the first quarter of 2022?
-- Finding: The jump came mainly from price, not from volume.
-- Q1 2022 revenue was about 14% above the average of the other Q1s (2020, 2021, 2023, 2024).
-- Units sold were almost the same in every Q1 (31,115 to 31,532).
-- The average price in Q1 2022 was $38.38. In the other years it was between $33.60 and $35.60.
-- The second query shows Vitamin and Mineral. Vitamin's price was $42.96 in Q1 2022 (other years: $31 to $33).
-- Mineral's price was also higher ($39.18), but it was already $37.19 in 2021.
-- The data does not explain why the price went up.

SELECT  YEAR([date]) as year, 
        SUM(revenue) as q1_revenue,
        SUM(units_sold) as q1_units_sold,
        CAST(AVG(price) AS DECIMAL(5,2)) as q1_avg_price
FROM fact_sales
WHERE DATEPART(QUARTER, [date]) = 1
 AND YEAR([date]) <= 2024
GROUP BY YEAR([date])
ORDER BY year;

SELECT
    pr.category,
    YEAR([date]) as year,
    SUM(fs.units_sold) as q1_units_sold,
    CAST(AVG(fs.price) AS DECIMAL(5,2)) as q1_avg_price
FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
WHERE DATEPART(QUARTER, [date]) = 1
  AND pr.category IN ('Vitamin', 'Mineral')
  AND YEAR([date]) <= 2024
GROUP BY pr.category, YEAR([date])
ORDER BY pr.category, year ;


-- QUERY 8: Performance revenue by country, 2020 vs. 2024
-- Question: Is the decline in Performance the same in every country?
-- Finding: No. Canada grew (+3.96%), UK fell (-18.23%) and USA fell the most (-25.03%).

WITH country_revenue as (
   SELECT
    l.location,
    SUM(CASE WHEN YEAR([date]) = 2020 THEN revenue END) as revenue_2020,
    SUM(CASE WHEN YEAR([date]) = 2024 THEN revenue END) as revenue_2024
FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
JOIN dim_locations l ON l.id_location = fs.id_location
WHERE pr.category = 'Performance'
GROUP BY l.location
)

SELECT  [location] ,
        revenue_2020,
        revenue_2024,
        CAST( (revenue_2024-revenue_2020) * 100 / revenue_2020 AS DECIMAL (5,2) ) as pct_change_2020_2024
        FROM country_revenue ;

-- QUERY 9: Creatine and Pre-Workout revenue in the USA, 2020 vs. 2024
-- Question: Inside the USA, which product explains the decline?
-- Finding: Creatine fell by almost half (-48.85%). Pre-Workout fell much less (-9.85%).

WITH usa_product_revenue AS (SELECT
    pr.product,
    SUM(CASE WHEN YEAR([date]) = 2020 THEN revenue END) as revenue_2020,
    SUM(CASE WHEN YEAR([date]) = 2024 THEN revenue END) as revenue_2024
FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
JOIN dim_locations l ON l.id_location = fs.id_location
WHERE pr.category = 'Performance' AND l.location = 'USA'
GROUP BY pr.product )

SELECT product , revenue_2020 , revenue_2024 ,
       CAST ( (revenue_2024 - revenue_2020) * 100.0 / revenue_2020 AS DECIMAL (5,2) ) as pct_change_2020_2024
FROM usa_product_revenue ;

-- QUERY 10: Creatine in the USA, units sold and average price, 2020 vs. 2024
-- Question: Did Creatine lose revenue because of units, price, or both?
-- Finding: Both. Units fell by about 29% and the average price fell by about 29%.

WITH creatine_units AS (
   SELECT  pr.product, 
		SUM(CASE WHEN YEAR([date]) = 2020 THEN units_sold END) as units_sold_2020,
		SUM(CASE WHEN YEAR([date]) = 2024 THEN units_sold END) as units_sold_2024
		FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
JOIN dim_locations l ON l.id_location = fs.id_location
WHERE [location] = 'USA' AND pr.product = 'Creatine'
GROUP BY pr.product )

SELECT  product, units_sold_2020 , units_sold_2024,
        CAST ( (units_sold_2024 - units_sold_2020) * 100.0 / units_sold_2020 AS DECIMAL (5,2) ) as pct_change_2020_2024
    FROM creatine_units ;

WITH price AS (
    SELECT  pr.product, 
		AVG(CASE WHEN YEAR([date]) = 2020 THEN price END) as avg_price_2020,
		AVG(CASE WHEN YEAR([date]) = 2024 THEN price END) as avg_price_2024
		FROM fact_sales fs
JOIN dim_products pr ON pr.id_product = fs.id_product
JOIN dim_locations l ON l.id_location = fs.id_location
WHERE [location] = 'USA' AND pr.product = 'Creatine'
GROUP BY pr.product )

SELECT  product, avg_price_2020 , avg_price_2024 ,
        CAST( (avg_price_2024 - avg_price_2020) * 100.00 / avg_price_2020 AS DECIMAL (5,2) ) as pct_change_2020_2024
    FROM price ;