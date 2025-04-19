from flask import Flask, jsonify, request, redirect
import logging
import os
from micloud import MiCloud
from miio import RoborockVacuum, DeviceException
from flasgger import Swagger
import time
import threading
from datetime import datetime, timezone

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

# Store last cleaning finished timestamps
last_cleaning_finished = {}  # {device_id: timestamp}

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

def monitor_cleaning_completion(vacuum):
    """Monitor vacuum status to detect cleaning completion."""
    device_id = vacuum["device_id"]
    device = vacuum["device"]
    try:
        # Poll status every 10 seconds for up to 1 hour
        for _ in range(360):
            status = device.status()
            # Check if vacuum is idle or docked (indicates cleaning stopped)
            if not status.is_on and not status.is_paused:
                last_cleaning_finished[device_id] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                app.logger.info(f"Vacuum {device_id} finished cleaning at {last_cleaning_finished[device_id]}")
                return
            time.sleep(10)
    except DeviceException as e:
        app.logger.error(f"Error monitoring vacuum {device_id}: {e}")

def control_vacuums(action, device_id=None, autostart=False):
    """Control vacuums via miIO protocol, optionally for a specific device ID."""
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

    # Filter by autostart if true (only start vacuums with last cleaning > 48 hours ago or null)
    if action == "start" and autostart:
        filtered_vacuums = []
        for vac in vacuums:
            last_cleaned = last_cleaning_finished.get(vac["device_id"])
            if last_cleaned is None:
                filtered_vacuums.append(vac)
                continue
            try:
                last_cleaned_time = datetime.strptime(last_cleaned, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                time_diff = (datetime.now(timezone.utc) - last_cleaned_time).total_seconds()
                if time_diff > 48 * 3600:  # 48 hours in seconds
                    filtered_vacuums.append(vac)
                else:
                    results.append(f"Vacuum {vac['ip']} ({vac['model']}): Skipped (last cleaned {last_cleaned})")
            except ValueError as e:
                app.logger.error(f"Invalid timestamp for vacuum {vac['device_id']}: {e}")
                filtered_vacuums.append(vac)  # Assume cleaning is old if timestamp is invalid
        vacuums = filtered_vacuums

    for vac in vacuums:
        if not vac["device"]:
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): No token available")
            continue
        try:
            if action == "start":
                vac["device"].start()
                status = "Started"
                # Start monitoring in a separate thread
                threading.Thread(target=monitor_cleaning_completion, args=(vac,), daemon=True).start()
            elif action == "stop":
    #            vac["device"].stop()
                vac["device"].home()
                status = "Stopped and sent to dock"
                last_cleaning_finished[vac["device_id"]] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                app.logger.info(f"Vacuum {vac['device_id']} stopped at {last_cleaning_finished[vac['device_id']]}")
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
              last_cleaning_finished:
                type: string
                format: date-time
                description: Timestamp of when the last cleaning finished (ISO format) or null if not available
        examples:
          application/json:
            - ip: "192.168.68.2"
              model: "roborock.vacuum.a15"
              device_id: "506521493"
              last_cleaning_finished: "2025-04-18T12:00:00Z"
            - ip: "192.168.68.21"
              model: "roborock.vacuum.s5"
              device_id: "118097498"
              last_cleaning_finished: null
    """
    vacuums = discover_vacuums()
    vacuum_info = [
        {
            "ip": vac["ip"],
            "model": vac["model"],
            "device_id": vac["device_id"],
            "last_cleaning_finished": last_cleaning_finished.get(vac["device_id"])
        }
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
      - name: autostart
        in: query
        type: boolean
        required: false
        default: false
        description: If true, only start vacuums whose last cleaning was more than 48 hours ago or never cleaned
    responses:
      200:
        description: Status of start action
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum 192.168.68.2 (roborock.vacuum.a15): Started<br>Vacuum 192.168.68.21 (roborock.vacuum.s5): Skipped (last cleaned 2025-04-18T12:00:00Z)"
      404:
        description: Vacuum not found (if device_id is invalid)
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum with device_id invalid: Not found"
    """
    device_id = request.args.get('device_id')
    autostart = request.args.get('autostart', type=bool, default=False)
    results = control_vacuums("start", device_id, autostart)
    app.logger.info(f"Start results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/stop')
def stop():
    """Stop Xiaomi vacuums and send them to the dock.
    ---
    tags:
      - Vacuums
    parameters:
      - name: device_id
        in: query
        type: string
        required: false
        description: Optional device ID to stop and send a specific vacuum to the dock (e.g., 506521493); if omitted, stops and docks all vacuums
    responses:
      200:
        description: Status of stop and dock action
        schema:
          type: string
        examples:
          text/html: >
            "Vacuum 192.168.68.2 (roborock.vacuum.a15): Stopped and sent to dock<br>Vacuum 192.168.68.21 (roborock.vacuum.s5): Stopped and sent to dock"
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
