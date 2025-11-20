# app.py
from flask import Flask, request, jsonify, g
from flask_cors import CORS
import logging, time, os
from datetime import date, datetime
from decimal import Decimal
import mysql.connector
from db_config import get_connection

# Auth helpers
import bcrypt
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired

app = Flask(__name__)
CORS(app)

# ---------- logging ----------
logging.basicConfig(level=logging.INFO,
                    format='[%(asctime)s] %(levelname)s: %(message)s')

@app.before_request
def _log_request():
    g._t0 = time.perf_counter()
    qs = request.query_string.decode() or ''
    app.logger.info(">> %s %s%s from %s",
                    request.method, request.path,
                    f"?{qs}" if qs else "", request.remote_addr)

@app.after_request
def _log_response(resp):
    dt_ms = (time.perf_counter() - getattr(g, "_t0", time.perf_counter())) * 1000
    app.logger.info("<< %s %s %s (%.1f ms)",
                    request.method, request.path, resp.status, dt_ms)
    return resp

# ---------- helpers ----------
def ok(payload=None, status=200): return (jsonify(payload or {}), status)
def err(msg, status=400):         return (jsonify({"error": str(msg)}), status)

def _coerce(v):
    # Datetime -> "YYYY-MM-DD HH:MM:SS"
    if isinstance(v, datetime):
        return v.strftime('%Y-%m-%d %H:%M:%S')
    # Date -> "YYYY-MM-DD"
    if isinstance(v, date):
        return v.isoformat()
    # MySQL DECIMAL -> float
    if isinstance(v, Decimal):
        return float(v)
    # Optional: bytes/bytearray -> utf-8 string
    if isinstance(v, (bytes, bytearray)):
        try:
            return v.decode('utf-8')
        except Exception:
            return str(v)
    return v

def _dict_rows(cur):
    rows = cur.fetchall()
    return [{k: _coerce(v) for k, v in r.items()} for r in rows]

# Prefer Bearer token, fallback to ?userId=
app.config['AUTH_SECRET'] = os.environ.get('AUTH_SECRET', 'dev-secret-change-me')
_signer = URLSafeTimedSerializer(app.config['AUTH_SECRET'])
TOKEN_MAX_AGE = 60 * 60 * 24 * 7  # 7 days

def _uid_from_bearer():
    auth = request.headers.get('Authorization', '')
    if not auth.startswith('Bearer '): return None
    token = auth[7:].strip()
    try:
        data = _signer.loads(token, max_age=TOKEN_MAX_AGE)
        return int(data.get('uid'))
    except (BadSignature, SignatureExpired, Exception):
        return None

def get_user_id() -> int:
    uid = _uid_from_bearer()
    if uid is not None: return uid
    try:
        return int(request.args.get("userId", "1"))
    except Exception:
        return 1

# ---------- health ----------
@app.get("/__ping")
def ping(): return ok({"ok": True, "ts": time.time()})

@app.get("/__dbcheck")
def dbcheck():
    try:
        cn = get_connection(); cur = cn.cursor()
        cur.execute("SELECT 1"); cur.fetchone()
        cur.close(); cn.close()
        return ok({"ok": True})
    except Exception as e:
        app.logger.exception("DB check failed")
        return err(e, 500)

# =========================================================
#                          AUTH
# =========================================================
def _hash_pw(plain: str) -> bytes:
    return bcrypt.hashpw(plain.encode('utf-8'), bcrypt.gensalt(rounds=12))

def _check_pw(plain: str, hashed: bytes) -> bool:
    try:    return bcrypt.checkpw(plain.encode('utf-8'), hashed)
    except: return False

def _make_token(user_id: int) -> str:
    return _signer.dumps({"uid": user_id})

