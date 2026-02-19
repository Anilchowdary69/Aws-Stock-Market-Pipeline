# AWS Real-Time Stock Market Analytics Pipeline

A production-grade, serverless data pipeline built on AWS that ingests, processes, stores, and analyzes real-time stock market data using event-driven architecture.

---

## What This Project Does

This pipeline fetches live Apple (AAPL) stock price data every 30 seconds, streams it through AWS Kinesis, processes it with Lambda, stores structured data in DynamoDB for fast querying, archives raw data in S3 for historical analysis, and sends real-time alerts via SNS when unusual price movements are detected.

---

## Architecture

```
yfinance (Local Python Script)
        |
        v
Amazon Kinesis Data Streams
        |
        v
AWS Lambda (ProcessStockData)
        |
        |-----> Amazon DynamoDB (structured, processed data)
        |-----> Amazon S3 (raw JSON archive)
        |-----> Amazon SNS (anomaly alerts via Email/SMS)
                |
                v
        Amazon Athena (SQL queries on S3 data)
```

---

## Services Used & Why

| Service | Purpose | Why This Over Alternatives |
|---|---|---|
| Amazon Kinesis | Real-time data ingestion | Handles high-throughput ordered streams. Chose over SQS because stock data requires ordering and supports multiple consumers simultaneously |
| AWS Lambda | Data processing & anomaly detection | Serverless — scales automatically with market volume. No idle server costs |
| Amazon DynamoDB | Structured data storage | Millisecond read/write for real-time querying. Chose over RDS because schema flexibility and speed matter more than relational joins |
| Amazon S3 | Raw data archive | Cheapest long-term storage. Enables Athena queries without a running database |
| Amazon Athena | Historical SQL analysis | Pay-per-query serverless SQL. Chose over Redshift to avoid 24/7 cluster costs for occasional historical queries |
| Amazon SNS | Real-time alerts | Simplest way to fan out notifications to Email/SMS at scale |
| AWS Glue | Schema catalog for Athena | Required to define S3 data structure so Athena can query it |
| IAM Roles | Security & permissions | Least-privilege access between all services |

---

## Key Design Decisions

**Why Kinesis over SQS?**
Stock data requires ordered, high-throughput ingestion with the ability for multiple consumers to read the same stream. SQS is better for simple decoupled task queues where ordering doesn't matter. Kinesis was the right choice here.

**Why DynamoDB over RDS?**
We need millisecond read/write for real-time stock lookups. DynamoDB's flexible schema also makes it easy to add new fields without migrations. RDS would be overkill and more expensive for this use case.

**Why Athena over Redshift?**
Historical analysis happens occasionally, not continuously. Running a full Redshift cluster 24/7 just for occasional queries is expensive and unnecessary. Athena charges per query scanned — far more cost-efficient for this workload.

**Why 30-second ingestion intervals?**
Balances near real-time responsiveness with free tier cost management. Batch size of 2 in Lambda means it triggers every 60 seconds — sufficient for trend detection without excessive invocations.

---

## Project Structure

```
aws-stock-market-pipeline/
├── README.md
├── architecture-diagram.png
├── src/
│   └── stream_stock_data.py       # Local Python script — fetches & streams stock data
├── lambda/
│   └── lambda_function.py         # Lambda function — processes, stores, detects anomalies
├── athena/
│   └── queries.sql                # SQL queries for historical analysis
├── terraform/
│   └── (coming soon)              # Infrastructure as Code
└── docs/
    └── design-decisions.md        # Detailed architecture reasoning
```

---

## How It Works

**Step 1 — Data Ingestion**
A local Python script uses `yfinance` to fetch AAPL stock data every 30 seconds and sends it to a Kinesis Data Stream using `boto3`.

**Step 2 — Processing**
Lambda triggers every 60 seconds (batch size 2), decodes the Kinesis records, computes additional metrics, and routes data to storage.

**Step 3 — Storage**
Raw JSON files land in S3 organized by symbol and timestamp. Processed, enriched records (including moving average, anomaly flag) land in DynamoDB.

**Step 4 — Analysis**
Athena queries the S3 raw data directly using a Glue catalog schema — no database required.

**Step 5 — Alerts**
If price movement exceeds 5%, Lambda triggers SNS to send an Email/SMS alert in real time.

---

## Data Schema

Each processed record stored in DynamoDB:

| Field | Type | Description |
|---|---|---|
| symbol | String | Stock ticker (e.g. AAPL) |
| timestamp | String | ISO 8601 timestamp |
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

## Cost Estimate

This pipeline runs at approximately $1-2/month within AWS Free Tier limits.

| Service | Free Tier | This Project |
|---|---|---|
| Kinesis | 1 shard free | 1 shard used |
| Lambda | 1M requests/month free | ~2,880 invocations/day |
| DynamoDB | 25GB free | < 1GB |
| S3 | 5GB free | < 1GB |
| Athena | $5 per TB scanned | Minimal |
| SNS | 1M notifications free | Minimal |

**Important:** Always stop the Python script with `CTRL+C` when not testing. Leaving it running continuously will exceed free tier limits.

---

## What I Would Do Differently At Scale

- Replace single-stock AAPL feed with multi-stock ingestion using multiple Kinesis shards
- Add Kinesis Data Firehose for automatic S3 batching instead of Lambda writing directly
- Move from DynamoDB to Redshift for complex analytical queries at scale
- Add Dead Letter Queue (DLQ) for failed Lambda records
- Implement CloudWatch alarms for Lambda error rates and Kinesis throttling
- Add Terraform to manage all infrastructure as code

---

## Setup & Deployment

**Prerequisites**
- AWS Account
- Python 3.8+
- AWS CLI configured (`aws configure`)
- `boto3` and `yfinance` installed (`pip install boto3 yfinance`)

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

Built as part of a cloud engineering portfolio to demonstrate real-world AWS data pipeline architecture.
