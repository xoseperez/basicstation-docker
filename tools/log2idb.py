#!/usr/bin/env python

import os
import datetime
from basicstation import parser
from influxdb import InfluxDBClient

CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "basicstation")
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", 8086)
DB_USER = os.environ.get("DB_USER", "")
DB_PASS = os.environ.get("DB_PASS", "")
DB_NAME = os.environ.get("DB_NAME", "gateways")
DB_MEASUREMENT = os.environ.get("DB_MEASUREMENT", "metrics")
GATEWAY_ID = os.environ.get("GATEWAY_ID", "gateway")

client = InfluxDBClient(host=DB_HOST, port=DB_PORT, username=DB_USER, password=DB_PASS)
client.switch_database(DB_NAME)
runner = parser(CONTAINER_NAME, True)
for value in runner.run():
    print(value)
    type = value.pop('type', None)
    timestamp = value.pop('timestamp', None)
    data = [
        {
            "measurement": DB_MEASUREMENT,
            "tags": {
                "gateway_id": GATEWAY_ID,
                "type": type
            },
            "time": datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).isoformat(),
            "fields": value
        }
    ]    
    client.write_points(data)

