-- ======================================================
-- E-COMMERCE ANALYTICS PROJECT
-- Indexes: Performance Optimization
-- 
-- These indexes speed up joins, filters, and groupings
-- used in the analytical views.
-- ======================================================

-- 1. Customer Index (Used in CLV, Churn, and Cohort views)
CREATE INDEX IF NOT EXISTS idx_customerid ON online_retail(customerid);

-- 2. Date Index (Used in Executive KPIs and Cohort views)
CREATE INDEX IF NOT EXISTS idx_invoicedate ON online_retail(invoicedate);

-- 3. Composite Index: Customer + Date (For cohort analysis)
CREATE INDEX IF NOT EXISTS idx_customerid_date ON online_retail(customerid, invoicedate);

-- 4. Return Flag Index (Used in Churn and KPI views)
CREATE INDEX IF NOT EXISTS idx_return_flag ON online_retail(return_flag);

-- 5. Composite Index: Customer + Return Flag (For churn scoring)
CREATE INDEX IF NOT EXISTS idx_customerid_return ON online_retail(customerid, return_flag);

-- 6. Invoice & Stock Index (For Product Affinity / Market Basket)
CREATE INDEX IF NOT EXISTS idx_invoice_stock ON online_retail(invoiceno, stockcode);

-- 7. Stock Code Index (For product filtering)
CREATE INDEX IF NOT EXISTS idx_stockcode ON online_retail(stockcode);

-- Optional: Analyze table to update statistics for query planner
ANALYZE online_retail;



