#!/usr/bin/env python3
from flask import Flask, request, jsonify
import requests
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

SERVICE_NAME = "ingestion-service"
PORT = os.getenv("SERVICE_PORT", 5001)
STORAGE_SERVICE_URL = os.getenv("STORAGE_SERVICE_URL")
REGISTRY_SERVICE_URL = os.getenv("REGISTRY_SERVICE_URL")

@app.route('/ingest', methods=['POST'])
def ingest():
     data = request.get_json()
     print(f"[INGESTION] Received: {data}")
     print(f"[INGESTION] Forwarding to: {STORAGE_SERVICE_URL}/store")
     # Forward to storage
     try:
         res = requests.post(f"{STORAGE_SERVICE_URL}/store", json=data, timeout=5)
         print(f"[INGESTION] Storage response: {res.status_code} - {res.text}")
         if res.status_code == 200:
             return jsonify({"stored": True, "message": "Data successfully stored"}), 200
         else:
             return jsonify({"stored": False, "error": res.text}), res.status_code
     except requests.exceptions.ConnectionError as e:
         print(f"[INGESTION] Connection error to storage service: {e}")
         return jsonify({"error": "Cannot connect to storage service", "details": str(e)}), 503
     except requests.exceptions.Timeout as e:
         print(f"[INGESTION] Timeout connecting to storage service: {e}")
         return jsonify({"error": "Storage service timeout", "details": str(e)}), 504
     except Exception as e:
         print(f"[INGESTION] Unexpected error: {e}")
         return jsonify({"error": "Internal server error", "details": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
     return jsonify({"status": "healthy", "service": SERVICE_NAME}), 200

def register():
     try:
          requests.post(f"{REGISTRY_SERVICE_URL}/register", json={
          "name": SERVICE_NAME,
          "url": f"http://ingestion-service:{PORT}"
          })
     except Exception as e:
          print(f"Could not register with registry service: {e}")

if __name__ == '__main__':
     register()
     app.run(host='0.0.0.0', port=PORT)
