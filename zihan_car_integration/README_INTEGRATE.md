Integration steps - add face recognition page to your zihan-car project

Overview
--------
This package contains a static page and a Flask blueprint example to integrate the
car-side face recognition service into your zihan-car project. There are two
options:

A) Proxy mode (recommended): Your zihan-car backend proxies requests to the
   car's face service. The page calls your backend at `/api/face/*`.

B) Direct mode: The page calls the car's face service directly (set PROXY_BASE to
   the car address, e.g. http://10.168.202.242:5000). Use this only if CORS
   / network allows.

Files
-----
- face_recognition_page.html  -> frontend page (copy to your project's static folder)
- backend_proxy.py            -> Flask blueprint example to proxy endpoints

Quick steps (proxy mode)
------------------------
1. Copy files
   - Copy `face_recognition_page.html` into your zihan-car project's static folder,
     e.g. `E:\project\zihan-car\static\face_recognition_page.html`.
   - Copy `backend_proxy.py` into your app package, e.g.
     `E:\project\zihan-car\your_app\backend_proxy.py`.

2. Install dependency for proxying (on your zihan-car environment):

```bash
pip install requests
```

3. Set CAR_FACE_SERVICE_URL environment variable to your car's face service URL,
   for example on the car deployment machine or the server that runs zihan-car:

Linux / macOS:
```bash
export CAR_FACE_SERVICE_URL=http://10.168.202.242:5000
```
Windows (PowerShell):
```powershell
$env:CAR_FACE_SERVICE_URL = 'http://10.168.202.242:5000'
```

4. Register the blueprint in your Flask app factory or main app file:

```python
from your_app.backend_proxy import face_bp
app.register_blueprint(face_bp, url_prefix='/api/face')
```

5. Open the UI
   - Browse to `http://<your-zihan-car-host>/static/face_recognition_page.html` (or
     if you serve the page via the blueprint: `http://<your-zihan-car-host>/api/face/page`).

Direct mode (no proxy)
----------------------
- Edit `face_recognition_page.html` and set PROXY_BASE to the car address
  `http://10.168.202.242:5000`. Place the file into your project's static folder and open it.

Notes / Troubleshooting
-----------------------
- If using direct mode, ensure the car service allows connections from the client
  host and CORS is properly configured (the car service currently does not set CORS).
- Proxy mode avoids CORS and centralizes auth if needed.
- If you want the page integrated into a different frontend stack (React/Vue), copy
  only the UI logic (the small JS functions) into your app and call the same endpoints.

If you want, I can:
- Patch your zihan-car project files directly (if you provide the project in the workspace).
- Add CORS support to the car service or return the page directly from the car service.
