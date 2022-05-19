#!/usr/bin/env python

import re
import time
import datetime
import docker

class parser():

    container = None
    only_new = True
    devaddr = None

    def __init__(self, container_name, only_new=True):

        self.line_dict = {
            'frequency': { 'pattern': re.compile(r'"freq":(?P<value>[0-9\.]+)'), 'process': float }, 
            'datarate': { 'pattern': re.compile(r'"datr":"(?P<value>SF\d+BW\d+)"'), 'process': None }, 
            'snr': { 'pattern': re.compile(r'"lsnr":(?P<value>[0-9\.]+)'), 'process': float }, 
            'rssi': { 'pattern': re.compile(r'"rssi":(?P<value>[\-0-9]+)'), 'process': int },
            'size': { 'pattern': re.compile(r'"size":(?P<value>[0-9\.]+)'), 'process': int }, 
            #'data': { 'pattern': re.compile(r'"data":"(?P<value>[^"]+)"'), 'process': None }, 
        }
        self.is_rx = re.compile(r'JSON up: {"rxpk"')
        self.is_tx = re.compile(r'JSON down: {"txpk"')
        self.is_devaddr = re.compile(r'Received pkt from mote: (?P<value>[0-9A-F]+)')
        
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
        output['timestamp'] = time.time()
        output['devaddr'] = self.devaddr
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

                # Cache last DevAddr
                match = self.is_devaddr.search(line)
                if match:
                    self.devaddr = match.group('value')
                
                if (self.is_rx.search(line)):
                    message = self.parse_line('rx', line)
                
                if (self.is_tx.search(line)):
                    message = self.parse_line('tx', line)

                if message:
                    if (not self.only_new) or (message['timestamp'] > self.min_ts):
                        yield message

if __name__ == '__main__':
    runner = parser("udp-packet-forwarder", True)
    for value in runner.run():
        print(value)
