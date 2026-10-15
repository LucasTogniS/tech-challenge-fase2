"""Cria a tabela do analytics-service no DynamoDB Local (idempotente)."""
import os
import time

import boto3
from botocore.exceptions import ClientError, EndpointConnectionError

TABLE = os.environ["AWS_DYNAMODB_TABLE"]
client = boto3.client("dynamodb")

for attempt in range(30):
    try:
        client.create_table(
            TableName=TABLE,
            AttributeDefinitions=[{"AttributeName": "event_id", "AttributeType": "S"}],
            KeySchema=[{"AttributeName": "event_id", "KeyType": "HASH"}],
            BillingMode="PAY_PER_REQUEST",
        )
        print(f"Tabela {TABLE} criada.")
        break
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceInUseException":
            print(f"Tabela {TABLE} já existe.")
            break
        raise
    except EndpointConnectionError:
        print("DynamoDB Local ainda não respondeu, tentando de novo...")
        time.sleep(2)
else:
    raise SystemExit("DynamoDB Local não respondeu a tempo.")
