#!/usr/bin/env python

import os
import time
from basicstation import parser
import flask
from flask import jsonify
import threading

CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "basicstation")
BUCKET_SIZE = os.environ.get("BUCET_SIZE", 60)
BUCKET_COUNT = os.environ.get("BUCKET_COUNT", 15)

buckets = {}
totals = {
    'rx': 0,
    'tx': 0
}
previous_bucket = 0

def manage_buckets(timestamp):
    new_bucket = timestamp / BUCKET_SIZE
    if new_bucket != previous_bucket:
        previous_bucket = new_bucket
        buckets = {key: value for key, value in buckets.items() if key > new_bucket - BUCKET_COUNT}
        buckets[new_bucket] = {
            'rx': 0,
            'tx': 0
        }
    return new_bucket


app = flask.Flask(__name__)
app.config["DEBUG"] = True

@app.route('/api/metrics', methods=['GET'])
def api_metrics():
    manage_buckets(time.time())
    offset = list(buckets.keys())[0]
    return jsonify(dict({
        'totals': totals,
        'buckets': { (key - offset): value for key, value in buckets.items() },
        'bucket_size': BUCKET_SIZE,
        'bucket_count': BUCKET_COUNT
    }))

threading.Thread(target=lambda: app.run(host="0.0.0.0", port=8888, debug=True, use_reloader=False)).start()

runner = parser(CONTAINER_NAME, True)
for value in runner.run():
    #print("Received: {}".format(value))
    bucket = manage_buckets(int(value['timestamp']))
    totals[value['type']] = totals[value['type']] + 1
    buckets[bucket][value['type']] = buckets[bucket][value['type']] + 1
