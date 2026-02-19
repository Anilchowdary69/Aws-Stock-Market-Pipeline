Basic query:

SELECT * FROM stock_data_table LIMIT 10;

Advanced Queries:

1.Top 5 stocks with highest price change
SELECT symbol, price, previous_close,
       (price - previous_close) AS price_change
FROM "stock-glue-table"
ORDER BY price_change DESC
LIMIT 5;

2.Average trading volume per stock
SELECT symbol, AVG(volume) AS avg_volume
FROM "stock-glue-table"
GROUP BY symbol;

3.Anomalous stocks (price change > 5%)
SELECT symbol, price, previous_close,
       ROUND(((price - previous_close) / previous_close) * 100, 2) AS change_percent
FROM "stock-glue-table"
WHERE ABS(((price - previous_close) / previous_close) * 100) > 5;