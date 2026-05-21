from pathlib import Path
import sys
from dotenv import load_dotenv


def get_app_dir():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


APP_DIR = get_app_dir()
load_dotenv(APP_DIR / ".env", override=True)

def setup_stdio_for_noconsole():
    if not getattr(sys, "frozen", False):
        return

    logs_dir = APP_DIR / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    if sys.stdout is None:
        sys.stdout = open(
            logs_dir / "backend_stdout.log",
            "a",
            encoding="utf-8",
            buffering=1
        )

    if sys.stderr is None:
        sys.stderr = open(
            logs_dir / "backend_stderr.log",
            "a",
            encoding="utf-8",
            buffering=1
        )


setup_stdio_for_noconsole()

from contextlib import asynccontextmanager
import subprocess
import time
from urllib.parse import urlparse
from fastapi import FastAPI, UploadFile, File, Body
from fastapi.middleware.cors import CORSMiddleware
import pyodbc
import os
import shutil
import json
import tempfile
import pandas as pd
import requests
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
import uvicorn
import bcrypt
import smtplib
import ssl
from email.message import EmailMessage


ML_SERVER_URL = os.getenv(
    "ML_SERVER_URL",
    "http://127.0.0.1:9000/predict/rul/report"
)

APP_ROOT = APP_DIR.parent

reports_folder_env = os.getenv("REPORTS_FOLDER", "reports")
reports_folder_path = Path(reports_folder_env)

if reports_folder_path.is_absolute():
    REPORTS_FOLDER = reports_folder_path
else:
    REPORTS_FOLDER = (APP_ROOT / reports_folder_path).resolve()

MODEL_API_PROCESS = None


def resolve_app_path(path_value: str | None, default_value: str) -> Path:
    raw_path = Path(path_value or default_value)

    if raw_path.is_absolute():
        return raw_path

    return (APP_DIR / raw_path).resolve()


def get_model_api_health_url() -> str:
    parsed = urlparse(ML_SERVER_URL)

    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}/health"

    return "http://127.0.0.1:9000/health"


def is_model_api_running() -> bool:
    try:
        response = requests.get(get_model_api_health_url(), timeout=2)
        return response.status_code == 200
    except Exception:
        return False


def kill_process_tree(process: subprocess.Popen):
    if process is None:
        return

    if process.poll() is not None:
        return

    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()


def start_model_api_if_needed():
    global MODEL_API_PROCESS

    autostart = os.getenv("MODEL_API_AUTOSTART", "true").lower() == "true"

    if not autostart:
        print("Model API autostart is disabled.")
        return

    if is_model_api_running():
        print(
            "Model API is already running before backend startup. "
            "Backend will not stop this external process."
        )
        return

    model_api_exe = resolve_app_path(
        os.getenv("MODEL_API_EXE"),
        "../model_api/model_api.exe"
    )

    if not model_api_exe.exists():
        raise RuntimeError(
            f"Model API executable was not found: {model_api_exe}. "
            "Set MODEL_API_EXE in backend .env."
        )

    model_api_dir = model_api_exe.parent

    logs_dir = APP_DIR / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    stdout_log_path = logs_dir / "model_api_stdout.log"
    stderr_log_path = logs_dir / "model_api_stderr.log"

    creationflags = 0
    if os.name == "nt":
        creationflags = subprocess.CREATE_NO_WINDOW

    stdout_log = open(stdout_log_path, "a", encoding="utf-8")
    stderr_log = open(stderr_log_path, "a", encoding="utf-8")

    model_api_env = os.environ.copy()
    model_api_env["BACKEND_PARENT_PID"] = str(os.getpid())

    try:
        MODEL_API_PROCESS = subprocess.Popen(
            [str(model_api_exe)],
            cwd=str(model_api_dir),
            stdout=stdout_log,
            stderr=stderr_log,
            creationflags=creationflags,
            env=model_api_env,
        )
    finally:
        stdout_log.close()
        stderr_log.close()

    timeout_seconds = int(os.getenv("MODEL_API_STARTUP_TIMEOUT", "90"))
    start_time = time.time()

    while time.time() - start_time < timeout_seconds:
        if is_model_api_running():
            print(f"Model API started successfully. PID={MODEL_API_PROCESS.pid}")
            return

        if MODEL_API_PROCESS.poll() is not None:
            raise RuntimeError(
                "Model API process exited during startup. "
                f"Check logs in: {logs_dir}"
            )

        time.sleep(1)

    kill_process_tree(MODEL_API_PROCESS)
    MODEL_API_PROCESS = None

    raise RuntimeError(
        f"Model API did not become ready within {timeout_seconds} seconds. "
        f"Check logs in: {logs_dir}"
    )


def stop_model_api_if_started_by_backend():
    global MODEL_API_PROCESS

    if MODEL_API_PROCESS is None:
        print("No model API process was started by this backend.")
        return

    print(f"Stopping model API process tree. PID={MODEL_API_PROCESS.pid}")

    kill_process_tree(MODEL_API_PROCESS)

    MODEL_API_PROCESS = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_model_api_if_needed()

    try:
        yield
    finally:
        stop_model_api_if_started_by_backend()