@app.post("/auth/signup")
def auth_signup():
    data = request.get_json(force=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    display_name = (data.get("display_name") or "").strip() or "User"

    if not email or not password:
        return err("email and password required", 422)

    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("SELECT id FROM profile WHERE email=%s", (email,))
    if cur.fetchone():
        cur.close(); cn.close()
        return err("email already in use", 409)

    cur.execute("SELECT COALESCE(MAX(id),0)+1 AS next_id FROM profile")
    next_id = int(cur.fetchone()["next_id"])

    pw_hash = _hash_pw(password)
    cur2 = cn.cursor()
    cur2.execute("""
        INSERT INTO profile (id, display_name, email, password_hash)
        VALUES (%s,%s,%s,%s)
    """, (next_id, display_name, email, pw_hash))
    cn.commit()
    cur2.close(); cur.close(); cn.close()

    token = _make_token(next_id)
    return ok({"user_id": next_id, "token": token}, 201)

@app.post("/auth/login")
def auth_login():
    data = request.get_json(force=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    if not email or not password:
        return err("email and password required", 422)

    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("SELECT id, password_hash FROM profile WHERE email=%s", (email,))
    row = cur.fetchone()
    cur.close(); cn.close()

    # Return a clean error for bad creds
    if not row or not row.get("password_hash"):
        return err("invalid credentials", 401)
    if not _check_pw(password, row["password_hash"].encode('utf-8')):
        return err("invalid credentials", 401)

    token = _make_token(int(row["id"]))
    return ok({"user_id": int(row["id"]), "token": token})

@app.get("/auth/me")
def auth_me():
    uid = _uid_from_bearer()
    if uid is None: return err("no/invalid token", 401)
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
        SELECT id AS user_id, display_name, email, avatar_url, bio, updated_at
        FROM profile WHERE id=%s
    """, (uid,))
    row = cur.fetchone()
    cur.close(); cn.close()
    if not row: return err("user not found", 404)
    return ok({k: _coerce(v) for k, v in row.items()})

# =========================================================
#                          PROFILE
# =========================================================
@app.get("/profile")
def profile_get():
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
        SELECT id AS user_id, display_name, email, avatar_url, bio, updated_at
        FROM profile WHERE id=%s
    """, (uid,))
    row = cur.fetchone()
    cur.close(); cn.close()
    if not row:
        row = {"user_id": uid, "display_name": "Your Name",
               "email": "you@example.com", "avatar_url": None, "bio": "",
               "updated_at": None}
    return ok({k: _coerce(v) for k, v in row.items()})

@app.put("/profile")
def profile_put():
    uid = get_user_id()
    data = request.get_json(force=True) or {}

    # Allow only these fields to be updated
    allowed = ("display_name", "email", "avatar_url", "bio")
    fields, vals = [], []

    for k in allowed:
        if k in data:
            fields.append(f"{k}=%s")
            vals.append(data[k])

    if not fields:
        return err("no fields", 422)

    cn = get_connection()
    cur = cn.cursor()

    # 1) Try update first
    vals_update = vals + [uid]
    cur.execute(
        f"UPDATE profile SET {', '.join(fields)} WHERE id=%s",
        vals_update
    )
    cn.commit()

    # 2) If no row updated, insert a new row safely
    if cur.rowcount == 0:
        display_name = data.get("display_name", "User")
        email = data.get("email", None)          # allow NULL
        avatar_url = data.get("avatar_url", None)
        bio = data.get("bio", "")

        cur.execute("""
            INSERT INTO profile (id, display_name, email, avatar_url, bio)
            VALUES (%s, %s, %s, %s, %s)
        """, (uid, display_name, email, avatar_url, bio))
        cn.commit()

    cur.close()
    cn.close()
    return ok({"ok": True})

# =========================================================
#                          TASKS
# =========================================================
@app.get("/tasks")
def tasks_list():
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
        SELECT id, user_id, title, urgency, due_date, done, created_at
        FROM tasks
        WHERE user_id=%s
        ORDER BY done ASC, created_at DESC
    """, (uid,))
    rows = _dict_rows(cur)
    cur.close(); cn.close()
    return ok(rows)

@app.post("/tasks")
def tasks_create():
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    title = (data.get("title") or "").strip()
    urgency = int(data.get("urgency", 1))
    due = data.get("due_date")
    if not title: return err("title required", 422)
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
        INSERT INTO tasks (user_id, title, urgency, due_date)
        VALUES (%s,%s,%s,%s)
    """, (uid, title, urgency, due))
    cn.commit()
    new_id = cur.lastrowid
    cur.close(); cn.close()
    return ok({"id": new_id}, 201)

