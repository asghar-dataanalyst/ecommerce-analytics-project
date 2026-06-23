-- ======================================================
-- E-COMMERCE ANALYTICS PROJECT
-- Views & Materialized View
-- 
-- This file contains all analytical views created for 
-- the Power BI dashboard (2010-2011 data).
-- ======================================================

-- ------------------------------------------------------
-- 1. View: Executive KPIs
-- ------------------------------------------------------

CREATE OR REPLACE VIEW vw_executive_kpi AS
WITH daily_metrics AS (
    SELECT 
        DATE(invoicedate) AS date,
        COUNT(DISTINCT CASE WHEN return_flag = 'Sale' THEN invoiceno END) AS orders,
        COUNT(DISTINCT CASE WHEN return_flag = 'Sale' THEN customerid END) AS active_customers,
        SUM(CASE WHEN return_flag = 'Sale' THEN totalamount ELSE 0 END) AS revenue,
        SUM(CASE WHEN return_flag = 'Return' THEN ABS(totalamount) ELSE 0 END) AS returns_value,
        COUNT(DISTINCT CASE WHEN return_flag = 'Return' THEN invoiceno END) AS return_orders,
        COUNT(DISTINCT CASE WHEN customer_type = 'Guest' THEN customerid END) AS guest_customers,
        COUNT(DISTINCT CASE WHEN customer_type = 'Registered' THEN customerid END) AS registered_customers
    FROM online_retail
    WHERE customerid IS NOT NULL
    GROUP BY DATE(invoicedate)
)
SELECT 
    date,
    revenue,
    returns_value,
    ROUND(100.0 * returns_value / NULLIF(revenue, 0), 2) AS return_rate_pct,
    orders,
    active_customers,
    ROUND(revenue / NULLIF(orders, 0), 2) AS aov,
    guest_customers,
    registered_customers,
    ROUND(100.0 * guest_customers / NULLIF(active_customers, 0), 2) AS guest_vs_registered_pct,
    ROUND(revenue / 1000, 2) AS revenue_k,
    ROUND(AVG(revenue) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS weekly_moving_avg
FROM daily_metrics
WHERE date >= (SELECT MAX(date) FROM daily_metrics) - INTERVAL '90 days'
ORDER BY date DESC;


-- ------------------------------------------------------
-- 2. View: CLV & Pareto
-- ------------------------------------------------------

CREATE OR REPLACE VIEW vw_clv_pareto AS
WITH customer_value AS (
    SELECT 
        customerid,
        SUM(CASE WHEN return_flag = 'Sale' THEN totalamount ELSE 0 END) AS lifetime_value,
        COUNT(DISTINCT invoiceno) AS total_orders,
        SUM(CASE WHEN return_flag = 'Sale' THEN quantity ELSE 0 END) AS total_items,
        EXTRACT(DAY FROM MAX(invoicedate) - MIN(invoicedate)) AS customer_life_days
    FROM online_retail
    WHERE customerid IS NOT NULL AND customerid != ''
    GROUP BY customerid
),
pareto AS (
    SELECT 
        customerid,
        lifetime_value,
        total_orders,
        customer_life_days,
        SUM(lifetime_value) OVER () AS total_revenue,
        SUM(lifetime_value) OVER (ORDER BY lifetime_value DESC) AS running_revenue,
        ROW_NUMBER() OVER (ORDER BY lifetime_value DESC) AS customer_rank,
        COUNT(*) OVER () AS total_customers
    FROM customer_value
    WHERE lifetime_value > 0
)
SELECT 
    customerid,
    lifetime_value,
    total_orders,
    customer_life_days,
    ROUND(100.0 * customer_rank / total_customers, 2) AS customer_percentile,
    ROUND(100.0 * running_revenue / total_revenue, 2) AS revenue_contribution_pct,
    CASE 
        WHEN 100.0 * running_revenue / total_revenue <= 80 THEN 'Top 20% (Core Revenue)'
        WHEN 100.0 * customer_rank / total_customers <= 50 THEN 'Mid 30%'
        ELSE 'Bottom 50%'
    END AS segment
FROM pareto
ORDER BY lifetime_value DESC;


-- ------------------------------------------------------
-- 3. View: Cohort Retention
-- ------------------------------------------------------

CREATE OR REPLACE VIEW vw_cohort_retention AS
WITH cohort_customers AS (
    SELECT 
        customerid,
        MIN(DATE_TRUNC('month', invoicedate)) AS cohort_month
    FROM online_retail
    WHERE customerid IS NOT NULL AND customerid != '' AND return_flag = 'Sale'
    GROUP BY customerid
),
cohort_activity AS (
    SELECT 
        c.cohort_month,
        DATE_TRUNC('month', o.invoicedate) AS activity_month,
        COUNT(DISTINCT o.customerid) AS active_customers,
        SUM(o.totalamount) AS cohort_revenue
    FROM online_retail o
    JOIN cohort_customers c ON o.customerid = c.customerid
    WHERE o.return_flag = 'Sale'
    GROUP BY c.cohort_month, activity_month
),
cohort_size AS (
    SELECT cohort_month, active_customers AS initial_size
    FROM cohort_activity
    WHERE cohort_month = activity_month
),
cohort_data AS (
    SELECT 
        TO_CHAR(ca.cohort_month, 'YYYY-MM') AS cohort_month,
        EXTRACT(MONTH FROM ca.activity_month) - EXTRACT(MONTH FROM ca.cohort_month) 
            + (EXTRACT(YEAR FROM ca.activity_month) - EXTRACT(YEAR FROM ca.cohort_month)) * 12 + 1 AS month_offset,
        ca.active_customers,
        cs.initial_size,
        ROUND(100.0 * ca.active_customers / cs.initial_size, 2) AS retention_rate_pct,
        ROUND(ca.cohort_revenue, 2) AS cohort_revenue,
        ROUND(ca.cohort_revenue / NULLIF(ca.active_customers, 0), 2) AS revenue_per_active_customer
    FROM cohort_activity ca
    JOIN cohort_size cs ON ca.cohort_month = cs.cohort_month
)
SELECT *
FROM cohort_data
WHERE month_offset <= 12
ORDER BY cohort_month, month_offset;



-- ------------------------------------------------------
-- 4. View: Churn Risk
-- ------------------------------------------------------

CREATE OR REPLACE VIEW vw_churn_risk AS
WITH customer_behavior AS (
    SELECT 
        customerid,
        MAX(invoicedate) AS last_purchase,
        MIN(invoicedate) AS first_purchase,
        COUNT(DISTINCT invoiceno) AS frequency,
        SUM(CASE WHEN return_flag = 'Sale' THEN totalamount ELSE 0 END) AS monetary,
        SUM(CASE WHEN return_flag = 'Return' THEN 1 ELSE 0 END) AS return_count,
        AVG(CASE WHEN return_flag = 'Sale' THEN totalamount END) AS avg_order_value,
        STDDEV(CASE WHEN return_flag = 'Sale' THEN totalamount END) AS spending_volatility
    FROM online_retail
    WHERE customerid IS NOT NULL AND customerid != ''
    GROUP BY customerid
),
churn_scoring AS (
    SELECT 
        customerid,
        last_purchase,
        frequency,
        monetary,
        return_count,
        avg_order_value,
        spending_volatility,
        EXTRACT(DAY FROM (SELECT MAX(invoicedate) FROM online_retail) - last_purchase) AS recency_days,
        ROUND(EXTRACT(DAY FROM (SELECT MAX(invoicedate) FROM online_retail) - first_purchase) / 30.0, 1) AS customer_age_months,
        ROUND(
            CASE WHEN EXTRACT(DAY FROM (SELECT MAX(invoicedate) FROM online_retail) - last_purchase) > 90 THEN 40 ELSE 0 END +
            CASE WHEN return_count > 2 THEN 25 ELSE 0 END +
            CASE WHEN frequency = 1 THEN 20 ELSE 0 END +
            CASE WHEN avg_order_value < 20 THEN 15 ELSE 0 END
        , 2) AS churn_score
    FROM customer_behavior
)
SELECT 
    customerid,
    churn_score,
    CASE 
        WHEN churn_score >= 70 THEN 'Critical - Priority Outreach'
        WHEN churn_score >= 50 THEN 'High Risk - Send Offer'
        WHEN churn_score >= 30 THEN 'Medium Risk - Monitor'
        ELSE 'Low Risk - Retain'
    END AS risk_level,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    return_count,
    customer_age_months
FROM churn_scoring
WHERE churn_score > 30
ORDER BY churn_score DESC;


-- ------------------------------------------------------
-- 5. Materialized View: Product Affinity
-- ------------------------------------------------------

CREATE MATERIALIZED VIEW mv_product_affinity AS
WITH basket AS (
    SELECT invoiceno, stockcode
    FROM online_retail
    WHERE return_flag = 'Sale' AND stockcode IS NOT NULL
),
product_pairs AS (
    SELECT 
        a.stockcode AS product_a,
        b.stockcode AS product_b,
        COUNT(*) AS together_count
    FROM basket a
    JOIN basket b ON a.invoiceno = b.invoiceno AND a.stockcode < b.stockcode
    GROUP BY a.stockcode, b.stockcode
    HAVING COUNT(*) > 50   -- higher threshold to reduce rows
),
product_stats AS (
    SELECT stockcode, COUNT(DISTINCT invoiceno) AS orders
    FROM basket
    GROUP BY stockcode
),
total_orders AS (SELECT COUNT(DISTINCT invoiceno) AS total FROM basket)
SELECT 
    pp.product_a,
    pp.product_b,
    pp.together_count,
    ROUND(100.0 * pp.together_count / t.total, 2) AS support_pct,
    ROUND(100.0 * pp.together_count / ps_a.orders, 2) AS confidence_pct,
    ROUND((pp.together_count / ps_a.orders) / (ps_b.orders::NUMERIC / t.total), 2) AS lift
FROM product_pairs pp
JOIN product_stats ps_a ON pp.product_a = ps_a.stockcode
JOIN product_stats ps_b ON pp.product_b = ps_b.stockcode
CROSS JOIN total_orders t
ORDER BY lift DESC
LIMIT 50;