app = FastAPI(
    title="Aircraft Engine Health Backend API",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BACKEND_HOST = os.getenv("BACKEND_HOST", "127.0.0.1")
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "8000"))

REQUIRED_COLUMNS = [
    "alt", "Mach", "TRA", "T2",
    "T24", "T30", "T48", "T50",
    "P15", "P2", "P21", "P24", "Ps30", "P40", "P50",
    "Nf", "Nc", "Wf"
]


def get_connection():
    driver = os.getenv("DB_DRIVER", "ODBC Driver 17 for SQL Server")
    server = os.getenv("DB_SERVER")
    database = os.getenv("DB_NAME", "backendengine")
    trusted_connection = os.getenv("DB_TRUSTED_CONNECTION", "yes").lower()
    encrypt = os.getenv("DB_ENCRYPT", "no")
    trust_cert = os.getenv("DB_TRUST_SERVER_CERTIFICATE", "yes")

    if not server:
        raise RuntimeError("DB_SERVER is missing from .env")

    if driver not in pyodbc.drivers():
        raise RuntimeError(
            f"DB_DRIVER '{driver}' is not installed. Available drivers: {pyodbc.drivers()}"
        )

    parts = [
        f"DRIVER={{{driver}}}",
        f"SERVER={server}",
        f"DATABASE={database}",
        f"Encrypt={encrypt}",
        f"TrustServerCertificate={trust_cert}",
    ]

    if trusted_connection == "yes":
        parts.append("Trusted_Connection=yes")
    else:
        user = os.getenv("DB_USER")
        password = os.getenv("DB_PASSWORD")

        if not user or not password:
            raise RuntimeError(
                "DB_USER and DB_PASSWORD are required when DB_TRUSTED_CONNECTION=no"
            )

        parts.append(f"UID={user}")
        parts.append(f"PWD={password}")

    return pyodbc.connect(";".join(parts) + ";")


def get_engine_id_from_row(row):
    if "unit" in row.index:
        return int(row["unit"])
    if "engine_id" in row.index:
        return int(row["engine_id"])
    raise ValueError("CSV must contain unit or engine_id column")


def get_cycle_id_from_row(row):
    if "cycle" in row.index:
        return int(row["cycle"])
    if "cycle_id" in row.index:
        return int(row["cycle_id"])
    raise ValueError("CSV must contain cycle or cycle_id column")


def call_ml_server(csv_path: str):
    payload = {"csv_path": csv_path}

    response = requests.post(
        ML_SERVER_URL,
        json=payload,
        timeout=180
    )

    try:
        response_body = response.json()
    except Exception:
        response_body = {"raw_response": response.text}

    if response.status_code >= 400:
        raise RuntimeError(
            f"ML server rejected the request. "
            f"Status code: {response.status_code}. "
            f"Response: {response_body}"
        )

    return response_body


def normalize_status(status):
    if status is None:
        return "unknown"

    status = str(status).lower()

    if status in ["ok", "normal", "low"]:
        return "ok"

    if status in ["watch", "warning", "medium"]:
        return "watch"

    if status in ["critical", "high"]:
        return "critical"

    return status


def save_engine_if_not_exists(cursor, engine_id, cycle_id):
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM engine WHERE engine_id = ?)
        INSERT INTO engine (engine_id, status, rul, cycle_id)
        VALUES (?, ?, ?, ?)
    """, (
        engine_id,
        engine_id,
        "Pending",
        None,
        cycle_id
    ))


def save_engine_data_rows(cursor, df, file_reference):
    timestep_counter = {}
    last_engine_id = None
    last_cycle_id = None
    last_timestep = None

    for _, row in df.iterrows():
        engine_id = get_engine_id_from_row(row)
        cycle_id = get_cycle_id_from_row(row)

        save_engine_if_not_exists(cursor, engine_id, cycle_id)

        key = (engine_id, cycle_id)
        timestep_counter[key] = timestep_counter.get(key, 0) + 1
        timestep = timestep_counter[key]

        cursor.execute("""
            INSERT INTO engine_data (
                engine_id, cycle_id, timestep, file_path,
                alt, Mach, TRA, T2, T24, T30, T48, T50,
                P15, P2, P21, P24, Ps30, P40, P50,
                Nf, Nc, Wf
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            engine_id,
            cycle_id,
            timestep,
            file_reference,
            float(row["alt"]),
            float(row["Mach"]),
            float(row["TRA"]),
            float(row["T2"]),
            float(row["T24"]),
            float(row["T30"]),
            float(row["T48"]),
            float(row["T50"]),
            float(row["P15"]),
            float(row["P2"]),
            float(row["P21"]),
            float(row["P24"]),
            float(row["Ps30"]),
            float(row["P40"]),
            float(row["P50"]),
            float(row["Nf"]),
            float(row["Nc"]),
            float(row["Wf"])
        ))

        last_engine_id = engine_id
        last_cycle_id = cycle_id
        last_timestep = timestep

    return last_engine_id, last_cycle_id, last_timestep, timestep_counter