@app.put("/tasks/<int:task_id>")
def tasks_update(task_id: int):
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    fields, vals = [], []
    for k in ("title", "urgency", "due_date", "done"):
        if k in data:
            fields.append(f"{k}=%s"); vals.append(data[k])
    if not fields: return err("no fields to update", 422)
    vals.extend([uid, task_id])
    cn = get_connection(); cur = cn.cursor()
    cur.execute(f"UPDATE tasks SET {', '.join(fields)} WHERE user_id=%s AND id=%s", vals)
    cn.commit()
    count = cur.rowcount
    cur.close(); cn.close()
    if count == 0: return err("not found", 404)
    return ok({"updated": count})

@app.delete("/tasks/<int:task_id>")
def tasks_delete(task_id: int):
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor()
    cur.execute("DELETE FROM tasks WHERE user_id=%s AND id=%s", (uid, task_id))
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    if count == 0: return err("not found", 404)
    return ok({"deleted": count})

# =========================================================
#                           GOAL
# =========================================================
@app.get("/goal")
def goal_get():
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("SELECT user_id, progress FROM goals WHERE user_id=%s", (uid,))
    row = cur.fetchone()
    cur.close(); cn.close()
    if not row: return ok({"user_id": uid, "progress": 0.0})
    row["user_id"] = uid
    row["progress"] = _coerce(row["progress"])
    return ok(row)

@app.put("/goal")
def goal_put():
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    progress = float(data.get("progress", 0))
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
        INSERT INTO goals (user_id, progress)
        VALUES (%s,%s)
        ON DUPLICATE KEY UPDATE progress=VALUES(progress)
    """, (uid, progress))
    cn.commit()
    cur.close(); cn.close()
    return ok({"ok": True, "progress": progress})

# =========================================================
#                        NUTRIENTS
#   - current = computed from nutrient_history
#   - goal    = stored in `nutrients` (kind='goal')
# =========================================================
@app.get("/nutrients")
def nutrients_get():
    uid = get_user_id()

    # Optional date filter (?date=YYYY-MM-DD), default = today
    day = request.args.get("date")
    if not day:
        day = datetime.utcnow().date().isoformat()

    # 1) Compute CURRENT from history of that date
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
      SELECT
        COALESCE(SUM(veg_g),0)     AS veg_g,
        COALESCE(SUM(carb_g),0)    AS carb_g,
        COALESCE(SUM(protein_g),0) AS protein_g
      FROM nutrient_history
      WHERE user_id=%s AND DATE(eaten_at)=%s
    """, (uid, day))
    sums = cur.fetchone() or {"veg_g":0,"carb_g":0,"protein_g":0}
    cur.close(); cn.close()

    veg_g = float(sums["veg_g"]); carb_g = float(sums["carb_g"]); protein_g = float(sums["protein_g"])
    total = max(veg_g + carb_g + protein_g, 0.0)
    if total > 0:
        current = {
            "veg": round(veg_g / total, 4),
            "carb": round(carb_g / total, 4),
            "protein": round(protein_g / total, 4),
            "grams": {"veg_g": veg_g, "carb_g": carb_g, "protein_g": protein_g, "total_g": total},
            "date": day
        }
    else:
        current = {"veg": 0.0, "carb": 0.0, "protein": 0.0,
                   "grams": {"veg_g": 0, "carb_g": 0, "protein_g": 0, "total_g": 0},
                   "date": day}

    # 2) Read GOAL from nutrients(kind='goal')
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
      SELECT veg, carb, protein, updated_at
      FROM nutrients WHERE user_id=%s AND kind='goal'
    """, (uid,))
    row = cur.fetchone()
    cur.close(); cn.close()

    if row:
        goal = {"veg": float(row["veg"]), "carb": float(row["carb"]),
                "protein": float(row["protein"]), "updated_at": _coerce(row["updated_at"])}
    else:
        goal = {"veg": 0.48, "carb": 0.30, "protein": 0.22, "updated_at": None}

    return ok({"current": current, "goal": goal})

# Keep body-style PUT (backward compat), but only persist GOAL
@app.put("/nutrients")
def nutrients_put_body():
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    # Accept { "goal": {veg,carb,protein} }
    if "goal" in data:
        s = data["goal"] or {}
        return _write_goal(uid, float(s.get("veg", 0)), float(s.get("carb", 0)), float(s.get("protein", 0)))
    return err("only 'goal' is editable now", 422)

# Allow PUT /nutrients/goal
@app.put("/nutrients/<kind>")
def nutrients_put(kind: str):
    kind = kind.lower()
    if kind != "goal":
        return err("current is computed from history; only 'goal' is editable", 422)
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    veg = float(data.get("veg", 0)); carb = float(data.get("carb", 0)); protein = float(data.get("protein", 0))
    return _write_goal(uid, veg, carb, protein)

def _write_goal(uid: int, veg: float, carb: float, protein: float):
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
        INSERT INTO nutrients (user_id, kind, veg, carb, protein)
        VALUES (%s,'goal',%s,%s,%s)
        ON DUPLICATE KEY UPDATE veg=VALUES(veg), carb=VALUES(carb), protein=VALUES(protein)
    """, (uid, veg, carb, protein))
    cn.commit(); cur.close(); cn.close()
    return ok({"ok": True})

