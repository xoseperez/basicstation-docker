#!/usr/bin/env python

import os
from basicstation import parser

CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "basicstation")
BUCKET_SIZE = os.environ.get("BUCET_SIZE", 60)
BUCKET_COUNT = os.environ.get("BUCKET_COUNT", 15)

buckets = {}
totals = {
    'rx': 0,
    'tx': 0
}
previous_bucket = 0

runner = parser(CONTAINER_NAME, True)
for value in runner.run():
    
    new_bucket = int(value['timestamp'] / BUCKET_SIZE)
    if new_bucket != previous_bucket:
        previous_bucket = new_bucket
        buckets = {key: value for key, value in buckets.items() if key > new_bucket - BUCKET_COUNT}
        buckets[new_bucket] = {
            'rx': 0,
            'tx': 0
        }
    totals[value['type']] = totals[value['type']] + 1
    buckets[new_bucket][value['type']] = buckets[new_bucket][value['type']] + 1
    
    offset = list(buckets.keys())[0]
    print(dict({
        'totals': totals,
        'buckets': { (key - offset): value for key, value in buckets.items() },
        'bucket_size': BUCKET_SIZE,
        'bucket_count': BUCKET_COUNT
    }))