def save_ml_result(cursor, ml_result, data_timestep, file_reference):
    prediction_data = ml_result.get("prediction", {})
    report_data = ml_result.get("report", {})

    engine_id = prediction_data.get("unit") or report_data.get("unit")
    cycle_id = prediction_data.get("cycle") or report_data.get("cycle")
    predicted_rul = prediction_data.get("predicted_rul") or report_data.get("predicted_rul")

    risk_level_raw = report_data.get("risk_level")
    health_status = normalize_status(risk_level_raw)

    top_features = (
        prediction_data.get("top_feature_contributions")
        or prediction_data.get("all_feature_contributions")
        or []
    )
    top_features_text = json.dumps(top_features, ensure_ascii=False)

    maintenance_report = report_data.get("maintenance_report")

    cursor.execute("""
        INSERT INTO prediction (
            engine_id, cycle_id, data_timestep,
            predicted_rul, probability, health_status, top_features
        )
        OUTPUT INSERTED.prediction_id
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        engine_id,
        cycle_id,
        data_timestep,
        predicted_rul,
        None,
        health_status,
        top_features_text
    ))

    prediction_id = cursor.fetchone()[0]
    alert_created = False

    if health_status in ["watch", "critical"]:
        message = f"Engine status is {health_status}. Predicted RUL = {predicted_rul}"

        cursor.execute("""
            INSERT INTO alert (prediction_id, alert_level, message)
            VALUES (?, ?, ?)
        """, (
            prediction_id,
            health_status,
            message
        ))

        alert_created = True

    cursor.execute("""
        INSERT INTO report (
            prediction_id,
            engine_id,
            file_path,
            report_textfile
        )
        VALUES (?, ?, ?, ?)
    """, (
        prediction_id,
        engine_id,
        file_reference,
        maintenance_report
    ))

    cursor.execute("""
        UPDATE engine
        SET status = ?, rul = ?, cycle_id = ?, timestamp = GETDATE()
        WHERE engine_id = ?
    """, (
        health_status,
        predicted_rul,
        cycle_id,
        engine_id
    ))

    return {
        "prediction_id": prediction_id,
        "engine_id": engine_id,
        "cycle_id": cycle_id,
        "data_timestep": data_timestep,
        "predicted_rul": predicted_rul,
        "health_status": health_status,
        "top_features": top_features,
        "maintenance_report": maintenance_report,
        "alert_created": alert_created
    }


def process_csv_file(csv_path: Path, file_reference: str):
    csv_path = Path(csv_path).resolve()

    if not csv_path.exists():
        return {"error": "CSV file path does not exist"}

    df = pd.read_csv(str(csv_path))

    if "unit" not in df.columns and "engine_id" in df.columns:
        df["unit"] = df["engine_id"]

    if "cycle" not in df.columns and "cycle_id" in df.columns:
        df["cycle"] = df["cycle_id"]

    if "unit" not in df.columns:
        return {"error": "CSV must contain unit or engine_id column"}

    if "cycle" not in df.columns:
        return {"error": "CSV must contain cycle or cycle_id column"}

    missing_columns = [col for col in REQUIRED_COLUMNS if col not in df.columns]
    if missing_columns:
        return {
            "error": "CSV file is missing required columns",
            "missing_columns": missing_columns
        }

    df.to_csv(str(csv_path), index=False)

    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        last_engine_id, last_cycle_id, last_timestep, timestep_counter = save_engine_data_rows(
            cursor=cursor,
            df=df,
            file_reference=file_reference
        )

        ml_result = call_ml_server(str(csv_path))

        prediction_data = ml_result.get("prediction", {})
        report_data = ml_result.get("report", {})

        ml_engine_id = prediction_data.get("unit") or report_data.get("unit") or last_engine_id
        ml_cycle_id = prediction_data.get("cycle") or report_data.get("cycle") or last_cycle_id

        data_timestep = timestep_counter.get(
            (int(ml_engine_id), int(ml_cycle_id)),
            last_timestep
        )

        save_ml_result(
            cursor=cursor,
            ml_result=ml_result,
            data_timestep=data_timestep,
            file_reference=file_reference
        )

        conn.commit()

        return ml_result

    except Exception:
        if conn is not None:
            conn.rollback()
        raise

    finally:
        if conn is not None:
            conn.close()

def hash_password(password: str) -> str:
    password_bytes = password.encode("utf-8")
    hashed = bcrypt.hashpw(password_bytes, bcrypt.gensalt(rounds=12))
    return hashed.decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        password_bytes = password.encode("utf-8")
        hash_bytes = password_hash.encode("utf-8")
        return bcrypt.checkpw(password_bytes, hash_bytes)
    except Exception:
        return False
    

@app.get("/")
def read_root():
    return {
        "message": "Backend API is working",
        "app_dir": str(APP_DIR),
        "reports_folder": str(REPORTS_FOLDER)
    }

@app.post("/login")
def login_user(
    username: str = Body(...),
    password: str = Body(...)
):
    conn = None

    try:
        if not username or not password:
            return {"error": "Username and password are required"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT user_id, username, password_hash
            FROM users
            WHERE username = ?
        """, (
            username,
        ))

        row = cursor.fetchone()

        if row and verify_password(password, row.password_hash):
            cursor.execute("""
                INSERT INTO audit_log (user_id, login_time)
                VALUES (?, GETDATE())
            """, (
                row.user_id,
            ))

            conn.commit()

            return {
                "message": "Login successful",
                "user_id": row.user_id,
                "username": row.username
            }

        return {"message": "Invalid username or password"}

    except Exception as e:
        if conn is not None:
            conn.rollback()

        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