#edit
@app.put("/nutrients/history/<int:hid>")
def nutrients_history_update(hid: int):
    uid = get_user_id()
    d = request.get_json(force=True) or {}

    # Allow only these fields to be edited
    allowed = ("name", "veg_g", "carb_g", "protein_g", "amount_g", "note", "eaten_at")
    fields, vals = [], []

    for k in allowed:
        if k in d:
            fields.append(f"{k}=%s")
            vals.append(d[k])

    if not fields:
        return err("no fields to update", 422)

    vals += [uid, hid]

    cn = get_connection()
    cur = cn.cursor()
    cur.execute(
        f"UPDATE nutrient_history SET {', '.join(fields)} WHERE user_id=%s AND id=%s",
        vals
    )
    cn.commit()
    count = cur.rowcount
    cur.close()
    cn.close()

    if count == 0:
        return err("not found", 404)

    return ok({"updated": count})

# =========================================================
#                         DIARY
# =========================================================
@app.get("/diary")
def diary_list():
    uid = get_user_id()
    d = request.args.get("date")  # YYYY-MM-DD
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    if d:
        cur.execute("""
            SELECT id, user_id, entry_date, title, content, mood, created_at, updated_at
            FROM diary_entries
            WHERE user_id=%s AND entry_date=%s
            ORDER BY created_at DESC
        """, (uid, d))
    else:
        cur.execute("""
            SELECT id, user_id, entry_date, title, content, mood, created_at, updated_at
            FROM diary_entries
            WHERE user_id=%s
            ORDER BY entry_date DESC, created_at DESC
            LIMIT 50
        """, (uid,))
    rows = _dict_rows(cur)
    cur.close(); cn.close()
    return ok(rows)

