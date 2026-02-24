# Kinesis stream ARN - needed for local Python script configuration
output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream"
  value       = aws_kinesis_stream.stock_market_stream.arn
}

# Kinesis stream name - used in lambda_function.py
output "kinesis_stream_name" {
  description = "Name of the Kinesis stream"
  value       = aws_kinesis_stream.stock_market_stream.name
}

# DynamoDB table name
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.stock_market_data.name
}

# S3 bucket name for raw data
output "s3_bucket_name" {
  description = "S3 bucket name for raw stock data"
  value       = aws_s3_bucket.raw_stock_data.bucket
}

# S3 bucket name for Athena results
output "athena_bucket_name" {
  description = "S3 bucket name for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

# SNS topic ARN - needed for Lambda environment variable
output "sns_topic_arn" {
  description = "ARN of the SNS topic for stock alerts"
  value       = aws_sns_topic.stock_alerts.arn
}

# Lambda function names
output "process_stock_data_function" {
  description = "Name of the ProcessStockData Lambda function"
  value       = aws_lambda_function.process_stock_data.function_name
}

output "stock_trend_analysis_function" {
  description = "Name of the StockTrendAnalysis Lambda function"
  value       = aws_lambda_function.stock_trend_analysis.function_name
}