@app.get("/engines")
def get_engines():
    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM engine")
        rows = cursor.fetchall()

        result = []

        for row in rows:
            result.append({
                "engine_id": row.engine_id,
                "status": row.status,
                "rul": row.rul,
                "timestamp": str(row.timestamp),
                "cycle_id": row.cycle_id
            })

        conn.close()
        return result

    except Exception as e:
        return {"error": str(e)}


@app.post("/admin/users")
def create_user_by_admin(
    admin_username: str = Body(...),
    username: str = Body(...),
    password: str = Body(...)
):
    conn = None

    try:
        if str(admin_username).strip().lower() != "admin":
            return {"error": "Only admin can create users"}

        username = str(username).strip()

        if not username:
            return {"error": "Username is required"}

        if not password or len(password) < 6:
            return {"error": "Password must be at least 6 characters"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT user_id
            FROM users
            WHERE username = ?
        """, (username,))

        existing_user = cursor.fetchone()

        if existing_user:
            return {"error": "Username already exists"}

        password_hash = hash_password(password)

        cursor.execute("""
            INSERT INTO users (username, password_hash)
            OUTPUT INSERTED.user_id
            VALUES (?, ?)
        """, (username, password_hash))

        user_id = cursor.fetchone()[0]
        conn.commit()

        return {
            "message": "User created successfully",
            "user_id": user_id,
            "username": username
        }

    except Exception as e:
        if conn is not None:
            conn.rollback()

        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()

@app.post("/upload-csv")
def upload_csv(file: UploadFile = File(...)):
    try:
        if not file.filename:
            return {"error": "No file was uploaded"}

        file_name = Path(file.filename).name

        if not file_name.lower().endswith(".csv"):
            return {"error": "Only CSV files are allowed"}

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_csv_path = Path(temp_dir) / file_name

            with temp_csv_path.open("wb") as buffer:
                shutil.copyfileobj(file.file, buffer)

            return process_csv_file(
                csv_path=temp_csv_path,
                file_reference=file_name
            )

    except Exception as e:
        return {"error": str(e)}


@app.get("/alerts")
def get_alerts():
    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM alert")
        rows = cursor.fetchall()

        result = []

        for row in rows:
            result.append({
                "alert_id": row.alert_id,
                "prediction_id": row.prediction_id,
                "alert_level": row.alert_level,
                "message": row.message,
                "created_at": str(row.created_at),
                "is_resolved": bool(row.is_resolved)
            })

        conn.close()
        return result

    except Exception as e:
        return {"error": str(e)}

@app.post("/alerts/{alert_id}/resolve")
def resolve_alert(alert_id: int):
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT alert_id, is_resolved
            FROM alert
            WHERE alert_id = ?
        """, (
            alert_id,
        ))

        row = cursor.fetchone()

        if not row:
            return {"error": "Alert not found"}

        cursor.execute("""
            UPDATE alert
            SET is_resolved = 1
            WHERE alert_id = ?
        """, (
            alert_id,
        ))

        conn.commit()

        return {
            "message": "Alert resolved successfully",
            "alert_id": alert_id,
            "is_resolved": True
        }

    except Exception as e:
        if conn is not None:
            conn.rollback()

        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


@app.post("/alerts/{alert_id}/acknowledge")
def acknowledge_alert(alert_id: int):
    return resolve_alert(alert_id)

