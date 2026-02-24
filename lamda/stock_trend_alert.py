import boto3
import json
import decimal
import os
from datetime import datetime, timedelta

# AWS Clients
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

# DynamoDB Table Name and SNS ARN
TABLE_NAME = os.environ['TABLE_NAME']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def get_recent_stock_data(symbol, minutes=5):
    """ Fetches stock data for the last 'minutes' from DynamoDB using Query instead of Scan """
    table = dynamodb.Table(TABLE_NAME)
    now = datetime.utcnow()
    past_time = now - timedelta(minutes=minutes)

    try:
        response = table.query(
            KeyConditionExpression="symbol = :symbol AND #ts >= :time",
            ExpressionAttributeNames={"#ts": "timestamp"},
            ExpressionAttributeValues={
                ":symbol": symbol,
                ":time": past_time.strftime("%Y-%m-%d %H:%M:%S"),
            },
            ScanIndexForward=True  # Get latest records first
        )
        return sorted(response.get("Items", []), key=lambda x: x["timestamp"])
    
    except Exception as e:
        print(f"Error fetching stock data: {e}")
        return []

def calculate_moving_average(data, period):
    """ Calculate moving average for given period, avoid None issues """
    if len(data) < period:
        return decimal.Decimal("0") 
    return sum(decimal.Decimal(d["price"]) for d in data[-period:]) / period

def lambda_handler(event, context):
    symbols = ["AAPL"]

    for symbol in symbols:
        stock_data = get_recent_stock_data(symbol)
        print(f"Fetched {len(stock_data)} records for {symbol}")

        if len(stock_data) < 20:
            print(f"Not enough data for {symbol}. Need 20, got {len(stock_data)}. Skipping.")
            continue

        sma_5 = calculate_moving_average(stock_data, 5)
        sma_20 = calculate_moving_average(stock_data, 20)
        sma_5_prev = calculate_moving_average(stock_data[:-1], 5)
        sma_20_prev = calculate_moving_average(stock_data[:-1], 20)
        
        print(f"SMA-5: {sma_5}, SMA-20: {sma_20}")

        if None not in (sma_5, sma_20, sma_5_prev, sma_20_prev):
            message = None

            if sma_5_prev < sma_20_prev and sma_5 > sma_20:
                message = f"{symbol} is in an **Uptrend**! Consider a buy opportunity."
            elif sma_5_prev > sma_20_prev and sma_5 < sma_20:
                message = f"{symbol} is in a **Downtrend**! Consider selling."

            if message:
                print(f"Sending alert: {message}")
                try:
                    sns.publish(TopicArn=SNS_TOPIC_ARN, Message=message, Subject=f"Stock Alert: {symbol}")
                    print("SNS alert sent successfully")
                except Exception as e:
                    print(f"Failed to publish SNS message: {e}")
            else:
                print(f"No trend crossover detected for {symbol}")

    return {"statusCode": 200, "body": json.dumps("Trend analysis complete")}
