# Design Decisions — AWS Stock Market Analytics Pipeline

This document explains the architectural choices made when building this pipeline, the alternatives that were considered, and the reasoning behind each decision. These are not arbitrary choices — each one was made based on the specific requirements of a real-time stock market analytics system operating within AWS Free Tier constraints.

---

## 1. Why Kinesis over SQS

The first decision was how to ingest real-time stock data into the pipeline.

**SQS** is AWS's simple queue service. It's excellent for decoupling services and handling task queues where each message is consumed once and order doesn't matter. However SQS has a critical limitation for this use case — messages are consumed and deleted. Once Lambda reads a message it's gone. There is no way for a second consumer to read the same message and no way to replay historical data.

**Kinesis** is a real-time data streaming service designed specifically for high-throughput ordered data. Records are retained for 24 hours by default and multiple consumers can read the same stream simultaneously without interfering with each other. Data is ordered within each shard using sequence numbers.

For a stock market pipeline ordering matters. If price records arrive out of order the moving average calculations produce incorrect results. Kinesis guarantees ordering within a shard using the stock symbol as the partition key — all AAPL records go to the same shard in order.

The choice was clear: Kinesis for ordered real-time streaming, SQS for simple task queues.

---

## 2. Why DynamoDB over RDS

The pipeline needs to store processed stock records and query them in milliseconds for real-time trend analysis.

**RDS** is AWS's managed relational database — MySQL, PostgreSQL, and others. RDS is excellent for complex relational data with joins, transactions, and structured schemas. However RDS requires a continuously running instance even when idle, which costs money 24/7. It also requires schema migrations every time the data model changes.

**DynamoDB** is AWS's managed NoSQL key-value and document database. It delivers single-digit millisecond read and write latency at any scale. There is no server to manage, no idle costs on PAY_PER_REQUEST billing mode, and the flexible schema means adding new fields to records requires no migration.

For this use case the query pattern is simple — fetch recent records for a specific stock symbol sorted by timestamp. DynamoDB's partition key (symbol) and sort key (timestamp) are designed exactly for this pattern. RDS would add unnecessary complexity and cost for a workload that doesn't need relational joins.

---

## 3. Why Two Lambda Functions Instead of One

The pipeline uses two separate Lambda functions — ProcessStockData and StockTrendAnalysis — instead of combining everything into one.

A single Lambda function could theoretically handle everything — read from Kinesis, store to DynamoDB and S3, then immediately calculate moving averages and send SNS alerts. But this creates several problems.

First, ProcessStockData is triggered by Kinesis and must be fast. Adding SMA calculations to it would slow it down and increase costs since Lambda bills per millisecond of execution.

Second, StockTrendAnalysis needs to query DynamoDB for historical records across multiple previous invocations. If this logic ran inside the Kinesis Lambda it would be querying data that may not yet be fully committed to DynamoDB — creating a race condition.

Third, separating the functions means each can be updated, monitored, debugged, and scaled independently. If the trend analysis logic needs to change the ingestion function is not affected.

DynamoDB Streams solves the sequencing problem elegantly — StockTrendAnalysis only triggers after a record is fully committed to DynamoDB, guaranteeing the data it needs is already there.

---

## 4. Why S3 and Athena for Historical Analysis

The pipeline stores raw JSON data in S3 and uses Athena with a Glue catalog for historical SQL queries instead of querying DynamoDB directly.

**The DynamoDB scan problem:** DynamoDB is optimized for key-based lookups. Scanning the entire table to answer questions like "what was the average volume every Monday over the last six months" is expensive — DynamoDB charges per read capacity unit consumed. A full table scan across thousands of records can cost significantly more than a targeted query.

**S3 and Athena cost model:** S3 storage costs approximately $0.023 per GB per month — essentially free for this project's data volume. Athena charges $5 per terabyte of data scanned. For a small dataset this means historical queries cost fractions of a cent. There is no running database to pay for when queries aren't happening.