@app.get("/history")
def get_history():
    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT 
                prediction_id,
                engine_id,
                cycle_id,
                data_timestep,
                predicted_rul,
                health_status,
                predicted_at
            FROM prediction
            ORDER BY predicted_at DESC
        """)

        rows = cursor.fetchall()
        result = []

        for row in rows:
            result.append({
                "run_id": f"RUN-{row.prediction_id:03d}",
                "prediction_id": row.prediction_id,
                "engine_id": row.engine_id,
                "cycle_id": row.cycle_id,
                "data_timestep": row.data_timestep,
                "predicted_rul": row.predicted_rul,
                "status": row.health_status,
                "time": str(row.predicted_at)
            })

        conn.close()
        return result

    except Exception as e:
        return {"error": str(e)}
    

def get_prediction_result_data(cursor, prediction_id: int):
    cursor.execute("""
        SELECT 
            p.prediction_id,
            p.engine_id,
            p.cycle_id,
            p.data_timestep,
            p.predicted_rul,
            p.health_status,
            p.top_features,
            p.predicted_at,
            r.report_textfile
        FROM prediction p
        LEFT JOIN report r ON p.prediction_id = r.prediction_id
        WHERE p.prediction_id = ?
    """, (
        prediction_id,
    ))

    row = cursor.fetchone()

    if not row:
        return None

    return {
        "prediction_id": row.prediction_id,
        "engine_id": row.engine_id,
        "cycle_id": row.cycle_id,
        "data_timestep": row.data_timestep,
        "predicted_rul": row.predicted_rul,
        "status": row.health_status,
        "top_features": json.loads(row.top_features) if row.top_features else [],
        "predicted_at": str(row.predicted_at),
        "report_textfile": row.report_textfile
    }

@app.get("/results/{prediction_id}")
def get_result_details(prediction_id: int):
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        result = get_prediction_result_data(cursor, prediction_id)

        if not result:
            return {"error": "Prediction result not found"}

        return result

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


@app.get("/dashboard-summary")
def dashboard_summary():
    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM engine WHERE status = 'ok'")
        ok_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM engine WHERE status = 'watch'")
        watch_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM engine WHERE status = 'critical'")
        critical_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM alert WHERE is_resolved = 0")
        active_alerts = cursor.fetchone()[0]

        conn.close()

        return {
            "fleet_health": {
                "ok": ok_count,
                "watch": watch_count,
                "critical": critical_count
            },
            "active_alerts": active_alerts
        }

    except Exception as e:
        return {"error": str(e)}

def clean_pdf_text(value):
    if value is None:
        return ""

    text = str(value)

    replacements = {
        "\u00a0": " ",   # non-breaking space
        "\u202f": " ",   # narrow non-breaking space
        "\u2007": " ",   # figure space
        "\u2009": " ",   # thin space
        "\u200a": " ",   # hair space
        "\u200b": "",    # zero-width space
        "\u2060": "",    # word joiner
        "\ufeff": "",    # BOM

        "\u2010": "-",   # hyphen
        "\u2011": "-",   # non-breaking hyphen
        "\u2012": "-",   # figure dash
        "\u2013": "-",   # en dash
        "\u2014": "-",   # em dash
        "\u2212": "-",   # minus sign

        "\u2018": "'",   # left single quote
        "\u2019": "'",   # right single quote
        "\u201c": '"',   # left double quote
        "\u201d": '"',   # right double quote

        "\u2026": "...", 
        "\u2248": "approximately",
        "\u2264": "<=",
        "\u2265": ">=",
        "\u2022": "-",
    }

    for bad, good in replacements.items():
        text = text.replace(bad, good)

    return text

def generate_report_pdf(result: dict) -> Path:
    REPORTS_FOLDER.mkdir(parents=True, exist_ok=True)

    pdf_file_name = (
        f"report_engine_{result['engine_id']}"
        f"_cycle_{result['cycle_id']}"
        f"_timestep_{result['data_timestep']}"
        f"_prediction_{result['prediction_id']}.pdf"
    )

    pdf_path = REPORTS_FOLDER / pdf_file_name

    c = canvas.Canvas(str(pdf_path), pagesize=A4)
    width, height = A4

    left_margin = 55
    right_margin = 55
    top_margin = 50
    bottom_margin = 60
    content_width = width - left_margin - right_margin

    title_font = "Helvetica-Bold"
    title_size = 24

    header_font = "Helvetica-Bold"
    header_size = 20

    section_font = "Helvetica-Bold"
    section_size = 16

    body_font = "Helvetica"
    body_size = 11

    meta_font = "Helvetica"
    meta_size = 10

    body_line_height = 15
    section_line_height = 18

    section_headings = {
        "Executive Summary",
        "Engine Performance Analysis",
        "Critical Findings",
        "Risk Classification Assessment",
        "Review Focus",
        "Recommendations and Action Items",
        "Conclusion",
    }

    def new_page():
        c.showPage()
        return height - top_margin

    def ensure_space(y_value, needed_space):
        if y_value - needed_space < bottom_margin:
            return new_page()
        return y_value

    def wrap_text(text, font_name, font_size, max_width):
        words = clean_pdf_text(text).split()
        lines = []
        current_line = ""

        for word in words:
            test_line = f"{current_line} {word}".strip()

            if c.stringWidth(test_line, font_name, font_size) <= max_width:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word

        if current_line:
            lines.append(current_line)

        return lines

    def draw_justified_line(line, y_value, font_name, font_size, max_width):
        words = line.split()

        c.setFont(font_name, font_size)

        if len(words) <= 1:
            c.drawString(left_margin, y_value, line)
            return

        total_words_width = sum(c.stringWidth(word, font_name, font_size) for word in words)
        space_count = len(words) - 1
        extra_space = (max_width - total_words_width) / space_count

        x = left_margin

        for index, word in enumerate(words):
            c.drawString(x, y_value, word)
            word_width = c.stringWidth(word, font_name, font_size)

            if index < len(words) - 1:
                x += word_width + extra_space

    def draw_paragraph(text, y_value):
        text = clean_pdf_text(text).strip()

        if not text:
            return y_value - 6

        lines = wrap_text(
            text=text,
            font_name=body_font,
            font_size=body_size,
            max_width=content_width
        )

        for index, line in enumerate(lines):
            y_value = ensure_space(y_value, body_line_height)

            is_last_line = index == len(lines) - 1

            if is_last_line:
                c.setFont(body_font, body_size)
                c.drawString(left_margin, y_value, line)
            else:
                draw_justified_line(
                    line=line,
                    y_value=y_value,
                    font_name=body_font,
                    font_size=body_size,
                    max_width=content_width
                )

            y_value -= body_line_height

        return y_value - 3

    y = height - top_margin

    c.setFont(title_font, title_size)
    c.drawString(left_margin, y, "Aircraft Engine Health Report")

    y -= 35

    metadata_lines = [
        f"Prediction ID: {result['prediction_id']}",
        f"Engine ID: {result['engine_id']}",
        f"Cycle ID: {result['cycle_id']}",
        f"Data Timestep: {result['data_timestep']}",
        f"Predicted RUL: {result['predicted_rul']}",
        f"Status: {result['status']}",
        f"Prediction Time: {result['predicted_at']}",
    ]

    for item in metadata_lines:
        y = ensure_space(y, 20)
        c.setFont(meta_font, meta_size)
        c.drawString(left_margin, y, clean_pdf_text(item))
        y -= 18

    y -= 18

    y = ensure_space(y, 25)
    c.setFont(header_font, header_size)
    c.drawString(left_margin, y, "Maintenance Report")
    y -= 26

    report_text = clean_pdf_text(
        result.get("report_textfile") or "No report text available."
    )

    for raw_line in report_text.split("\n"):
        line = clean_pdf_text(raw_line).strip()

        if not line:
            y -= 6
            continue

        if line in section_headings:
            y -= 8
            y = ensure_space(y, section_line_height + 8)

            c.setFont(section_font, section_size)
            c.drawString(left_margin, y, line)

            y -= section_line_height
            y -= 4
        else:
            y = draw_paragraph(line, y)

    c.save()

    return pdf_path



@app.post("/export-report")
def export_report(prediction_id: int):
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        result = get_prediction_result_data(cursor, prediction_id)

        if not result:
            return {"error": "Prediction report not found"}

        pdf_path = generate_report_pdf(result)

        return {
            "message": "Report exported successfully",
            "prediction_id": result["prediction_id"],
            "engine_id": result["engine_id"],
            "cycle_id": result["cycle_id"],
            "data_timestep": result["data_timestep"],
            "pdf_path": str(pdf_path)
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


def parse_email_list(value):
    if value is None:
        return []

    if isinstance(value, list):
        items = value
    else:
        items = str(value).split(",")

    emails = []

    for item in items:
        email = str(item).strip()

        if email:
            emails.append(email)

    return emails


def validate_email_list(emails, field_name):
    for email in emails:
        if "@" not in email or "." not in email.split("@")[-1]:
            raise RuntimeError(f"Invalid {field_name} email address: {email}")


def send_pdf_email_to_maintenance(
    result: dict,
    pdf_path: Path,
    recipient_emails_override=None,
    cc_emails_override=None
):
    default_recipients = parse_email_list(os.getenv("MAINTENANCE_EMAIL"))
    default_cc = parse_email_list(os.getenv("MAINTENANCE_CC"))

    recipient_emails = parse_email_list(recipient_emails_override)

    if not recipient_emails:
        recipient_emails = default_recipients

    cc_emails = parse_email_list(cc_emails_override)

    if not cc_emails:
        cc_emails = default_cc

    if not recipient_emails:
        raise RuntimeError(
            "No maintenance recipient emails were provided and MAINTENANCE_EMAIL is missing from .env"
        )

    validate_email_list(recipient_emails, "recipient")
    validate_email_list(cc_emails, "CC")

    smtp_host = os.getenv("SMTP_HOST")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_use_tls = os.getenv("SMTP_USE_TLS", "true").lower() == "true"
    smtp_use_ssl = os.getenv("SMTP_USE_SSL", "false").lower() == "true"
    smtp_user = os.getenv("SMTP_USER")
    smtp_password = os.getenv("SMTP_PASSWORD")
    smtp_from = os.getenv("SMTP_FROM") or smtp_user

    if not smtp_host:
        raise RuntimeError("SMTP_HOST is missing from .env")

    if not smtp_from:
        raise RuntimeError("SMTP_FROM or SMTP_USER is missing from .env")

    subject = (
        f"[{str(result['status']).upper()}] "
        f"Engine {result['engine_id']} Maintenance Report "
        f"- Prediction {result['prediction_id']}"
    )

    body = f"""
