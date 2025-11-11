#!/usr/bin/env python3
from flask import Flask, request, jsonify
import sqlite3
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

# Create data directory if it doesn't exist
os.makedirs('/app/data', exist_ok=True)
DB = '/app/data/temp_data.db'

STORAGE_SERVICE_PORT=os.getenv("STORAGE_SERVICE_PORT",5002)

def init_db():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute('''
     CREATE TABLE IF NOT EXISTS temperatures (
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     device_id TEXT,
     temperature REAL,
     timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
     )
     ''')
     conn.commit()
     conn.close()

@app.route('/store', methods=['POST'])
def store():
     data = request.get_json()
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("INSERT INTO temperatures (device_id, temperature) VALUES (?, ?)",
     (data["device_id"], data["temperature"]))
     conn.commit()
     conn.close()
     return jsonify({"status": "stored"}), 200

@app.route('/health', methods=['GET'])
def health():
     return jsonify({"status": "healthy", "service": "storage-service"}), 200

@app.route('/query', methods=['GET'])
def query_all():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("SELECT * FROM temperatures ORDER BY timestamp DESC LIMIT 100")
     rows = c.fetchall()
     conn.close()
     result = [{"id": r[0], "device_id": r[1], "temperature": r[2], "timestamp": r[3]} for r in rows]
     return jsonify({"data": result}), 200

@app.route('/count', methods=['GET'])
def count():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("SELECT COUNT(*) FROM temperatures")
     count = c.fetchone()[0]
     conn.close()
     return jsonify({"count": count}), 200

if __name__ == '__main__':
     init_db()
     app.run(host='0.0.0.0', port=STORAGE_SERVICE_PORT)
