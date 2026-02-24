# AWS region where all resources will be deployed
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

# Kinesis stream name for real-time stock data ingestion
variable "kinesis_stream_name" {
  description = "Name of the Kinesis stream"
  default     = "stock_data_stream"
}

# DynamoDB table name for storing processed stock data
variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  default     = "stock-data-table"
}

# S3 bucket for storing raw unprocessed stock data
# Used by Athena for historical analysis
variable "s3_bucket_name" {
  description = "S3 bucket name for raw stock data"
  default     = "stock-data-bucket6969"
}

# S3 bucket for storing Athena query results
variable "athena_bucket_name" {
  description = "S3 bucket name for Athena query results"
  default     = "athena-query-results6969"
}

# SNS topic name for sending stock trend alerts
variable "sns_topic_name" {
  description = "SNS topic name for stock alerts"
  default     = "stock-trend-alerts"
}

# Email address to receive uptrend and downtrend SNS alerts
variable "alert_email" {
  description = "Email address to receive stock trend alerts"
  default     = "anilpoka910@gmail.com"
}