**Raw data as source of truth:** Storing raw unprocessed JSON in S3 means the original data is always available. If the processing logic changes — different anomaly threshold, new calculated fields, updated moving average periods — the raw data can be reprocessed from scratch. If only processed data was stored this reprocessing would be impossible.

This pattern — streaming storage in DynamoDB for real-time queries, archival storage in S3 for historical analysis — is a standard architecture pattern in production data platforms.

---

## 5. Why Serverless over EC2

The pipeline uses Lambda, DynamoDB, Kinesis, SNS, and Athena — all fully managed serverless services. No EC2 instances were used.

**EC2 approach:** A traditional approach would run a Python script on an EC2 instance continuously polling for new data and processing it. This requires the instance to run 24/7 even when stock markets are closed and data volume is zero. It requires patching, monitoring, and managing the operating system. It costs money even when idle.

**Serverless approach:** Lambda only runs when triggered by new data. During off-market hours when no data is flowing Lambda invocations drop to zero and costs drop to zero. There is no server to patch, no OS to manage, and no capacity to provision.

For a data pipeline with variable load — high volume during market hours, zero volume overnight and on weekends — serverless is dramatically more cost-efficient and operationally simpler than EC2.

---

## 6. Why Terraform over AWS Console or CloudFormation

The infrastructure is managed using Terraform rather than clicking through the AWS console or using AWS CloudFormation.

**Console clicking problems:** Manual console deployments are not repeatable. Two engineers following the same instructions will make slightly different choices. There is no audit trail of what was changed and when. Recreating the infrastructure after an accidental deletion requires remembering every step.

**CloudFormation:** AWS's native Infrastructure as Code tool. CloudFormation works well but uses verbose JSON or YAML syntax and is tightly coupled to AWS. If the project ever needs resources from another cloud provider CloudFormation cannot manage them.

**Terraform advantages:** Terraform uses clean readable HCL syntax. It supports AWS, Azure, Google Cloud, and hundreds of other providers in a single tool. The plan command shows exactly what will change before anything is applied — a safety check that CloudFormation lacks. The state file provides a complete record of every managed resource. Terraform is the industry standard IaC tool for multi-cloud environments and is heavily requested in job postings.

The result: the entire 21-resource pipeline can be destroyed and redeployed from scratch in under 2 minutes from any machine with AWS credentials configured.

---

## 7. Why CloudWatch for Monitoring

Rather than only building the pipeline and considering it done, a CloudWatch dashboard was added to monitor the health of every layer.

Without monitoring a pipeline can fail silently. Lambda errors accumulate without anyone noticing. Kinesis throughput spikes go undetected. DynamoDB latency degrades without any alert.

The CloudWatch dashboard provides real-time visibility into Lambda invocation counts and error rates, Kinesis incoming record throughput, DynamoDB read and write latency, and Lambda execution duration trends. This is the difference between a tutorial project and a production-grade system. In real companies every data pipeline has observability built in from day one.

---

## 8. Trade-offs and Limitations

Every architectural decision involves trade-offs. Here are the honest limitations of this design.

**Not truly real-time:** Data arrives every 30 seconds. Lambda triggers every 60 seconds with batch size 2. This is near real-time not true real-time. A genuine real-time system would use WebSocket connections or sub-second streaming. For a portfolio project demonstrating AWS services this delay is acceptable and keeps costs within Free Tier.

**Single stock:** The pipeline only tracks AAPL. Extending to multiple stocks would require additional Kinesis shards, updated Lambda logic, and higher costs. The architecture supports this extension without redesign — it would simply require adding symbols to the streaming script and additional Kinesis partition keys.

**Local state file:** Terraform state is stored locally. In a team environment this would be moved to an S3 backend with DynamoDB state locking to prevent concurrent modifications and enable collaboration across machines.

**No error recovery:** Failed Lambda records are currently dropped. A production system would add a Dead Letter Queue to capture and reprocess failed records so no data is lost during transient errors.
