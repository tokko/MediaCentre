from flask import Flask, jsonify, request
import json
import logging
import os
from micloud import MiCloud

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)

def read_secret(secret_name):
    """Read Docker secret."""
    try:
        with open(f"/run/secrets/{secret_name}", "r") as f:
            return f.read().strip()
    except Exception as e:
        app.logger.error(f"Failed to read secret {secret_name}: {e}")
        return None

XIAOMI_USERNAME = read_secret("xiaomi_username")
XIAOMI_PASSWORD = read_secret("xiaomi_password")

def get_cloud_client():
    """Initialize Xiaomi Cloud client."""
    if not XIAOMI_USERNAME or not XIAOMI_PASSWORD:
        app.logger.error("Missing credentials")
        return None
    try:
        cloud = MiCloud(XIAOMI_USERNAME, XIAOMI_PASSWORD)
        cloud.login()
        return cloud
    except Exception as e:
        app.logger.error(f"Cloud login failed: {e}")
        return None

def discover_vacuums():
    """Discover vacuums via Xiaomi Cloud."""
    vacuums = []
    cloud = get_cloud_client()
    if not cloud:
        app.logger.error("No cloud client available")
        return vacuums
    
    try:
        devices = cloud.get_devices()
        for device in devices:
            if "roborock.vacuum" in device["model"]:
                ip = device.get("localip", "unknown")
                did = device["did"]
                model = device["model"]
                vacuums.append({
                    "ip": ip,
                    "model": model,
                    "device_id": did,
                    "device": None  # Cloud control, no local miIO device
                })
                app.logger.info(f"Found vacuum: {ip}, model: {model}, did: {did}")
    except Exception as e:
        app.logger.error(f"Failed to discover vacuums: {e}")
    
    app.logger.info(f"Discovered {len(vacuums)} devices")
    return vacuums

def control_vacuums(action):
    """Control all vacuums via Xiaomi Cloud."""
    vacuums = discover_vacuums()
    results = []
    cloud = get_cloud_client()
    if not cloud:
        return ["Cloud connection failed"]
    
    if not vacuums:
        return ["No vacuums found"]
    
    for vac in vacuums:
        did = vac["device_id"]
        try:
            if action == "start":
                cloud.execute_action(did, "app_start", [])
                status = "Started"
            elif action == "stop":
                cloud.execute_action(did, "app_stop", [])
                status = "Stopped"
            elif action == "pause":
                cloud.execute_action(did, "app_pause", [])
                status = "Paused"
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): {status}")
        except Exception as e:
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): Error - {str(e)}")
    
    return results

@app.route('/list')
def list_vacuums():
    """Return JSON with info about all vacuums."""
    vacuums = discover_vacuums()
    vacuum_info = [
        {"ip": vac["ip"], "model": vac["model"], "device_id": vac["device_id"]}
        for vac in vacuums
    ]
    app.logger.info(f"Returning vacuum list: {vacuum_info}")
    return jsonify(vacuum_info)

@app.route('/start')
def start():
    """Start all Xiaomi vacuums."""
    results = control_vacuums("start")
    app.logger.info(f"Start results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/stop')
def stop():
    """Stop all Xiaomi vacuums."""
    results = control_vacuums("stop")
    app.logger.info(f"Stop results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/pause')
def pause():
    """Pause all Xiaomi vacuums."""
    results = control_vacuums("pause")
    app.logger.info(f"Pause results: {results}")
    return "<br>".join(results) or "No vacuums found."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
