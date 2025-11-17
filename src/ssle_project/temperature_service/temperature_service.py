#!/usr/bin/env python3
import requests
import time
import random
import os
from dotenv import load_dotenv
import uuid

load_dotenv()

DEVICE_ID = "sensor-"+str(uuid.uuid4())
INGESTION_SERVICE_URL = os.getenv("INGESTION_SERVICE_URL")

def send_temp():
     while True:
         temp = round(random.uniform(20.0, 30.0), 2)
         payload = {"device_id": DEVICE_ID, "temperature": temp}
         try:
             requests.post(f'{INGESTION_SERVICE_URL}/ingest', json=payload)
             print("Sent:", payload)
         except Exception as e:
             print("Error:", e)
         time.sleep(5)

if __name__ == '__main__':
    send_temp()
