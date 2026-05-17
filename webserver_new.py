import os,random,time,signal,subprocess,threading,socket
from flask import Flask, flash, request, redirect, url_for,render_template
from werkzeug.utils import secure_filename
from flask import send_from_directory
from datetime import datetime
from PIL import Image
import json
from inky.auto import auto
import RPi.GPIO as GPIO
from PIL import ImageDraw,Image
import generateInfo

BUTTONS = [5, 6, 16, 24]
ORIENTATION = 0
ADJUST_AR = False

GPIO.setmode(GPIO.BCM)
GPIO.setup(BUTTONS, GPIO.IN, pull_up_down=GPIO.PUD_UP)

PATH = os.path.dirname(os.path.dirname(__file__))
print(PATH)
UPLOAD_FOLDER = os.path.join(PATH,"img")
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg','webp'}
print(ALLOWED_EXTENSIONS)

pathExist = os.path.exists(os.path.join(PATH,"img"))
if(pathExist == False):
   os.makedirs(os.path.join(PATH,"img"))

inky_display = auto(ask_user=True, verbose=True)
inky_display.set_border(inky_display.BLACK)

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

@app.before_request
def handle_preflight():
    if request.method == 'OPTIONS':
        resp = app.response_class('', status=204)
        resp.headers['Access-Control-Allow-Origin'] = '*'
        resp.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        resp.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return resp

