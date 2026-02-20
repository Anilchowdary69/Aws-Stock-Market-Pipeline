# AWS Real-Time Stock Market Analytics Pipeline

A production-grade, serverless data pipeline built on AWS that ingests, processes, stores, analyzes, and monitors real-time stock market data using event-driven architecture.

---

## What This Project Does

This pipeline fetches live Apple (AAPL) stock price data every 30 seconds, streams it through AWS Kinesis, processes it with Lambda, stores structured data in DynamoDB for fast querying, archives raw data in S3 for historical analysis, detects stock trend reversals using Simple Moving Averages, sends real-time alerts via SNS, and monitors the entire system through a CloudWatch dashboard.

---

## Architecture

```
yfinance (Local Python Script)
        |
        v
Amazon Kinesis Data Streams
        |
        v
AWS Lambda — ProcessStockData
        |
        |-----> Amazon DynamoDB (structured, processed data)
        |            |
        |            v
        |       DynamoDB Streams
        |            |
        |            v
        |       AWS Lambda — StockTrendAnalysis
        |            |
        |            v
        |       Amazon SNS (Email/SMS trend alerts)
        |
        |-----> Amazon S3 (raw JSON archive)
                     |
                     v
              AWS Glue Data Catalog
                     |
                     v
              Amazon Athena (SQL queries on historical data)

All services monitored via Amazon CloudWatch Dashboard
```

> Replace this text diagram with your draw.io architecture image

---

## Live Pipeline Screenshots

### CloudWatch Monitoring Dashboard
![CloudWatch Dashboard](cloudwatch-dashboard.png)

### SNS Trend Alert — Uptrend Notification
![SNS Uptrend Alert](sns-uptrend-alert.png)

### SNS Trend Alert — Downtrend Notification
![SNS Downtrend Alert](sns-downtrend-alert.png)

### DynamoDB Records
![DynamoDB Records](dynamodb-records.png)

### S3 Raw Data
![S3 Raw Data](s3-raw-data.png)

---

## Services Used & Why

| Service | Purpose | Why This Over Alternatives |
|---|---|---|
| Amazon Kinesis | Real-time data ingestion | Handles high-throughput ordered streams. Chose over SQS because stock data requires ordering and supports multiple consumers simultaneously |
| AWS Lambda | Data processing, anomaly detection, trend analysis | Serverless — scales automatically with market volume. No idle server costs unlike EC2 |
| Amazon DynamoDB | Structured data storage | Millisecond read/write for real-time querying. Chose over RDS because schema flexibility and speed matter more than relational joins |
| DynamoDB Streams | Change capture | Triggers trend analysis Lambda every time a new record arrives without polling |
| Amazon S3 | Raw data archive | Cheapest long-term storage. Enables Athena queries without a running database |
| AWS Glue | Schema catalog | Defines S3 data structure so Athena can query it without loading data into a database first |
| Amazon Athena | Historical SQL analysis | Pay-per-query serverless SQL. Chose over Redshift to avoid 24/7 cluster costs for occasional historical queries |
| Amazon SNS | Real-time alerts | Simple fan-out notification system. One Lambda call notifies all subscribers simultaneously |
| Amazon CloudWatch | Monitoring & observability | Tracks Lambda errors, invocation counts, DynamoDB latency, and Kinesis throughput in one dashboard |
| IAM Roles | Security & permissions | Least-privilege access between all services |

---

## Key Design Decisions

**Why Kinesis over SQS?**
Stock data requires ordered, high-throughput ingestion with the ability for multiple consumers to read the same stream. SQS is better for simple decoupled task queues where ordering does not matter. Kinesis was the right choice here.

**Why DynamoDB over RDS?**
Millisecond read/write is required for real-time stock lookups. DynamoDB's flexible schema also makes it easy to add new fields without migrations. RDS would be overkill and more expensive for this use case.

**Why Athena over Redshift?**
Historical analysis happens occasionally, not continuously. Running a full Redshift cluster 24/7 just for occasional queries is expensive and unnecessary. Athena charges per query scanned — far more cost-efficient for this workload.

**Why two Lambda functions instead of one?**
Separation of concerns. ProcessStockData handles ingestion and storage — it needs to be fast and lightweight. StockTrendAnalysis handles complex moving average calculations requiring historical DynamoDB data. Combining them would create a slow, tightly coupled function that is harder to debug and maintain.

**Why 30-second ingestion intervals?**
Balances near real-time responsiveness with free tier cost management. Batch size of 2 means Lambda triggers every 60 seconds — sufficient for trend detection without excessive invocations.

**Why DynamoDB Streams instead of triggering trend Lambda from Kinesis?**
Trend analysis requires historical data already stored in DynamoDB. Triggering from Kinesis would mean the trend Lambda runs before data is written. DynamoDB Streams guarantees data is persisted before trend analysis begins.

---

## How Trend Detection Works

The StockTrendAnalysis Lambda uses Simple Moving Averages to detect trend reversals — a real concept used in financial markets.

**SMA-5** — average of the last 5 price readings. Reacts quickly to recent movements.

**SMA-20** — average of the last 20 price readings. Moves slowly and represents the bigger trend.

When SMA-5 crosses above SMA-20 — prices are accelerating upward. This is a **Golden Cross** — a BUY signal. Lambda fires an SNS alert.

When SMA-5 crosses below SMA-20 — prices are dropping. This is a **Death Cross** — a SELL signal. Lambda fires an SNS alert.

During a 30-minute live test both a Golden Cross and Death Cross were detected and SNS alerts were delivered via email confirming the system works end to end.

---

## Project Structure

