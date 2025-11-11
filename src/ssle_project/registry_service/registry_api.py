#!/usr/bin/env python3
from flask import Flask, request, jsonify
from datetime import datetime
import os
import requests
import threading
import time
from dotenv import load_dotenv
app = Flask(__name__)

# Registry now supports multiple instances per service
# Structure: {service_name: [{"url": url, "timestamp": iso_string, "healthy": bool, "instance_id": id}, ...]}
registry = {}
load_balancer_index = {}  # Tracks current index for round-robin load balancing
load_dotenv()

REGISTRY_SERVICE_PORT=os.getenv("REGISTRY_SERVICE_PORT")

@app.route('/register', methods=['POST'])
def register():
     data = request.get_json()
     name, url = data.get("name"), data.get("url")
     instance_id = data.get("instance_id", f"{name}-{len(registry.get(name, []))}")
     if not name or not url:
         return jsonify({"error": "Missing name or url"}), 400

     # Initialize service list if not exists
     if name not in registry:
         registry[name] = []
         load_balancer_index[name] = 0

     # Check if instance already registered (update instead of duplicate)
     existing = next((i for i, inst in enumerate(registry[name]) if inst["url"] == url), None)
     if existing is not None:
         registry[name][existing]["timestamp"] = datetime.utcnow().isoformat()
         registry[name][existing]["healthy"] = True
         return jsonify({"message": f"{name} instance updated", "instance_id": registry[name][existing]["instance_id"]}), 200

     # Add new instance
     registry[name].append({
         "url": url,
         "timestamp": datetime.utcnow().isoformat(),
         "healthy": True,
         "instance_id": instance_id
     })
     return jsonify({"message": f"{name} registered", "instance_id": instance_id}), 200

@app.route('/unregister', methods=['DELETE'])
def unregister():
     data = request.get_json()
     name = data.get("name")
     url = data.get("url")  # Optional: unregister specific instance
     if name not in registry:
         return jsonify({"error": "Service not found"}), 404

     if url:
         # Remove specific instance
         registry[name] = [inst for inst in registry[name] if inst["url"] != url]
         if not registry[name]:
             del registry[name]
             del load_balancer_index[name]
         return jsonify({"message": f"{name} instance unregistered"}), 200
     else:
         # Remove all instances
         del registry[name]
         if name in load_balancer_index:
             del load_balancer_index[name]
         return jsonify({"message": f"{name} unregistered"}), 200

@app.route('/services', methods=['GET'])
def services():
     return jsonify(registry)

@app.route('/services/<name>', methods=['GET'])
def get_service(name):
     """Get a healthy service instance using round-robin load balancing"""
     if name not in registry:
         return jsonify({"error": "Service not found"}), 404

     instances = registry[name]
     healthy_instances = [inst for inst in instances if inst["healthy"]]

     if not healthy_instances:
         return jsonify({"error": "No healthy instances available"}), 503

     # Round-robin load balancing
     index = load_balancer_index[name] % len(healthy_instances)
     selected = healthy_instances[index]
     load_balancer_index[name] = (index + 1) % len(healthy_instances)

     return jsonify(selected), 200

@app.route('/health', methods=['GET'])
def health():
     return jsonify({"status": "healthy", "service": "registry-service"}), 200

def check_service_health(url):
     """Check if a service instance is healthy by calling its /health endpoint"""
     try:
         response = requests.get(f"{url}/health", timeout=5)
         return response.status_code == 200
     except Exception:
         return False

def health_check_loop():
     """Periodically check health of all registered services"""
     while True:
         time.sleep(30)  # Check every 30 seconds
         for service_name, instances in list(registry.items()):
             for instance in instances:
                 is_healthy = check_service_health(instance["url"])
                 instance["healthy"] = is_healthy
                 if not is_healthy:
                     print(f"Service {service_name} instance {instance['instance_id']} at {instance['url']} is unhealthy")

def start_health_check_thread():
     """Start background thread for health checking"""
     thread = threading.Thread(target=health_check_loop, daemon=True)
     thread.start()
     print("Health check thread started")

if __name__ == '__main__':
    start_health_check_thread()
    app.run(host='0.0.0.0', port=REGISTRY_SERVICE_PORT)
