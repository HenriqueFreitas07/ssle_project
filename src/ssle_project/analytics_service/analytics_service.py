#!/usr/bin/env python3
from flask import Flask, jsonify, request
import sqlite3
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

# Use shared database from storage service
DB = '/app/data/temp_data.db'

ANALYTICS_SERVICE_PORT= os.getenv("ANALYTICS_SERVICE_PORT",5003)

@app.route('/average', methods=['GET'])
def average_temp():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("SELECT AVG(temperature) FROM temperatures")
     avg = c.fetchone()[0]
     conn.close()
     return jsonify({"average_temperature": round(avg, 2) if avg else None})

@app.route('/min', methods=['GET'])
def min_temp():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("SELECT MIN(temperature), device_id, timestamp FROM temperatures")
     row = c.fetchone()
     conn.close()
     if row and row[0] is not None:
         return jsonify({"min_temperature": round(row[0], 2), "device_id": row[1], "timestamp": row[2]})
     return jsonify({"min_temperature": None})

@app.route('/max', methods=['GET'])
def max_temp():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("SELECT MAX(temperature), device_id, timestamp FROM temperatures")
     row = c.fetchone()
     conn.close()
     if row and row[0] is not None:
         return jsonify({"max_temperature": round(row[0], 2), "device_id": row[1], "timestamp": row[2]})
     return jsonify({"max_temperature": None})

@app.route('/stats', methods=['GET'])
def stats():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("""
         SELECT
             COUNT(*) as count,
             AVG(temperature) as avg,
             MIN(temperature) as min,
             MAX(temperature) as max,
             COUNT(DISTINCT device_id) as device_count
         FROM temperatures
     """)
     row = c.fetchone()
     conn.close()
     if row:
         return jsonify({
             "total_readings": row[0],
             "average_temperature": round(row[1], 2) if row[1] else None,
             "min_temperature": round(row[2], 2) if row[2] else None,
             "max_temperature": round(row[3], 2) if row[3] else None,
             "device_count": row[4]
         })
     return jsonify({"error": "No data available"}), 404

@app.route('/by_device', methods=['GET'])
def by_device():
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute("""
         SELECT
             device_id,
             COUNT(*) as count,
             AVG(temperature) as avg,
             MIN(temperature) as min,
             MAX(temperature) as max,
             MAX(timestamp) as last_reading
         FROM temperatures
         GROUP BY device_id
     """)
     rows = c.fetchall()
     conn.close()
     result = []
     for row in rows:
         result.append({
             "device_id": row[0],
             "reading_count": row[1],
             "average_temperature": round(row[2], 2) if row[2] else None,
             "min_temperature": round(row[3], 2) if row[3] else None,
             "max_temperature": round(row[4], 2) if row[4] else None,
             "last_reading": row[5]
         })
     return jsonify({"devices": result})

@app.route('/recent', methods=['GET'])
def recent():
     limit = request.args.get('limit', 10, type=int)
     conn = sqlite3.connect(DB)
     c = conn.cursor()
     c.execute(f"SELECT device_id, temperature, timestamp FROM temperatures ORDER BY timestamp DESC LIMIT {limit}")
     rows = c.fetchall()
     conn.close()
     result = [{"device_id": r[0], "temperature": r[1], "timestamp": r[2]} for r in rows]
     return jsonify({"recent_readings": result, "count": len(result)})

@app.route('/health', methods=['GET'])
def health():
     return jsonify({"status": "healthy", "service": "analytics-service"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=ANALYTICS_SERVICE_PORT)
