#!/usr/bin/env python

import os
import sys
from basicstation import parser
import paho.mqtt.client as mqtt

CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "basicstation")
MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = os.environ.get("MQTT_PORT", 1883)
MQTT_USER = os.environ.get("MQTT_USER", "")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
MQTT_TOPIC = os.environ.get("MQTT_TOPIC", "gateway/metrics")
GATEWAY_ID = os.environ.get("GATEWAY_ID", "gateway")
MEASUREMENT = os.environ.get("MEASUREMENT", "metrics")
MQTT_DATA_FORMAT = os.environ.get("MQTT_DATA_FORMAT", "json")

def on_connect(client, userdata, flags, rc):
    client.subscribe(MQTT_TOPIC)

client = mqtt.Client()
client.on_connect = on_connect
if MQTT_USER:
    client.username_pw_set(MQTT_USER, password=MQTT_PASS)
client.connect(MQTT_HOST, MQTT_PORT, 60)

runner = parser(CONTAINER_NAME, True)
for value in runner.run():
    #print("Received: {}".format(value))
   
    data = None
    if MQTT_DATA_FORMAT == "json":
        data = str(value)
    if MQTT_DATA_FORMAT == "influx":
        tags = {}
        tags['gateway_id'] = GATEWAY_ID
        tags['type'] = value.pop('type', None)
        timestamp = value.pop('timestamp', None)
        data = "{},{} {} {}".format(
            MEASUREMENT,
            ",".join([str(key) + "=" + str(value) for key, value in tags.items()]),
            ",".join([str(key) + "=" + str(value) for key, value in value.items()]),
            int(timestamp * 1e6)
        )

    if data:    
        client.publish(MQTT_TOPIC, data, qos=0, retain=False)
    else:
        print("ERROR: Unkown data format")
        sys.exit()
    
    client.loop()
