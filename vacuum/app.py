from flask import Flask, jsonify, request, redirect
import logging
import os
from micloud import MiCloud
from miio import RoborockVacuum, DeviceException
from flasgger import Swagger

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)

# Configure Swagger
swagger = Swagger(app, template={
    "info": {
        "title": "Xiaomi Vacuum Control API",
        "description": "API to control Xiaomi robot vacuums via Xiaomi Cloud API for discovery and miIO protocol for control. Use /list to get device IDs for specific control.",
        "version": "1.0.0"
    },
    "host": "vacuum.granbacken",
    "basePath": "/",
    "schemes": ["https"]
})

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
        app.logger.error("Missing Xiaomi credentials")
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
                token = device.get("token", "")
                vacuums.append({
                    "ip": ip,
                    "model": model,
                    "device_id": did,
                    "token": token,
                    "device": None if not token else RoborockVacuum(ip=ip, token=token)
                })
                app.logger.info(f"Found vacuum: {ip}, model: {model}, did: {did}")
    except Exception as e:
        app.logger.error(f"Failed to discover vacuums: {e}")
    
    app.logger.info(f"Discovered {len(vacuums)} devices")
    return vacuums

def control_vacuums(action, device_id=None):
    """Control vacuums via miIO protocol, optionally for a specific device ID.
    ---
    description: Internal function to control vacuums (start, stop, pause).
    parameters:
      - name: action
        in: query
        type: string
        enum: [start, stop, pause]
        required: true
        description: The action to perform
      - name: device_id
        in: query
        type: string
        required: false
        description: Optional device ID to control a specific vacuum; if omitted, controls all vacuums
    """
    vacuums = discover_vacuums()
    results = []
    if not vacuums:
        return ["No vacuums found"]
    
    # Filter by device_id if provided
    if device_id:
        target_vacuum = next((v for v in vacuums if v["device_id"] == device_id), None)
        if not target_vacuum:
            return [f"Vacuum with device_id {device_id}: Not found"]
        vacuums = [target_vacuum]
    
    for vac in vacuums:
        if not vac["device"]:
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): No token available")
            continue
        try:
            if action == "start":
                vac["device"].start()
                status = "Started"
            elif action == "stop":
                vac["device"].stop()
                status = "Stopped"
            elif action == "pause":
                vac["device"].pause()
                status = "Paused"
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): {status}")
        except DeviceException as e:
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): Error - {str(e)}")
    
    return results

@app.route('/list')
def list_vacuums():
    """List all Xiaomi vacuums.
    ---
    tags:
      - Vacuums
    responses:
      200:
        description: List of discovered vacuums
        schema:
          type: array
          items:
            type: object
            properties:
              ip:
                type: string
                description: Local IP address of the vacuum
              model:
                type: string
                description: Model of the vacuum (e.g., roborock.vacuum.s5)
              device_id:
                type: string
                description: Unique device ID for cloud control
        examples:
          application/json:
            - ip: "192.168.68.2"
              model: "roborock.vacuum.a15"
              device_id: "506521493"
            - ip: "192.168.68.21"
              model: "roborock.vacuum.s5"
              device_id: "118097498"
    """
    vacuums = discover_vacuums()
    vacuum_info = [
        {"ip": vac["ip"], "model": vac["model"], "device_id": vac["device_id"]}
        for vac in vacuums
    ]
    app.logger.info(f"Returning vacuum list: {vacuum_info}")
    return jsonify(vacuum_info)

@app.route('/start')
def start():
    """Start Xiaomi vacuums.
    ---
    tags:
      - Vacuums
    parameters:
      - name: device_id
        in: query
        type: string
        required: false
        description: Optional device ID to start a specific vacuum (e.g., 506521493); if omitted, starts all vacuums
    responses:
      200:
        description: Status of start action
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum 192.168.68.2 (roborock.vacuum.a15): Started<br>Vacuum 192.168.68.21 (roborock.vacuum.s5): Started"
      404:
        description: Vacuum not found (if device_id is invalid)
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum with device_id invalid: Not found"
    """
    device_id = request.args.get('device_id')
    results = control_vacuums("start", device_id)
    app.logger.info(f"Start results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/stop')
def stop():
    """Stop Xiaomi vacuums.
    ---
    tags:
      - Vacuums
    parameters:
      - name: device_id
        in: query
        type: string
        required: false
        description: Optional device ID to stop a specific vacuum (e.g., 506521493); if omitted, stops all vacuums
    responses:
      200:
        description: Status of stop action
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum 192.168.68.2 (roborock.vacuum.a15): Stopped<br>Vacuum 192.168.68.21 (roborock.vacuum.s5): Stopped"
      404:
        description: Vacuum not found (if device_id is invalid)
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum with device_id invalid: Not found"
    """
    device_id = request.args.get('device_id')
    results = control_vacuums("stop", device_id)
    app.logger.info(f"Stop results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/pause')
def pause():
    """Pause Xiaomi vacuums.
    ---
    tags:
      - Vacuums
    parameters:
      - name: device_id
        in: query
        type: string
        required: false
        description: Optional device ID to pause a specific vacuum (e.g., 118097498); if omitted, pauses all vacuums
    responses:
      200:
        description: Status of pause action
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum 192.168.68.2 (roborock.vacuum.a15): Paused<br>Vacuum 192.168.68.21 (roborock.vacuum.s5): Paused"
      404:
        description: Vacuum not found (if device_id is invalid)
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum with device_id invalid: Not found"
    """
    device_id = request.args.get('device_id')
    results = control_vacuums("pause", device_id)
    app.logger.info(f"Pause results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/docs')
def docs():
    """Swagger UI for API documentation.
    ---
    tags:
      - Documentation
    responses:
      200:
        description: Interactive Swagger UI page
        schema:
          type: string
          description: HTML page for API documentation
    """
    return redirect("/apidocs/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
