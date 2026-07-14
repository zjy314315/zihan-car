"""
Flask blueprint that serves the face recognition page and proxies requests
to a remote face service (the car's face service). Put this file under your
zihan-car Flask app and register the blueprint.

Usage:
  - Set environment variable CAR_FACE_SERVICE_URL, e.g. http://10.168.202.242:5000
  - Register the blueprint in your app factory:
      from backend_proxy import face_bp
      app.register_blueprint(face_bp, url_prefix='/api/face')

The blueprint serves:
  GET  /api/face/page      -> returns static page (face_recognition_page.html)
  POST /api/face/register  -> forwarded to CAR_FACE_SERVICE_URL/register
  POST /api/face/start     -> forwarded to CAR_FACE_SERVICE_URL/start
  POST /api/face/stop      -> forwarded to CAR_FACE_SERVICE_URL/stop
  GET  /api/face/status    -> forwarded to CAR_FACE_SERVICE_URL/status
  GET  /api/face/result    -> forwarded to CAR_FACE_SERVICE_URL/result

This allows your web UI to call /api/face/* and the Flask app will proxy.
"""
from flask import Blueprint, current_app, send_from_directory, request, jsonify
import os
import requests

face_bp = Blueprint('face_bp', __name__, static_folder=None)

CAR_FACE_SERVICE_URL = os.environ.get('CAR_FACE_SERVICE_URL', 'http://10.168.202.242:5000')

@face_bp.route('/page')
def page():
    # Serve the face recognition page from a local static folder if present,
    # otherwise serve it from the current module directory.
    root = os.path.join(os.path.dirname(__file__), 'static')
    if not os.path.isdir(root):
        root = os.path.dirname(__file__)
    return send_from_directory(root, 'face_recognition_page.html')


def _proxy(path, method='GET'):
    url = CAR_FACE_SERVICE_URL.rstrip('/') + '/' + path.lstrip('/')
    try:
        if method == 'GET':
            r = requests.get(url, timeout=5)
        else:
            r = requests.request(method, url, json=request.get_json(silent=True), timeout=10)
        return (r.content, r.status_code, r.headers.items())
    except Exception as e:
        return jsonify({'status':'error','message':f'proxy_error:{e}'}), 502

@face_bp.route('/register', methods=['POST'])
def register():
    return _proxy('register', method='POST')

@face_bp.route('/start', methods=['POST'])
def start():
    return _proxy('start', method='POST')

@face_bp.route('/stop', methods=['POST'])
def stop():
    return _proxy('stop', method='POST')

@face_bp.route('/status', methods=['GET'])
def status():
    return _proxy('status', method='GET')

@face_bp.route('/result', methods=['GET'])
def result():
    return _proxy('result', method='GET')
