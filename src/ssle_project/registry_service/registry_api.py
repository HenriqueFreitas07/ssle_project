from flask import Flask, request, jsonify
from datetime import datetime
import os
from dotenv import load_env 
app = Flask(__name__)

registry = {}
load_env()

PORT=os.getenv("PORT")

@app.route('/register', methods=['POST'])
def register():
     data = request.get_json()
     name, url = data.get("name"), data.get("url")
     if not name or not url:
         return jsonify({"error": "Missing name or url"}), 400
     registry[name] = {"url": url, "timestamp": datetime.utcnow().isoformat()}
     return jsonify({"message": f"{name} registered"}), 200
@app.route('/unregister', methods=['DELETE'])
def unregister():
     name = request.get_json().get("name")
     if name in registry:
         del registry[name]
         return jsonify({"message": f"{name} unregistered"}), 200
     return jsonify({"error": "Not found"}), 404

@app.route('/services', methods=['GET'])
def services():
     return jsonify(registry)

@app.route('/services/<name>', methods=['GET'])
def get_service(name):
     service = registry.get(name)
     return jsonify(service) if service else (jsonify({"error": "Not found"}), 404)
if __name__ == '__main__':



 app.run(port=5050)