@app.after_request
def add_cors(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    return response

def handleButton(pin):
    if(pin == 5):
        print("--A-- Pressed: Show Plink info")
        generateInfo.infoGen(inky_display.width,inky_display.height)
        updateEink("infoImage.png",0,"")
    elif(pin == 6):
        print("--B-- Pressed: Rotate image clockwise")
        rotateImage(-90)
    elif(pin == 16):
        print("--C-- Pressed: Rotate image counter clockwise")
        rotateImage(90)
    elif(pin == 24):
        print("--D-- Pressed: Reboot the Pi")
        os.system('sudo reboot')

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# ── Legacy route (kept for curl/backward compat) ─────────────────────────────
@app.route('/', methods=['GET', 'POST'])
def upload_file():
    print("req ",request.files)
    ADJUST_AR = False
    arSwitchCheck,horizontalOrientationRadioCheck,verticalOrientationRadioCheck = loadSettings()
    if horizontalOrientationRadioCheck == "checked":
        ORIENTATION = 0
    else:
        ORIENTATION = 1
    if arSwitchCheck == "checked":
        ADJUST_AR = True
    if request.method == 'POST':
        if 'file' in request.files or (request.form and request.form.get("submit") == "Upload Image"):
            file = request.files['file']
            if file and allowed_file(file.filename):
                deleteImage()
                filename = secure_filename(file.filename)
                file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
                filename = os.path.join(app.config['UPLOAD_FOLDER'],filename)
                updateEink(filename,ORIENTATION,ADJUST_AR)
                if(len(request.form) == 0):
                    return "File uploaded successfully", 200
            else:
                deleteImage()
                imageLink = request.form.getlist("text")[0]
                try:
                    filename = imageLink.replace(":","").replace("/","")
                    filename = filename.split("?")[0]
                    urllib.request.urlretrieve(imageLink, os.path.join(app.config['UPLOAD_FOLDER'], filename))
                    updateEink(filename,ORIENTATION,ADJUST_AR)
                except:
                    flash("Error: Unsupported Media or Invalid Link!")
                    return render_template('main.html')
        if request.form.get("submit") == 'Reboot':
            os.system("sudo reboot")
        if request.form.get("submit") == 'Shutdown':
            os.system("sudo shutdown")
        if request.form.get("submit") == 'rotateImage':
            rotateImage(-90)
        if request.form.get("submit") == 'clearGhost':
            clearScreen()
        if request.form.get("submit") == 'Save Settings':
            if(request.form["frame_orientation"] == "Horizontal Orientation"):
                horizontalOrientationRadioCheck = "checked"
                verticalOrientationRadioCheck = ""
            else:
                horizontalOrientationRadioCheck = ""
                verticalOrientationRadioCheck = "checked"
            try:
                if request.form["adjust_ar"] == "true":
                    arSwitchCheck = "checked"
            except:
                arSwitchCheck = ""
            saveSettings(horizontalOrientationRadioCheck,verticalOrientationRadioCheck,arSwitchCheck)
            return render_template('main.html')
    return render_template('main.html')

# ── New JSON API ──────────────────────────────────────────────────────────────

@app.route('/api/status')
def api_status():
    wifi = '--'
    try:
        out = subprocess.check_output(['iw','dev','wlan0','link'], stderr=subprocess.DEVNULL).decode()
        for line in out.split('\n'):
            if 'signal:' in line:
                wifi = line.strip().replace('signal:','').strip()
                break
    except Exception:
        pass

    uptime = '--'
    try:
        with open('/proc/uptime') as f:
            secs = float(f.read().split()[0])
        days = int(secs // 86400)
        hours = int((secs % 86400) // 3600)
        uptime = (f'{days}d ' if days else '') + f'{hours}h'
    except Exception:
        pass

    image_url = None
    try:
        q = load_queue()
        if q["items"]:
            cur = q.get("current", 0) % len(q["items"])
            fname = q["items"][cur]["filename"]
            fpath = os.path.join(app.config['UPLOAD_FOLDER'], fname)
            if os.path.isfile(fpath):
                image_url = '/uploads/' + fname
    except Exception:
        pass
    if image_url is None:
        try:
            imgs = [i for i in os.listdir(app.config['UPLOAD_FOLDER']) if not i.startswith('.')]
            if imgs:
                image_url = '/uploads/' + imgs[0]
        except Exception:
            pass

    _, horiz, _ = loadSettings()
    orientation = 'landscape' if horiz == 'checked' else 'portrait'

    return app.response_class(
        json.dumps({'wifi': wifi, 'uptime': uptime, 'image_url': image_url, 'orientation': orientation, 'lan_ip': _LAN_IP}),
        mimetype='application/json'
    )


@app.route('/api/upload', methods=['POST'])
def api_upload():
    _, horiz, _ = loadSettings()
    orientation = 0 if horiz == 'checked' else 1
    try:
        if 'file' in request.files and request.files['file'].filename:
            file = request.files['file']
            if not allowed_file(file.filename):
                return app.response_class(json.dumps({'error': 'Unsupported file type'}), status=400, mimetype='application/json')
            deleteImage()
            filename = secure_filename(file.filename)
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(filepath)
            updateEink(filename, orientation, True)
            return app.response_class(json.dumps({'ok': True, 'image_url': '/uploads/' + filename}), mimetype='application/json')
        else:
            return app.response_class(json.dumps({'error': 'No file provided'}), status=400, mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')


@app.route('/api/action', methods=['POST'])
def api_action():
    action = request.form.get('action', '')
    _, horiz, _ = loadSettings()
    orientation = 0 if horiz == 'checked' else 1

    if action == 'reboot':
        os.system('sudo reboot &')
        return app.response_class(json.dumps({'ok': True}), mimetype='application/json')

    elif action == 'shutdown':
        os.system('sudo shutdown now &')
        return app.response_class(json.dumps({'ok': True}), mimetype='application/json')

    elif action == 'clear_ghost':
        blank = Image.new('RGB', (inky_display.width, inky_display.height), (255, 255, 255))
        inky_display.set_image(blank)
        inky_display.show()
        imgs = [i for i in os.listdir(app.config['UPLOAD_FOLDER']) if not i.startswith('.')]
        if imgs:
            updateEink(imgs[0], orientation, True)
        return app.response_class(json.dumps({'ok': True}), mimetype='application/json')

    elif action == 'rotate':
        imgs = [i for i in os.listdir(app.config['UPLOAD_FOLDER']) if not i.startswith('.')]
        if not imgs:
            return app.response_class(json.dumps({'error': 'No image to rotate'}), status=400, mimetype='application/json')
        fname = imgs[0]
        fpath = os.path.join(PATH, 'img', fname)
        with Image.open(fpath) as img:
            rotated = img.rotate(-90, Image.NEAREST, expand=1)
            rotated.save(fpath)
        updateEink(fname, orientation, True)
        return app.response_class(json.dumps({'ok': True, 'image_url': '/uploads/' + fname}), mimetype='application/json')

    return app.response_class(json.dumps({'error': 'Unknown action'}), status=400, mimetype='application/json')


@app.route('/api/settings', methods=['POST'])
def api_settings():
    try:
        data = request.get_json(force=True, silent=True) or {}
        orientation = data.get('orientation', 'landscape')
        horiz = 'checked' if orientation == 'landscape' else ''
        vert  = '' if orientation == 'landscape' else 'checked'
        _, _, ar = loadSettings()
        saveSettings(horiz, vert, ar)
        return app.response_class(json.dumps({'ok': True}), mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')

# ── Queue API ─────────────────────────────────────────────────────────────────

QUEUE_FILE = os.path.join(PATH, "config/queue.json")
_rotate_timer = None
_rotate_lock  = threading.Lock()

def load_queue():
    try:
        with open(QUEUE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"items": [], "current": 0, "interval": 0}

def save_queue(q):
    os.makedirs(os.path.join(PATH, "config"), exist_ok=True)
    with open(QUEUE_FILE, "w") as f:
        json.dump(q, f)

def _show_queue_item(q, idx):
    if not q["items"]:
        return
    fname = q["items"][idx % len(q["items"])]["filename"]
    _, horiz, _ = loadSettings()
    orientation = 0 if horiz == "checked" else 1
    try:
        updateEink(fname, orientation, True)
    except Exception as e:
        print(f"Queue display error: {e}")

def _schedule_rotate():
    global _rotate_timer
    with _rotate_lock:
        if _rotate_timer:
            _rotate_timer.cancel()
            _rotate_timer = None
        q = load_queue()
        interval = q.get("interval", 0)
        if interval > 0 and len(q["items"]) > 1:
            _rotate_timer = threading.Timer(interval * 60, _do_rotate)
            _rotate_timer.daemon = True
            _rotate_timer.start()

def _do_rotate():
    q = load_queue()
    if len(q["items"]) <= 1:
        return
    q["current"] = (q.get("current", 0) + 1) % len(q["items"])
    save_queue(q)
    _show_queue_item(q, q["current"])
    _schedule_rotate()


@app.route('/api/queue', methods=['GET'])
def api_queue_get():
    return app.response_class(json.dumps(load_queue()), mimetype='application/json')


@app.route('/api/queue/add', methods=['POST'])
def api_queue_add():
    q = load_queue()
    try:
        label = request.form.get('label', '')
        if 'file' in request.files and request.files['file'].filename:
            file = request.files['file']
            if not allowed_file(file.filename):
                return app.response_class(json.dumps({'error': 'Unsupported file type'}), status=400, mimetype='application/json')
            ts = datetime.now().strftime('%Y%m%d_%H%M%S_')
            filename = ts + secure_filename(file.filename)
            file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        else:
            return app.response_class(json.dumps({'error': 'No file provided'}), status=400, mimetype='application/json')

        show_now = request.form.get('show_now') == '1'
        item = {"filename": filename, "label": label or filename, "added_at": datetime.now().isoformat()}
        q["items"].append(item)
        new_idx = len(q["items"]) - 1
        was_empty = new_idx == 0

        if was_empty or show_now:
            q["current"] = new_idx
        save_queue(q)

        if was_empty or show_now:
            _show_queue_item(q, new_idx)

        _schedule_rotate()
        return app.response_class(json.dumps({'ok': True, 'image_url': '/uploads/' + filename, 'queue': q}), mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')


@app.route('/api/queue/remove', methods=['POST'])
def api_queue_remove():
    q = load_queue()
    try:
        data = request.get_json(force=True, silent=True) or {}
        idx = int(data.get('index', -1))
        if idx < 0 or idx >= len(q["items"]):
            return app.response_class(json.dumps({'error': 'Invalid index'}), status=400, mimetype='application/json')

        old_current = q.get("current", 0)
        item = q["items"].pop(idx)

        # Delete file only if no other queue item references it AND queue is not now empty
        # (keep the file if queue becomes empty — it's still showing on e-ink)
        if not any(i["filename"] == item["filename"] for i in q["items"]):
            if len(q["items"]) > 0:
                fp = os.path.join(app.config['UPLOAD_FOLDER'], item["filename"])
                if os.path.isfile(fp):
                    os.remove(fp)

        # Adjust current pointer correctly
        if idx < old_current:
            q["current"] = old_current - 1          # same item still shown, index shifted
        elif q["current"] >= len(q["items"]) and q["current"] > 0:
            q["current"] = len(q["items"]) - 1      # was at end, clamp

        save_queue(q)

        # Only refresh e-ink if the shown item actually changed (deleted current & more remain)
        # Run in background thread so HTTP response returns immediately
        if idx == old_current and q["items"]:
            threading.Thread(target=_show_queue_item, args=(q, q["current"]), daemon=True).start()

        _schedule_rotate()
        return app.response_class(json.dumps({'ok': True, 'queue': q}), mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')


@app.route('/api/queue/reorder', methods=['POST'])
def api_queue_reorder():
    data = request.get_json(force=True)
    new_order = data.get('order', [])
    q = load_queue()
    items = q['items']
    if len(new_order) != len(items) or sorted(new_order) != list(range(len(items))):
        return app.response_class(json.dumps({'error': 'Invalid order'}), status=400, mimetype='application/json')
    current = q.get('current', 0)
    q['items'] = [items[i] for i in new_order]
    q['current'] = new_order.index(current)
    save_queue(q)
    return app.response_class(json.dumps({'ok': True, 'queue': q}), mimetype='application/json')


@app.route('/api/queue/next', methods=['POST'])
def api_queue_next():
    q = load_queue()
    if len(q["items"]) < 2:
        return app.response_class(json.dumps({'error': 'Queue has only one item'}), status=400, mimetype='application/json')
    q["current"] = (q.get("current", 0) + 1) % len(q["items"])
    save_queue(q)
    _show_queue_item(q, q["current"])
    _schedule_rotate()
    return app.response_class(json.dumps({'ok': True, 'queue': q}), mimetype='application/json')


@app.route('/api/queue/show', methods=['POST'])
def api_queue_show():
    q = load_queue()
    try:
        data = request.get_json(force=True, silent=True) or {}
        idx = int(data.get('index', 0))
        if idx < 0 or idx >= len(q["items"]):
            return app.response_class(json.dumps({'error': 'Invalid index'}), status=400, mimetype='application/json')
        q["current"] = idx
        save_queue(q)
        _show_queue_item(q, idx)
        _schedule_rotate()
        return app.response_class(json.dumps({'ok': True, 'queue': q}), mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')


@app.route('/api/queue/interval', methods=['POST'])
def api_queue_interval():
    q = load_queue()
    try:
        data = request.get_json(force=True, silent=True) or {}
        minutes = int(data.get('minutes', 0))
        q["interval"] = max(0, minutes)
        save_queue(q)
        _schedule_rotate()
        return app.response_class(json.dumps({'ok': True}), mimetype='application/json')
    except Exception as e:
        return app.response_class(json.dumps({'error': str(e)}), status=500, mimetype='application/json')


@app.route('/api/hotspot/status', methods=['GET'])
def api_hotspot_status():
    import os
    active = os.path.exists('/tmp/plink_ap_mode')
    try:
        import json as _json
        settings_path = '/home/pi/PiInk/config/settings.json'
        with open(settings_path) as f:
            s = _json.load(f)
        password = s.get('ap_password', 'plink123')
    except Exception:
        password = 'plink123'
    return app.response_class(
        json.dumps({'active': active, 'ssid': 'plink-setup', 'password': password, 'ip': '192.168.4.1'}),
        mimetype='application/json'
    )


# ── Shared helpers ────────────────────────────────────────────────────────────

def loadSettings():
    horizontalOrient = ""
    verticalOrient = ""
    try:
        jsonFile = open(os.path.join(PATH,"config/settings.json"))
    except:
        saveSettings("","checked",'aria-checked="false"')
        jsonFile = open(os.path.join(PATH,"config/settings.json"))
    settingsData = json.load(jsonFile)
    jsonFile.close()
    if settingsData.get("orientation") == "Horizontal":
        horizontalOrient = "checked"
        verticalOrient = ""
    else:
        verticalOrient = "checked"
        horizontalOrient = ""
    return settingsData.get("adjust_aspect_ratio"),horizontalOrient,verticalOrient

def saveSettings(orientationHorizontal,orientationVertical,adjustAR):
    if orientationHorizontal == "checked":
        orientationSetting = "Horizontal"
    else:
        orientationSetting = "Vertical"
    jsonStr = {
        "orientation":orientationSetting,
        "adjust_aspect_ratio":adjustAR,
    }
    with open(os.path.join(PATH,"config/settings.json"), "w") as f:
        json.dump(jsonStr, f)

def updateEink(filename,orientation,adjustAR):
    with Image.open(os.path.join(PATH, "img/",filename)) as img:
        img = changeOrientation(img,orientation)
        img = adjustAspectRatio(img,adjustAR)
        inky_display.set_image(img)
        inky_display.show()

def clearScreen():
    img = Image.new(mode="RGB", size=(inky_display.width, inky_display.height),color=(255,255,255))
    clearImage = ImageDraw.Draw(img)
    inky_display.set_image(img)
    inky_display.show()
    q = load_queue()
    if q["items"]:
        updateEink(q["items"][q["current"]]["filename"], ORIENTATION, ADJUST_AR)

def changeOrientation(img,orientation):
    if orientation == 0:
        img = img.rotate(0)
    elif orientation == 1:
        img = img.rotate(90)
    return img

def adjustAspectRatio(img,adjustARBool):
    w = inky_display.width
    h = inky_display.height
    ratioWidth = w / img.width
    ratioHeight = h / img.height
    if ratioWidth < ratioHeight:
        resizedWidth = w
        resizedHeight = round(ratioWidth * img.height)
    else:
        resizedWidth = round(ratioHeight * img.width)
        resizedHeight = h
    imgResized = img.resize((resizedWidth, resizedHeight), Image.LANCZOS)
    background = Image.new('RGB', (w, h), (255, 255, 255))
    offset = (round((w - resizedWidth) / 2), round((h - resizedHeight) / 2))
    background.paste(imgResized, offset)
    return background

def deleteImage():
    img_directory = os.path.join(PATH, "img")
    for filename in os.listdir(img_directory):
        fp = os.path.join(img_directory, filename)
        if os.path.isfile(fp):
            os.remove(fp)

def rotateImage(deg):
    q = load_queue()
    if not q["items"]:
        return
    filename = q["items"][q["current"]]["filename"]
    with Image.open(os.path.join(PATH, "img/", filename)) as img:
        img = img.rotate(deg, Image.NEAREST, expand=1)
        img = img.save(os.path.join(PATH, "img/", filename))
        updateEink(filename, ORIENTATION, ADJUST_AR)

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'],filename)


_MANIFEST = json.dumps({
    "name": "Plink",
    "short_name": "Plink",
    "description": "e-ink photo frame companion",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#d46b7a",
    "theme_color": "#d46b7a",
    "icons": [
        {"src": "/static/icon.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"}
    ],
    "share_target": {
        "action": "/share-target",
        "method": "POST",
        "enctype": "multipart/form-data",
        "params": {
            "files": [{"name": "file", "accept": ["image/jpeg", "image/png", "image/gif", "image/webp"]}]
        }
    }
})

@app.route('/manifest.json')
def manifest():
    return app.response_class(_MANIFEST, mimetype='application/manifest+json')


_SW = r"""
const CACHE = 'plink-v1';
const SHELL = ['/', '/manifest.json', '/static/icon.png'];

self.addEventListener('install', e => {
  // Cache while Pi is reachable (user just loaded the page).
  // skipWaiting only after caching so the SW activates ready.
  e.waitUntil(
    caches.open(CACHE)
      .then(c => Promise.all(SHELL.map(url => c.add(url).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;
  if (url.pathname.startsWith('/api/') || url.pathname === '/share-target') return;

  if (request.mode === 'navigate') {
    e.respondWith(
      fetch(request)
        .then(r => {
          if (r.ok) caches.open(CACHE).then(c => c.put('/', r.clone()));
          return r;
        })
        .catch(() => caches.match('/'))
    );
    return;
  }

  if (url.pathname.startsWith('/static/') || url.pathname === '/manifest.json') {
    e.respondWith(
      caches.match(request).then(cached => cached || fetch(request).then(r => {
        if (r.ok) caches.open(CACHE).then(c => c.put(request, r.clone()));
        return r;
      }))
    );
  }
});
"""

@app.route('/sw.js')
def service_worker():
    resp = app.response_class(_SW.strip(), mimetype='application/javascript')
    resp.headers['Service-Worker-Allowed'] = '/'
    return resp


@app.route('/share-target', methods=['GET', 'POST'])
def share_target():
    if request.method == 'POST':
        try:
            file = request.files.get('file')
            if file and file.filename and allowed_file(file.filename):
                q = load_queue()
                ts = datetime.now().strftime('%Y%m%d_%H%M%S_')
                filename = ts + secure_filename(file.filename)
                file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
                label = file.filename.rsplit('.', 1)[0]
                item = {"filename": filename, "label": label, "added_at": datetime.now().isoformat()}
                q["items"].append(item)
                new_idx = len(q["items"]) - 1
                was_empty = new_idx == 0
                if was_empty:
                    q["current"] = 0
                save_queue(q)
                if was_empty:
                    threading.Thread(target=_show_queue_item, args=(q, 0), daemon=True).start()
                _schedule_rotate()
        except Exception as e:
            print("share-target error:", e)
    return redirect('/?shared=1')


for pin in BUTTONS:
        GPIO.add_event_detect(pin, GPIO.FALLING, handleButton, bouncetime=250)

# ── Bonjour/mDNS advertisement (zeroconf) ─────────────────────────────────────
# Allows the iOS app to discover this frame automatically on the local network.
# Install: pip install zeroconf
def _get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

_LAN_IP = _get_lan_ip()

def _start_bonjour():
    try:
        from zeroconf import ServiceInfo, Zeroconf
        hostname = socket.gethostname()
        zc = Zeroconf()
        info = ServiceInfo(
            "_plink._tcp.local.",
            f"{hostname}._plink._tcp.local.",
            addresses=[socket.inet_aton(_LAN_IP)],
            port=80,
            properties={"version": b"1", "name": hostname.encode()},
        )
        zc.register_service(info)
        print(f"Bonjour: advertising _plink._tcp as {hostname} on {_LAN_IP}:80")
    except Exception as e:
        print(f"Bonjour: unavailable ({e}) — install with: pip install zeroconf")

threading.Thread(target=_start_bonjour, daemon=True).start()

if __name__ == '__main__':
    app.secret_key = str(random.randint(100000,999999))
    app.run(host="::", port=80, threaded=True)
