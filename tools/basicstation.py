#!/usr/bin/env python

import re
import time
import datetime
import docker

class parser():

    container = None
    only_new = True

    def __init__(self, container_name, only_new=True):

        self.line_dict = {
            'timestamp': { 'pattern': re.compile(r'^(?P<value>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3})'), 'process': self.timestamp_parser }, 
            'frequency': { 'pattern': re.compile(r' (?P<value>[0-9\.]+)MHz'), 'process': float }, 
            'datarate': { 'pattern': re.compile(r' DR(?P<value>[0-5])'), 'process': int }, 
            'snr': { 'pattern': re.compile(r' snr=(?P<value>[0-9\.]+)'), 'process': float }, 
            'rssi': { 'pattern': re.compile(r' rssi=(?P<value>[\-0-9]+)'), 'process': int }, 
            'devaddr': { 'pattern': re.compile(r' DevAddr=(?P<value>[0-9A-F]+)'), 'process': None }, 
        }
        self.is_rx = re.compile(r'\[S2E:VERB\] RX ')
        self.is_tx = re.compile(r'\[S2E:INFO\] TX ::1 ')
        
        self.only_new = only_new
        self.min_ts = time.time()

        client = docker.from_env()
        try:
            self.container = client.containers.get(container_name)
        except docker.errors.NotFound:
            print("Container %s NOT found!" % container_name)


    def timestamp_parser(self, value):
        ts, ms = value.split(".")
        value = datetime.datetime.strptime(ts+"+0000", "%Y-%m-%d %H:%M:%S%z").timestamp()
        value = value + int(ms) / 1000
        return value

    def parse_line(self, type, line):
        output = {}
        output['type'] = type
        for key, p in self.line_dict.items():
            match = p['pattern'].search(line)
            if match:
                value = match.group('value')
                if p['process']:
                    value = p['process'](value)
                output[key] = value
        return output

    def run(self):
        
        if self.container:

            # Log stream
            for line in self.container.logs(stream=True):
                
                message = None
                line = line.strip().decode("utf-8") 
                
                if (self.is_rx.search(line)):
                    message = self.parse_line('rx', line)
                
                if (self.is_tx.search(line)):
                    message = self.parse_line('tx', line)

                if message:
                    if (not self.only_new) or (message['timestamp'] > self.min_ts):
                        yield message


if __name__ == '__main__':
    runner = parser("basicstation", False)
    for value in runner.run():
        print(value)