@app.post("/diary")
def diary_add():
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    entry_date = data.get("date") or datetime.utcnow().date().isoformat()
    title = (data.get("title") or "").strip()
    content = (data.get("content") or "").strip()
    mood = data.get("mood")
    if not title and not content:
        return err("title or content required", 422)
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
        INSERT INTO diary_entries (user_id, entry_date, title, content, mood)
        VALUES (%s,%s,%s,%s,%s)
    """, (uid, entry_date, title, content, mood))
    cn.commit()
    new_id = cur.lastrowid
    cur.close(); cn.close()
    return ok({"id": new_id}, 201)

@app.delete("/diary/<int:item_id>")
def diary_delete(item_id: int):
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor()
    cur.execute("DELETE FROM diary_entries WHERE user_id=%s AND id=%s", (uid, item_id))
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    if count == 0: return err("not found", 404)
    return ok({"deleted": count})

# =========================================================
#                     CALENDAR EVENTS
# =========================================================
@app.get("/calendar/events")
def calendar_events_list():
    uid = get_user_id()
    start = request.args.get("start"); end = request.args.get("end")
    if not start or not end: return err("start and end required (YYYY-MM-DD)", 422)
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    cur.execute("""
        SELECT id, user_id, title, note, starts_at, ends_at, all_day, color, created_at
        FROM calendar_events
        WHERE user_id=%s AND starts_at>=CONCAT(%s,' 00:00:00') AND ends_at<=CONCAT(%s,' 23:59:59')
        ORDER BY starts_at ASC
    """, (uid, start, end))
    rows = _dict_rows(cur)
    cur.close(); cn.close()
    return ok(rows)

@app.post("/calendar/events")
def calendar_events_add():
    uid = get_user_id()
    data = request.get_json(force=True) or {}
    title = (data.get("title") or "").strip()
    starts_at = data.get("starts_at")
    ends_at   = data.get("ends_at")
    note      = data.get("note")
    all_day   = int(bool(data.get("all_day", 0)))
    color     = data.get("color")
    if not title or not starts_at:
        return err("title and starts_at required", 422)
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
        INSERT INTO calendar_events (user_id, title, note, starts_at, ends_at, all_day, color)
        VALUES (%s,%s,%s,%s,%s,%s,%s)
    """, (uid, title, note, starts_at, ends_at, all_day, color))
    cn.commit()
    new_id = cur.lastrowid
    cur.close(); cn.close()
    return ok({"id": new_id}, 201)

@app.delete("/calendar/events/<int:eid>")
def calendar_events_delete(eid: int):
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor()
    cur.execute("DELETE FROM calendar_events WHERE user_id=%s AND id=%s", (uid, eid))
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    if count == 0: return err("not found", 404)
    return ok({"deleted": count})

# =========================================================
#                         FOODS (catalog)
# =========================================================
@app.get("/foods")
def foods_list():
    uid = get_user_id()
    q = (request.args.get("q") or "").strip()
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    if q:
        cur.execute("""
          SELECT id, user_id, name, veg_g, carb_g, protein_g, per_unit_g, created_at
          FROM food_items WHERE user_id=%s AND name LIKE %s
          ORDER BY name ASC
        """, (uid, f"%{q}%"))
    else:
        cur.execute("""
          SELECT id, user_id, name, veg_g, carb_g, protein_g, per_unit_g, created_at
          FROM food_items WHERE user_id=%s
          ORDER BY name ASC
        """, (uid,))
    rows = _dict_rows(cur)
    cur.close(); cn.close()
    return ok(rows)

@app.post("/foods")
def foods_create():
    uid = get_user_id()
    d = request.get_json(force=True) or {}
    name = (d.get("name") or "").strip()
    if not name: return err("name required", 422)
    veg = float(d.get("veg_g", 0)); carb = float(d.get("carb_g", 0)); prot = float(d.get("protein_g", 0))
    per  = float(d.get("per_unit_g", 100))
    cn = get_connection(); cur = cn.cursor()
    cur.execute("""
      INSERT INTO food_items (user_id, name, veg_g, carb_g, protein_g, per_unit_g)
      VALUES (%s,%s,%s,%s,%s,%s)
    """, (uid, name, veg, carb, prot, per))
    cn.commit(); nid = cur.lastrowid
    cur.close(); cn.close()
    return ok({"id": nid}, 201)