```
aws-stock-market-pipeline/
├── README.md
├── architecture-diagram.png
├── cloudwatch-dashboard.png
├── sns-uptrend-alert.png
├── sns-downtrend-alert.png
├── dynamodb-records.png
├── s3-raw-data.png
├── src/
│   └── stream_stock_data.py          # Local script — fetches & streams stock data to Kinesis
├── lambda/
│   ├── process_stock_data.py         # Lambda 1 — processes Kinesis records, stores to DynamoDB & S3
│   └── stock_trend_analysis.py       # Lambda 2 — calculates SMAs, detects trends, fires SNS alerts
├── athena/
│   └── queries.sql                   # SQL queries for historical analysis
├── terraform/
│   └── (coming soon)                 # Full pipeline rebuilt as Infrastructure as Code
└── docs/
    └── design-decisions.md           # Detailed architecture reasoning
```

---

## Data Schema

Each processed record stored in DynamoDB:

| Field | Type | Description |
|---|---|---|
| symbol | String | Stock ticker (e.g. AAPL) — Partition Key |
| timestamp | String | ISO 8601 timestamp — Sort Key |
| open | Decimal | Opening price |
| high | Decimal | Day high |
| low | Decimal | Day low |
| price | Decimal | Current price |
| previous_close | Decimal | Previous day closing price |
| change | Decimal | Price change from previous close |
| change_percent | Decimal | Percentage change |
| volume | Integer | Trading volume |
| moving_average | Decimal | Average of open/high/low/close |
| anomaly | String | "Yes" if change > 5%, else "No" |

---

## Athena Queries

```sql
-- Basic data retrieval
SELECT * FROM stock_data_table LIMIT 10;

-- Top 5 stocks with highest price change
SELECT symbol, price, previous_close,
       (price - previous_close) AS price_change
FROM stock_data_table
ORDER BY price_change DESC
LIMIT 5;

-- Average trading volume per stock
SELECT symbol, AVG(volume) AS avg_volume
FROM stock_data_table
GROUP BY symbol;

-- Anomalous stocks (price change > 5%)
SELECT symbol, price, previous_close,
       ROUND(((price - previous_close) / previous_close) * 100, 2) AS change_percent
FROM stock_data_table
WHERE ABS(((price - previous_close) / previous_close) * 100) > 5;
```

---

## CloudWatch Monitoring Dashboard

A CloudWatch dashboard monitors the entire pipeline in real time with the following widgets:

- Lambda invocation count and error rate for ProcessStockData and StockTrendAnalysis
- Kinesis incoming records and throughput per shard
- DynamoDB SuccessfulRequestLatency for both Query and Scan operations
- Lambda duration trends over time

This provides full observability into the pipeline without checking each service individually — the same approach used in production environments.

---

## Challenges & Lessons Learned

**Hidden character bug in Lambda:** When copy pasting code from documentation into the Lambda editor, invisible Unicode zero-width space characters (U+200B) caused a silent syntax error. The Lambda editor highlights these with a yellow marker. Fix — delete the affected line and retype it manually. Lesson: always scan for yellow highlights in the Lambda code editor before clicking Deploy.

**Kinesis is not storage:** Data disappears from Kinesis after Lambda consumes it — this is by design. Kinesis is a temporary pipe, not a storage system. Permanent storage lives in DynamoDB and S3.

**Silent Lambda skips:** The trend analysis Lambda silently skips if fewer than 20 records exist in DynamoDB. Adding meaningful print statements to Lambda functions is essential for debugging serverless functions. Silent code is impossible to troubleshoot in CloudWatch.

**Always add logging from day one:** The first version of StockTrendAnalysis had no print statements. When it ran silently with no output it was impossible to tell if it was working correctly or skipping entirely. Proper logging is not optional in production systems.

---

## Cost Estimate

This pipeline runs at approximately $1-2/month within AWS Free Tier limits.

| Service | Free Tier | This Project Usage |
|---|---|---|
| Kinesis | 1 shard free | 1 shard, ~2,880 records/day |
| Lambda | 1M requests/month free | ~2,880 invocations/day per function |
| DynamoDB | 25GB storage free | Less than 1MB |
| S3 | 5GB free | Less than 1MB |
| Athena | $5 per TB scanned | Minimal — small dataset |
| SNS | 1M notifications free | Minimal |
| CloudWatch | 10 metrics free | Under free tier limit |

**Important:** Always stop the Python script with `CTRL+C` when not testing. Leaving it running continuously will exceed free tier limits.

---

## What I Would Do Differently At Scale

- Replace single-stock AAPL feed with multi-stock ingestion using multiple Kinesis shards — one shard per stock symbol
- Add Kinesis Data Firehose for automatic S3 batching instead of Lambda writing individual files
- Move from DynamoDB to Redshift for complex analytical queries at scale
- Add Dead Letter Queue for failed Lambda records so no data is lost on processing errors
- Replace the simple 5% anomaly threshold with a machine learning model trained on historical S3 data using SageMaker
- Use AWS Secrets Manager instead of hardcoded ARNs and table names in Lambda code
- Full Terraform deployment for repeatable infrastructure across dev, staging, and production environments

---

## Setup & Deployment

**Prerequisites**
- AWS Account
- Python 3.8+
- AWS CLI configured (`aws configure`)
- boto3 and yfinance installed (`pip install boto3 yfinance`)

**Run the pipeline**
```bash
python src/stream_stock_data.py
```

**Stop the pipeline**
```
CTRL+C
```

---

## Author

Built as part of a cloud engineering portfolio to demonstrate real-world AWS data pipeline architecture, serverless computing, event-driven design, and production observability practices.
