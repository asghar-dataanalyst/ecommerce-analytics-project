-- ======================================================
-- E-COMMERCE ANALYTICS PROJECT
-- Schema: Table Creation
-- 
-- This script creates the main fact table for 
-- the UCI Online Retail dataset (2010-2011).
-- ======================================================

-- Drop table if it exists 
-- DROP TABLE IF EXISTS online_retail;

-- Create the main table
CREATE TABLE IF NOT EXISTS online_retail (
    invoiceno       VARCHAR(20),    -- Invoice number (C prefix = cancelled)
    stockcode       VARCHAR(20),    -- Product code
    description     TEXT,           -- Product description
    quantity        INTEGER,        -- Units sold (negative = returns)
    invoicedate     TIMESTAMP,      -- Transaction date & time
    unitprice       NUMERIC(10,2),  -- Price per unit
    customerid      VARCHAR(20),    -- Customer identifier (blank = guest)
    country         VARCHAR(50),    -- Customer country
    totalamount     NUMERIC(10,2),  -- Calculated: quantity * unitprice
    return_flag     VARCHAR(10),    -- 'Sale' or 'Return'
    customer_type   VARCHAR(20)     -- 'Guest' or 'Registered'
);


COMMENT ON TABLE online_retail IS 'Main transaction fact table for UCI Online Retail (2010-2011)';

