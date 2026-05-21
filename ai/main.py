from __future__ import annotations

from pathlib import Path
import sys
import os
from dotenv import load_dotenv


def get_app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


APP_DIR = get_app_dir()
ENV_PATH = APP_DIR / ".env"
load_dotenv(ENV_PATH, override=True)

def setup_stdio_for_noconsole():
    if not getattr(sys, "frozen", False):
        return

    logs_dir = APP_DIR / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    if sys.stdout is None:
        sys.stdout = open(
            logs_dir / "model_api_stdout.log",
            "a",
            encoding="utf-8",
            buffering=1
        )

    if sys.stderr is None:
        sys.stderr = open(
            logs_dir / "model_api_stderr.log",
            "a",
            encoding="utf-8",
            buffering=1
        )


setup_stdio_for_noconsole()
import os
import time
import threading
import ctypes
from functools import lru_cache
from typing import Any, Dict, List

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from rul_model_service import BiLSTMServingService
from llm_report_service import RULReportGenerator


def is_process_alive_windows(pid: int) -> bool:
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    SYNCHRONIZE = 0x00100000
    WAIT_TIMEOUT = 0x00000102

    kernel32 = ctypes.windll.kernel32

    handle = kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
        False,
        pid
    )

    if not handle:
        return False

    try:
        result = kernel32.WaitForSingleObject(handle, 0)
        return result == WAIT_TIMEOUT
    finally:
        kernel32.CloseHandle(handle)


def is_process_alive(pid: int) -> bool:
    if pid <= 0:
        return False

    if os.name == "nt":
        return is_process_alive_windows(pid)

    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def start_backend_parent_watchdog():
    parent_pid_raw = os.getenv("BACKEND_PARENT_PID")

    if not parent_pid_raw:
        return

    try:
        parent_pid = int(parent_pid_raw)
    except ValueError:
        return

    def watchdog_loop():
        while True:
            time.sleep(2)

            if not is_process_alive(parent_pid):
                os._exit(0)

    thread = threading.Thread(
        target=watchdog_loop,
        daemon=True
    )
    thread.start()


start_backend_parent_watchdog()

class PredictAndReportRequest(BaseModel):
    csv_path: str


@lru_cache(maxsize=1)
def get_rul_service():

    artifact_dir_env = os.environ.get("ARTIFACT_DIR")

    if artifact_dir_env:
        artifact_path = Path(artifact_dir_env)

        if not artifact_path.is_absolute():
            artifact_path = APP_DIR / artifact_path
    else:
        artifact_path = APP_DIR / "Model"

    device = os.environ.get("TORCH_DEVICE")
    mc_passes = int(os.environ.get("MC_PASSES", "5"))

    return BiLSTMServingService(
        artifact_dir=str(artifact_path),
        device=device,
        mc_passes=mc_passes,
    )

@lru_cache(maxsize=1)
def get_report_generator() -> RULReportGenerator:
    return RULReportGenerator()


def run_rul_prediction(csv_path: str) -> Dict[str, Any]:
    service = get_rul_service()
    return service.predict_from_csv_path(csv_path=csv_path)


def run_llm_report(prediction_json: Dict[str, Any]) -> Dict[str, Any]:
    generator = get_report_generator()
    return generator.generate_report(prediction_json)


def top_n_feature_contributions(
    all_feature_contributions: List[Dict[str, Any]],
    n: int = 5,
) -> List[Dict[str, Any]]:
    return sorted(
        all_feature_contributions,
        key=lambda item: float(item.get("abs_shap_value", 0.0)),
        reverse=True,
    )[:n]


def build_frontend_prediction(prediction_json: Dict[str, Any]) -> Dict[str, Any]:
    all_features = prediction_json.get("all_feature_contributions", [])
    top_features = top_n_feature_contributions(all_features, n=5)

    return {
        "unit": prediction_json["unit"],
        "cycle": prediction_json["cycle"],
        "input_rows": prediction_json["input_rows"],
        "predicted_rul": prediction_json["predicted_rul"],
        "top_feature_contributions": top_features,
    }


def build_frontend_report(report_json: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "unit": report_json["unit"],
        "cycle": report_json["cycle"],
        "predicted_rul": report_json["predicted_rul"],
        "risk_level": report_json["risk_level"],
        "maintenance_report": report_json["maintenance_report"],
        "recommendation": report_json["recommendation"],
        "report_source": report_json.get("report_source", "unknown"),
    }


app = FastAPI(
    title="BiLSTM RUL Prediction and LLM Maintenance Report API",
    version="2.6.0",
)


@app.get("/", include_in_schema=False)
def root() -> Dict[str, Any]:
    return {
        "status": "running",
        "docs": "/docs",
        "endpoint": "/predict/rul/report",
    }


@app.get("/health", include_in_schema=False)
def health() -> Dict[str, str]:
    return {
        "status": "ok",
    }


@app.post("/predict/rul/report")
def predict_rul_and_generate_report(request: PredictAndReportRequest) -> Dict[str, Any]:
    try:
        full_prediction_json = run_rul_prediction(csv_path=request.csv_path)

        report_json = run_llm_report(full_prediction_json)

        frontend_prediction_json = build_frontend_prediction(full_prediction_json)
        frontend_report_json = build_frontend_report(report_json)

        return {
            "prediction": frontend_prediction_json,
            "report": frontend_report_json,
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


if __name__ == "__main__":
    host = os.environ.get("API_HOST", "127.0.0.1")
    port = int(os.environ.get("API_PORT", "9000"))
    reload = os.environ.get("API_RELOAD", "false").lower() == "true"
    uvicorn.run(
        app,
        host=host,
        port=port,
        reload=reload,
    )
