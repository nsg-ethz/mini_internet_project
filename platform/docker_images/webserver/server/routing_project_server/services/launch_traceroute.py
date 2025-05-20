import ipaddress
import json
import uuid
import threading
from time import sleep
from datetime import datetime
from flask import Blueprint, request, jsonify, current_app
import subprocess
import jc

from .login import csrf

traceroute_bp = Blueprint("traceroute", __name__)

# In-memory store for traceroute jobs (can be replaced by Redis/DB later)
TRACEROUTE_RESULTS = {}

def cleanup_loop(config=None, **kwargs):
    from datetime import datetime
    expire_after = config.get("TRACEROUTE_CLEANUP_EXPIRE_AFTER", 600) if config else 600
    now = datetime.now()
    expired = []
    for job_id, result in list(TRACEROUTE_RESULTS.items()):
        ts = result.get("timestamp")
        if not ts:
            continue
        try:
            created = datetime.fromisoformat(ts)
            if (now - created).total_seconds() > expire_after:
                expired.append(job_id)
        except ValueError:
            continue
    for job_id in expired:
        del TRACEROUTE_RESULTS[job_id]
        print(f"[Traceroute Cleanup] Removed expired job: {job_id}")

# Traceroute execution
def run_traceroute_job(job_id, container, target_ip, logger):
    logger.info(f"[Traceroute] Job {job_id} started: {container} ? {target_ip}")
    timestamp = datetime.now().isoformat(timespec="seconds")

    try:
        cmd = ["docker", "exec", container, "sh", "-c", f"traceroute -w 1 -q 1 -m 10 {target_ip} 2>&1"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        output = result.stdout

        try:
            parsed = jc.parse("traceroute", output)
        except Exception as e:
            logger.warning(f"[Traceroute] JC parsing failed: {e}")
            parsed = []

        TRACEROUTE_RESULTS[job_id] = {
            "timestamp": timestamp,
            "container": container,
            "target_ip": target_ip,
            "raw_output": output,
            "routes": parsed
        }

    except subprocess.TimeoutExpired:
        TRACEROUTE_RESULTS[job_id] = {
            "error": f"Traceroute to {target_ip} timed out after 60s"
        }
    except Exception as e:
        logger.exception("[Traceroute ERROR]")
        TRACEROUTE_RESULTS[job_id] = {
            "error": str(e)
        }

# Launch traceroute request
@csrf.exempt
@traceroute_bp.route("/launch-traceroute", methods=["POST"])
def launch_traceroute():
    logger = current_app.logger
    data = request.get_json(silent=True)
    if not data or not all(data.get(k) for k in ["container", "target_ip"]):
        return jsonify({"error": "Missing required fields: container, target_ip"}), 400

    container = data["container"]
    target_ip = data["target_ip"]

    if container not in current_app.config.get("ALLOWED_CONTAINERS", set()):
        logger.warning(f"[Traceroute] Access denied for container '{container}'")
        return jsonify({"error": f"Container '{container}' is not allowed."}), 403

    try:
        ipaddress.ip_address(target_ip)
    except ValueError:
        return jsonify({"error": "Invalid IP address"}), 400

    # Start job
    job_id = str(uuid.uuid4())
    thread = threading.Thread(
        target=run_traceroute_job,
        args=(job_id, container, target_ip, logger),
        daemon=True
    )
    thread.start()

    logger.info(f"[Traceroute] Launched job {job_id} for {target_ip}")
    return jsonify({"status": "started", "job_id": job_id})

# Poll for traceroute result
@traceroute_bp.route("/get-traceroute-result", methods=["GET"])
def get_traceroute_result():
    job_id = request.args.get("job_id")
    if not job_id:
        return jsonify({"error": "Missing job_id"}), 400

    result = TRACEROUTE_RESULTS.get(job_id)
    if result is None:
        return jsonify({"status": "pending"})
    return jsonify(result)