@app.put("/foods/<int:fid>")
def foods_update(fid):
    uid = get_user_id()
    d = request.get_json(force=True) or {}
    fields, vals = [], []
    for k in ("name", "veg_g", "carb_g", "protein_g", "per_unit_g"):
        if k in d: fields.append(f"{k}=%s"); vals.append(d[k])
    if not fields: return err("no fields", 422)
    vals += [uid, fid]
    cn = get_connection(); cur = cn.cursor()
    cur.execute(f"UPDATE food_items SET {', '.join(fields)} WHERE user_id=%s AND id=%s", vals)
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    return ok({"updated": count}) if count else err("not found", 404)

@app.delete("/foods/<int:fid>")
def foods_delete(fid):
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor()
    cur.execute("DELETE FROM food_items WHERE user_id=%s AND id=%s", (uid, fid))
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    return ok({"deleted": count}) if count else err("not found", 404)

# =========================================================
#                   NUTRIENT HISTORY (list/add/remove)
# =========================================================
@app.get("/nutrients/history")
def nutrients_history_list():
    uid = get_user_id()
    limit = int(request.args.get("limit", "20"))
    day   = request.args.get("date")  # optional YYYY-MM-DD
    cn = get_connection(); cur = cn.cursor(dictionary=True)
    if day:
        cur.execute("""
          SELECT id, user_id, eaten_at, food_id, name, veg_g, carb_g, protein_g, amount_g, note
          FROM nutrient_history
          WHERE user_id=%s AND DATE(eaten_at) = %s
          ORDER BY eaten_at DESC
          LIMIT %s
        """, (uid, day, limit))
    else:
        cur.execute("""
          SELECT id, user_id, eaten_at, food_id, name, veg_g, carb_g, protein_g, amount_g, note
          FROM nutrient_history
          WHERE user_id=%s
          ORDER BY eaten_at DESC
          LIMIT %s
        """, (uid, limit))
    rows = _dict_rows(cur); cur.close(); cn.close()
    return ok(rows)

@app.post("/nutrients/history")
def nutrients_history_add():
    uid = get_user_id()
    d = request.get_json(force=True) or {}
    eaten_at = d.get("eaten_at")  # optional ISO string
    cn = get_connection(); cur = cn.cursor(dictionary=True)

    if d.get("food_id"):
        fid = int(d["food_id"])
        amt = float(d.get("amount_g", 100))
        cur.execute("SELECT name, veg_g, carb_g, protein_g, per_unit_g FROM food_items WHERE user_id=%s AND id=%s",
                    (uid, fid))
        row = cur.fetchone()
        if not row:
            cur.close(); cn.close()
            return err("food not found", 404)
        scale = amt / float(row["per_unit_g"])
        veg = float(row["veg_g"]) * scale
        carb = float(row["carb_g"]) * scale
        prot = float(row["protein_g"]) * scale
        name = row["name"]
    else:
        name = (d.get("name") or "").strip() or None
        veg  = float(d.get("veg_g", 0))
        carb = float(d.get("carb_g", 0))
        prot = float(d.get("protein_g", 0))

    cur2 = cn.cursor()
    cur2.execute("""
      INSERT INTO nutrient_history (user_id, eaten_at, food_id, name, veg_g, carb_g, protein_g, amount_g, note)
      VALUES (%s, COALESCE(%s, NOW()), %s, %s, %s, %s, %s, %s, %s)
    """, (uid, eaten_at, d.get("food_id"), name, veg, carb, prot,
          d.get("amount_g"), d.get("note")))
    cn.commit(); nid = cur2.lastrowid
    cur2.close(); cur.close(); cn.close()
    return ok({"id": nid}, 201)

@app.delete("/nutrients/history/<int:hid>")
def nutrients_history_delete(hid):
    uid = get_user_id()
    cn = get_connection(); cur = cn.cursor()
    cur.execute("DELETE FROM nutrient_history WHERE user_id=%s AND id=%s", (uid, hid))
    cn.commit(); count = cur.rowcount
    cur.close(); cn.close()
    return ok({"deleted": count}) if count else err("not found", 404)

# ---------- run ----------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
