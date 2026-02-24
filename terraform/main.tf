#This is for creating a kinesis data stream
resource "aws_kinesis_stream" "stock_market_stream" {
  name = var.kinesis_stream_name

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Project = "stock-market-pipeline"
  }
}

#this is for creating buckets for storing raw data and athena query results data
resource "aws_s3_bucket" "raw_stock_data" {
  bucket = var.s3_bucket_name

  tags = {
    Project = "stock-market-pipeline"
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket = var.athena_bucket_name

  tags = {
    Project = "stock-market-pipeline"
  }
}

/*
  This DynamoDB table stores processed stock data.
  Partition key: symbol
  Sort key: timestamp
  Streams enabled for SNS trend alerts
*/

resource "aws_dynamodb_table" "stock_market_data" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "symbol"
  range_key    = "timestamp"

  attribute {
    name = "symbol"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  tags = {
    Project = "stock-market-pipeline"
  }
}

# IAM Role for ProcessStockData Lambda
# Allows Lambda to read from Kinesis, write to DynamoDB, S3, and send SNS alerts
resource "aws_iam_role" "lambda_kinesis_role" {
  name = "stock-data-manage-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Project = "stock-market-pipeline"
  }
}

# Attach policies to ProcessStockData Lambda role
resource "aws_iam_role_policy_attachment" "lambda_kinesis_access" {
  role       = aws_iam_role.lambda_kinesis_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_kinesis_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_kinesis_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_kinesis_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Role for StockTrendAnalysis Lambda
# Allows Lambda to read from DynamoDB and publish to SNS
resource "aws_iam_role" "stock_trend_role" {
  name = "stock-trend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Project = "stock-market-pipeline"
  }
}

# Attach policies to StockTrendAnalysis Lambda role
resource "aws_iam_role_policy_attachment" "trend_dynamodb_access" {
  role       = aws_iam_role.stock_trend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "trend_sns_access" {
  role       = aws_iam_role.stock_trend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_iam_role_policy_attachment" "trend_basic_execution" {
  role       = aws_iam_role.stock_trend_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Topic for stock trend alerts
resource "aws_sns_topic" "stock_alerts" {
  name = var.sns_topic_name

  tags = {
    Project = "stock-market-pipeline"
  }
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "stock_alerts_email" {
  topic_arn = aws_sns_topic.stock_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda_function - Processes Kinesis records
# Reads stock data from Kinesis, stores processed data to DynamoDB and raw data to S3
resource "aws_lambda_function" "process_stock_data" {
  function_name = "ProcessStockData"
  role          = aws_iam_role.lambda_kinesis_role.arn
  runtime       = "python3.13"
  handler       = "lambda_function.lambda_handler"
  filename      = "lambda_function.zip"

  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      DYNAMO_TABLE = var.dynamodb_table_name
      S3_BUCKET    = var.s3_bucket_name
    }
  }

  tags = {
    Project = "stock-market-pipeline"
  }
}

# Kinesis trigger for ProcessStockData Lambda
# Triggers Lambda every time 2 records accumulate in Kinesis stream
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.stock_market_stream.arn
  function_name     = aws_lambda_function.process_stock_data.arn
  starting_position = "LATEST"
  batch_size        = 2
}

# stock_trend_alert - Analyzes stock trends using SMA-5 and SMA-20
# Triggers from DynamoDB Streams and sends SNS alerts on trend crossovers
resource "aws_lambda_function" "stock_trend_analysis" {
  function_name = "StockTrendAnalysis"
  role          = aws_iam_role.stock_trend_role.arn
  runtime       = "python3.13"
  handler       = "stock_trend_alert.lambda_handler"
  filename      = "stock_trend_alert.zip"

  source_code_hash = filebase64sha256("stock_trend_alert.zip")

  environment {
    variables = {
      TABLE_NAME    = var.dynamodb_table_name
      SNS_TOPIC_ARN = aws_sns_topic.stock_alerts.arn
    }
  }

  tags = {
    Project = "stock-market-pipeline"
  }
}

# DynamoDB Streams trigger for StockTrendAnalysis Lambda
# Triggers Lambda every time a new record is written to DynamoDB
resource "aws_lambda_event_source_mapping" "dynamodb_trigger" {
  event_source_arn  = aws_dynamodb_table.stock_market_data.stream_arn
  function_name     = aws_lambda_function.stock_trend_analysis.arn
  starting_position = "LATEST"
  batch_size        = 2
}


# Glue Database - acts as a catalog for Athena to query S3 data
resource "aws_glue_catalog_database" "stock_database" {
  name = "stock-data-db"
}

# Glue Table - defines the schema of raw stock data stored in S3
# Athena uses this schema to query JSON files in S3
resource "aws_glue_catalog_table" "stock_table" {
  name          = "stock-glue-table"
  database_name = aws_glue_catalog_database.stock_database.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/raw-data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "symbol"
      type = "string"
    }

    columns {
      name = "timestamp"
      type = "string"
    }

    columns {
      name = "open"
      type = "double"
    }

    columns {
      name = "high"
      type = "double"
    }

    columns {
      name = "low"
      type = "double"
    }

    columns {
      name = "price"
      type = "double"
    }

    columns {
      name = "previous_close"
      type = "double"
    }

    columns {
      name = "change"
      type = "double"
    }

    columns {
      name = "change_percent"
      type = "double"
    }

    columns {
      name = "volume"
      type = "bigint"
    }

    columns {
      name = "moving_average"
      type = "double"
    }

    columns {
      name = "anomaly"
      type = "string"
    }
  }
}