Hello Maintenance Team,

A new aircraft engine health report has been generated and requires review.

Engine ID: {result['engine_id']}
Cycle ID: {result['cycle_id']}
Data Timestep: {result['data_timestep']}
Predicted RUL: {result['predicted_rul']}
Status: {result['status']}
Prediction Time: {result['predicted_at']}

The full maintenance report is attached as a PDF.

Regards,
Aircraft Engine Health System
""".strip()

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = smtp_from
    message["To"] = ", ".join(recipient_emails)

    if cc_emails:
        message["Cc"] = ", ".join(cc_emails)

    message.set_content(body)

    with pdf_path.open("rb") as file:
        message.add_attachment(
            file.read(),
            maintype="application",
            subtype="pdf",
            filename=pdf_path.name
        )

    all_recipients = recipient_emails + cc_emails

    context = ssl.create_default_context()

    if smtp_use_ssl:
        with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context, timeout=30) as server:
            if smtp_user and smtp_password:
                server.login(smtp_user, smtp_password)
            server.send_message(message, to_addrs=all_recipients)
    else:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
            if smtp_use_tls:
                server.starttls(context=context)
            if smtp_user and smtp_password:
                server.login(smtp_user, smtp_password)
            server.send_message(message, to_addrs=all_recipients)

    return {
        "to": recipient_emails,
        "cc": cc_emails
    }

@app.post("/send-to-maintenance/{prediction_id}")
def send_to_maintenance(
    prediction_id: int,
    recipient_emails: list[str] | None = Body(default=None),
    cc_emails: list[str] | None = Body(default=None)
):
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        result = get_prediction_result_data(cursor, prediction_id)

        if not result:
            return {"error": "Prediction result not found"}

        pdf_path = generate_report_pdf(result)

        sent_to = send_pdf_email_to_maintenance(
            result=result,
            pdf_path=pdf_path,
            recipient_emails_override=recipient_emails,
            cc_emails_override=cc_emails
        )

        return {
            "message": "Report PDF sent to maintenance successfully",
            "prediction_id": result["prediction_id"],
            "engine_id": result["engine_id"],
            "cycle_id": result["cycle_id"],
            "status": result["status"],
            "sent_to": sent_to["to"],
            "cc": sent_to["cc"],
            "pdf_path": str(pdf_path)
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


@app.get("/results/{prediction_id}/decreasing-sensor-trends")
def get_decreasing_sensor_trends(prediction_id: int):
    conn = None

    allowed_columns = {
        "alt", "Mach", "TRA", "T2", "T24", "T30", "T48", "T50",
        "P15", "P2", "P21", "P24", "Ps30", "P40", "P50",
        "Nf", "Nc", "Wf"
    }

    try:
        conn = get_connection()
        cursor = conn.cursor()

        result = get_prediction_result_data(cursor, prediction_id)

        if not result:
            return {"error": "Prediction result not found"}

        decreasing_features = []

        for item in result.get("top_features", []):
            feature = item.get("feature")
            effect = str(item.get("effect", "")).lower()

            if (
                feature in allowed_columns
                and "decrease" in effect
            ):
                decreasing_features.append(feature)

        if not decreasing_features:
            return {
                "prediction_id": prediction_id,
                "engine_id": result["engine_id"],
                "cycle_id": result["cycle_id"],
                "decreasing_features": [],
                "series": []
            }

        selected_columns = ", ".join(f"[{feature}]" for feature in decreasing_features)

        query = f"""
            SELECT 
                timestep,
                {selected_columns}
            FROM engine_data
            WHERE engine_id = ?
              AND cycle_id = ?
              AND timestep <= ?
            ORDER BY timestep ASC
        """

        cursor.execute(query, (
            result["engine_id"],
            result["cycle_id"],
            result["data_timestep"]
        ))

        rows = cursor.fetchall()

        series = []

        for row in rows:
            point = {
                "timestep": row.timestep
            }

            for feature in decreasing_features:
                point[feature] = getattr(row, feature)

            series.append(point)

        return {
            "prediction_id": prediction_id,
            "engine_id": result["engine_id"],
            "cycle_id": result["cycle_id"],
            "data_timestep": result["data_timestep"],
            "decreasing_features": decreasing_features,
            "series": series
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()

@app.get("/dashboard/fleet-health-trend")
def dashboard_fleet_health_trend(days: int = 30):
    from datetime import date, datetime, timedelta

    conn = None

    try:
        if days < 1:
            days = 30

        if days > 365:
            days = 365

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT CAST(MAX(predicted_at) AS date)
            FROM prediction
        """)

        max_date_value = cursor.fetchone()[0]

        if max_date_value is None:
            return {
                "days": days,
                "trend_type": "daily_fleet_health_snapshot",
                "series": []
            }

        if isinstance(max_date_value, datetime):
            end_date = max_date_value.date()
        elif isinstance(max_date_value, date):
            end_date = max_date_value
        else:
            end_date = datetime.fromisoformat(str(max_date_value)[:10]).date()

        start_date = end_date - timedelta(days=days - 1)

        series = []

        for offset in range(days):
            current_date = start_date + timedelta(days=offset)
            next_date = current_date + timedelta(days=1)

            next_date_string = next_date.strftime("%Y-%m-%d")

            cursor.execute("""
                WITH latest_per_engine AS (
                    SELECT
                        engine_id,
                        LOWER(health_status) AS health_status,
                        ROW_NUMBER() OVER (
                            PARTITION BY engine_id
                            ORDER BY predicted_at DESC, prediction_id DESC
                        ) AS rn
                    FROM prediction
                    WHERE predicted_at < ?
                )
                SELECT
                    SUM(CASE WHEN health_status = 'ok' THEN 1 ELSE 0 END) AS ok_count,
                    SUM(CASE WHEN health_status = 'watch' THEN 1 ELSE 0 END) AS watch_count,
                    SUM(CASE WHEN health_status = 'critical' THEN 1 ELSE 0 END) AS critical_count
                FROM latest_per_engine
                WHERE rn = 1
            """, (
                next_date_string,
            ))

            row = cursor.fetchone()

            ok_count = int(row[0] or 0)
            watch_count = int(row[1] or 0)
            critical_count = int(row[2] or 0)

            series.append({
                "date": current_date.isoformat(),
                "ok": ok_count,
                "watch": watch_count,
                "critical": critical_count,
                "total": ok_count + watch_count + critical_count
            })

        return {
            "days": days,
            "trend_type": "daily_fleet_health_snapshot",
            "series": series
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()

@app.get("/analytics/predictions-this-month")
def analytics_predictions_this_month():
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                COUNT(*) AS predictions_this_month,
                COUNT(DISTINCT engine_id) AS engines_this_month
            FROM prediction
            WHERE predicted_at >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
              AND predicted_at < DATEADD(
                    MONTH,
                    1,
                    DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
              )
        """)

        row = cursor.fetchone()

        return {
            "predictions_this_month": int(row.predictions_this_month or 0),
            "engines_this_month": int(row.engines_this_month or 0)
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()

@app.get("/analytics/filter-options")
def analytics_filter_options():
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT DISTINCT engine_id, cycle_id
            FROM engine_data
            ORDER BY engine_id ASC, cycle_id ASC
        """)

        rows = cursor.fetchall()

        engines = []
        cycles_by_engine = {}

        for row in rows:
            engine_id = int(row.engine_id)
            cycle_id = int(row.cycle_id)

            if engine_id not in cycles_by_engine:
                cycles_by_engine[engine_id] = []
                engines.append(engine_id)

            cycles_by_engine[engine_id].append(cycle_id)

        cycles_by_engine_string_keys = {
            str(engine_id): cycles
            for engine_id, cycles in cycles_by_engine.items()
        }

        return {
            "engines": engines,
            "cycles_by_engine": cycles_by_engine_string_keys
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()

@app.get("/analytics/sensor-groups")
def analytics_sensor_groups(
    engine_id: int,
    cycle_id: int
):
    conn = None

    sensor_groups = {
        "temperature": ["T2", "T24", "T30", "T48", "T50"],
        "pressure": ["P15", "P2", "P21", "P24", "Ps30", "P40", "P50"],
        "speed": ["Nf", "Nc"],
        "fuel": ["Wf"],
        "operating_context": ["alt", "Mach", "TRA"]
    }

    all_columns = []

    for columns in sensor_groups.values():
        all_columns.extend(columns)

    try:
        conn = get_connection()
        cursor = conn.cursor()

        selected_columns = ", ".join(f"[{col}]" for col in all_columns)

        query = f"""
            SELECT
                timestep,
                {selected_columns}
            FROM engine_data
            WHERE engine_id = ?
              AND cycle_id = ?
            ORDER BY timestep ASC
        """

        cursor.execute(query, (
            engine_id,
            cycle_id
        ))

        rows = cursor.fetchall()

        timesteps = []

        series = {}

        for group_name, feature_names in sensor_groups.items():
            series[group_name] = {}

            for feature in feature_names:
                series[group_name][feature] = []

        for row in rows:
            timesteps.append(row.timestep)

            for group_name, feature_names in sensor_groups.items():
                for feature in feature_names:
                    value = getattr(row, feature)

                    if value is None:
                        series[group_name][feature].append(None)
                    else:
                        series[group_name][feature].append(float(value))

        return {
            "engine_id": engine_id,
            "cycle_id": cycle_id,
            "row_count": len(timesteps),
            "timesteps": timesteps,
            "series": series
        }

    except Exception as e:
        return {"error": str(e)}

    finally:
        if conn is not None:
            conn.close()


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=BACKEND_HOST,
        port=BACKEND_PORT,
        reload=False,
        log_config=None,
        access_log=False
    )