from __future__ import annotations

import json
import math
import os
import pickle
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.nn.utils.rnn import pack_padded_sequence, pad_packed_sequence

try:
    import shap
except Exception:
    shap = None

RUL_CAP_DEFAULT = 99.0
BASE_FEATURE_COLS = [
    "alt", "Mach", "TRA", "T2",
    "T24", "T30", "T48", "T50",
    "P15", "P2", "P21", "P24", "Ps30", "P40", "P50",
    "Nf", "Nc", "Wf",
]
DEFAULT_FEATURE_COLS = BASE_FEATURE_COLS + ["cycle_norm"]


def get_activation(name: str = "gelu") -> nn.Module:
    name = name.lower()
    if name == "relu":
        return nn.ReLU()
    if name == "gelu":
        return nn.GELU()
    if name == "silu":
        return nn.SiLU()
    raise ValueError(f"Unsupported activation: {name}")


class BiLSTMRegressor(nn.Module):
    def __init__(
        self,
        input_size: int,
        hidden_size: int = 128,
        num_layers: int = 4,
        dropout: float = 0.2,
        bidirectional: bool = True,
        activation_name: str = "gelu",
        rul_cap: float = RUL_CAP_DEFAULT,
    ) -> None:
        super().__init__()
        self.rul_cap = float(rul_cap)
        self.input_norm = nn.LayerNorm(input_size)
        self.bidirectional = bidirectional
        self.hidden_size = hidden_size
        self.num_directions = 2 if bidirectional else 1
        lstm_output_size = hidden_size * self.num_directions
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0.0,
            bidirectional=bidirectional,
        )
        self.post_lstm_norm = nn.LayerNorm(lstm_output_size)
        pooled_size = lstm_output_size * 2
        self.head = nn.Sequential(
            nn.Linear(pooled_size, 128),
            get_activation(activation_name),
            nn.Dropout(dropout),
            nn.Linear(128, 64),
            get_activation(activation_name),
            nn.Dropout(dropout),
            nn.Linear(64, 1),
        )

    def forward(self, x: torch.Tensor, lengths: torch.Tensor) -> torch.Tensor:
        x = self.input_norm(x)
        packed = pack_padded_sequence(
            x,
            lengths.detach().cpu(),
            batch_first=True,
            enforce_sorted=True,
        )
        packed_out, _ = self.lstm(packed)
        out, _ = pad_packed_sequence(packed_out, batch_first=True)
        out = self.post_lstm_norm(out)
        _, max_len, _ = out.shape
        mask = torch.arange(max_len, device=out.device).unsqueeze(0) < lengths.unsqueeze(1)
        mask = mask.unsqueeze(-1)
        out_masked = out.masked_fill(~mask, 0.0)
        mean_pool = out_masked.sum(dim=1) / lengths.unsqueeze(1).clamp(min=1)
        max_pool = out.masked_fill(~mask, -1e9).max(dim=1).values
        pooled = torch.cat([mean_pool, max_pool], dim=1)
        preds = self.head(pooled).squeeze(-1)
        return torch.clamp(preds, min=0.0, max=self.rul_cap)


class FixedLengthShapWrapper(nn.Module):
    def __init__(self, model: BiLSTMRegressor, fixed_length: int) -> None:
        super().__init__()
        self.model = model
        self.fixed_length = int(fixed_length)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        lengths = torch.full(
            (x.shape[0],),
            self.fixed_length,
            dtype=torch.long,
            device=x.device,
        )
        return self.model(x, lengths).unsqueeze(-1)


@dataclass(frozen=True)
class ServingConfig:
    artifact_dir: Path
    model_path: Path
    scaler_path: Path
    config_path: Path
    metrics_path: Path
    device: torch.device
    feature_cols: List[str]
    base_feature_cols: List[str]
    max_len: int
    train_cycle_max: float
    rul_cap: float
    test_mae: float
    test_low_rul_mae_20: float
    test_high_rul_mae_70: float
    mc_passes: int


def _read_config(config_path: Path, checkpoint_config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    if config_path.exists():
        with config_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    if checkpoint_config:
        return checkpoint_config
    raise FileNotFoundError(f"Missing config file: {config_path}")


def _build_model(config: Dict[str, Any]) -> BiLSTMRegressor:
    feature_cols = config.get("feature_cols", DEFAULT_FEATURE_COLS)
    return BiLSTMRegressor(
        input_size=len(feature_cols),
        hidden_size=int(config.get("hidden_size", 128)),
        num_layers=int(config.get("num_layers", 4)),
        dropout=float(config.get("dropout", 0.2)),
        bidirectional=bool(config.get("bidirectional", True)),
        activation_name=str(config.get("activation", "gelu")),
        rul_cap=float(config.get("rul_cap", RUL_CAP_DEFAULT)),
    )


def _load_error_metrics(metrics_path: Path) -> Dict[str, float]:
    defaults = {
        "test_mae": 6.151422313620559,
        "test_low_rul_mae_20": 2.9910761281684204,
        "test_high_rul_mae_70": 8.113162465842374,
    }
    if not metrics_path.exists():
        return defaults
    metrics_df = pd.read_csv(metrics_path)
    if metrics_df.empty:
        return defaults
    row = metrics_df.iloc[0]
    return {
        "test_mae": float(row.get("test_MAE", defaults["test_mae"])),
        "test_low_rul_mae_20": float(row.get("test_LowRUL_MAE@20", defaults["test_low_rul_mae_20"])),
        "test_high_rul_mae_70": float(row.get("test_HighRUL_MAE@70", defaults["test_high_rul_mae_70"])),
    }


def resample_sequence(seq_array: np.ndarray, max_len: int) -> tuple[np.ndarray, int]:
    length = len(seq_array)
    if length == 0:
        raise ValueError("Encountered an empty sequence.")
    if length <= max_len:
        return seq_array.astype(np.float32), length
    idx = np.linspace(0, length - 1, num=max_len, dtype=np.int64)
    return seq_array[idx].astype(np.float32), max_len


def _enable_dropout_only(model: nn.Module) -> None:
    model.eval()
    for module in model.modules():
        if isinstance(module, nn.Dropout):
            module.train()
        if isinstance(module, nn.LSTM):
            module.train()


class BiLSTMServingService:
    def __init__(
        self,
        artifact_dir: str | os.PathLike[str],
        device: Optional[str] = None,
        mc_passes: int = 5,
    ) -> None:
        artifact_dir = Path(artifact_dir)
        model_path = artifact_dir / "bilstm_4layer_gelu_cycle_norm_model.pt"
        scaler_path = artifact_dir / "bilstm_4layer_gelu_cycle_norm_scaler.pkl"
        config_path = artifact_dir / "bilstm_4layer_gelu_cycle_norm_config.json"
        metrics_path = artifact_dir / "bilstm_4layer_gelu_cycle_norm_metrics.csv"
        self.device = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
        if not model_path.exists():
            raise FileNotFoundError(f"Missing model artifact: {model_path}")
        if not scaler_path.exists():
            raise FileNotFoundError(f"Missing scaler artifact: {scaler_path}")
        checkpoint = torch.load(model_path, map_location=self.device)
        config = _read_config(config_path, checkpoint.get("config") if isinstance(checkpoint, dict) else None)
        self.model = _build_model(config).to(self.device)
        state_dict = checkpoint.get("model_state_dict", checkpoint) if isinstance(checkpoint, dict) else checkpoint
        self.model.load_state_dict(state_dict)
        self.model.eval()
        with scaler_path.open("rb") as f:
            self.scaler = pickle.load(f)
        error_metrics = _load_error_metrics(metrics_path)
        self.config = ServingConfig(
            artifact_dir=artifact_dir,
            model_path=model_path,
            scaler_path=scaler_path,
            config_path=config_path,
            metrics_path=metrics_path,
            device=self.device,
            feature_cols=list(config.get("feature_cols", DEFAULT_FEATURE_COLS)),
            base_feature_cols=list(config.get("base_feature_cols", BASE_FEATURE_COLS)),
            max_len=int(config.get("max_len", 400)),
            train_cycle_max=float(config.get("train_cycle_max")),
            rul_cap=float(config.get("rul_cap", RUL_CAP_DEFAULT)),
            test_mae=float(error_metrics["test_mae"]),
            test_low_rul_mae_20=float(error_metrics["test_low_rul_mae_20"]),
            test_high_rul_mae_70=float(error_metrics["test_high_rul_mae_70"]),
            mc_passes=int(mc_passes),
        )

    def _preprocess_csv(self, csv_path: str | os.PathLike[str]) -> Dict[str, Any]:
        df = pd.read_csv(csv_path)
        required_cols = ["unit", "cycle"] + self.config.base_feature_cols
        missing = [c for c in required_cols if c not in df.columns]
        if missing:
            raise ValueError(f"CSV is missing required columns: {missing}")
        if "timestep" not in df.columns:
            df["timestep"] = np.arange(len(df), dtype=np.int32)
        df = df.sort_values(["unit", "cycle", "timestep"]).reset_index(drop=True)
        operating_condition_summary = self._feature_summary(df, ["alt", "Mach", "TRA"])
        sensor_cols = [c for c in self.config.base_feature_cols if c not in {"alt", "Mach", "TRA"}]
        sensor_summary = self._feature_summary(df, sensor_cols)
        df["cycle_norm"] = (
            df["cycle"].astype(np.float32) / self.config.train_cycle_max
        ).clip(0.0, 1.5).astype(np.float32)
        df[self.config.feature_cols] = self.scaler.transform(
            df[self.config.feature_cols].values
        ).astype(np.float32)
        seq = df[self.config.feature_cols].values.astype(np.float32)
        seq, true_len = resample_sequence(seq, self.config.max_len)
        last_row = df.iloc[-1]
        return {
            "unit": int(last_row["unit"]),
            "cycle": int(last_row["cycle"]),
            "sequence": seq,
            "length": int(true_len),
            "input_rows": int(len(df)),
            "operating_condition_summary": operating_condition_summary,
            "sensor_summary": sensor_summary,
        }

    def _feature_summary(self, df: pd.DataFrame, cols: List[str]) -> Dict[str, Dict[str, float]]:
        summary: Dict[str, Dict[str, float]] = {}
        for col in cols:
            if col not in df.columns:
                continue
            values = pd.to_numeric(df[col], errors="coerce").dropna()
            if values.empty:
                continue
            summary[col] = {
                "mean": round(float(values.mean()), 6),
                "min": round(float(values.min()), 6),
                "max": round(float(values.max()), 6),
                "std": round(float(values.std(ddof=0)), 6),
            }
        return summary

    def _select_error_margin(self, predicted_rul: float) -> float:
        if predicted_rul <= 20.0:
            return self.config.test_low_rul_mae_20
        if predicted_rul >= 70.0:
            return self.config.test_high_rul_mae_70
        return self.config.test_mae

    def _rul_error_context(self, predicted_rul: float) -> Dict[str, Any]:
        if predicted_rul <= 20.0:
            return {
                "metric_name": "test_LowRUL_MAE@20",
                "mae_cycles": round(float(self.config.test_low_rul_mae_20), 3),
                "rul_range": "predicted_rul <= 20",
            }
        if predicted_rul >= 70.0:
            return {
                "metric_name": "test_HighRUL_MAE@70",
                "mae_cycles": round(float(self.config.test_high_rul_mae_70), 3),
                "rul_range": "predicted_rul >= 70",
            }
        return {
            "metric_name": "test_MAE",
            "mae_cycles": round(float(self.config.test_mae), 3),
            "rul_range": "20 < predicted_rul < 70",
        }

    @torch.no_grad()
    def _predict(self, x: torch.Tensor, lengths: torch.Tensor) -> Dict[str, float]:
        preds: List[float] = []
        _enable_dropout_only(self.model)
        for _ in range(max(1, self.config.mc_passes)):
            preds.append(float(self.model(x, lengths).detach().cpu().item()))
        self.model.eval()
        mean_pred = float(np.mean(preds))
        internal_mc_std = float(np.std(preds, ddof=1)) if len(preds) > 1 else 0.0
        error_margin = self._select_error_margin(mean_pred)
        confidence = 100.0 * math.exp(-internal_mc_std / max(error_margin, 1e-6))
        confidence = max(0.0, min(100.0, confidence))
        return {
            "predicted_rul": mean_pred,
            "confidence": confidence,
        }

    def _shap_feature_contributions(self, x: torch.Tensor, length: int) -> List[Dict[str, Any]]:
        if shap is None:
            raise RuntimeError("SHAP is not installed. Install it with: pip install shap")
        self.model.eval()
        background = torch.zeros((4, length, x.shape[-1]), dtype=x.dtype, device=x.device)
        wrapped = FixedLengthShapWrapper(self.model, fixed_length=length).to(x.device)
        wrapped.eval()
        explainer = shap.GradientExplainer(wrapped, background)
        shap_values = explainer.shap_values(x, nsamples=20)
        if isinstance(shap_values, list):
            shap_values = shap_values[0]
        values = np.asarray(shap_values)
        if values.ndim == 4:
            values = values[0, :, :, 0]
        elif values.ndim == 3:
            values = values[0]
        elif values.ndim == 2:
            pass
        else:
            raise RuntimeError(f"Unexpected SHAP value shape: {values.shape}")
        signed_by_feature = values.sum(axis=0)
        abs_by_feature = np.abs(values).sum(axis=0)
        valid_indices = [
            idx for idx, feature in enumerate(self.config.feature_cols)
            if feature != "cycle_norm"
        ]
        valid_abs_values = abs_by_feature[valid_indices]
        order = [valid_indices[int(i)] for i in np.argsort(valid_abs_values)[::-1]]
        total = float(valid_abs_values.sum())
        if total <= 0.0:
            total = 1.0
        result: List[Dict[str, Any]] = []
        for idx in order:
            signed_value = float(signed_by_feature[idx])
            abs_value = float(abs_by_feature[idx])
            importance_percent = abs_value / total * 100.0
            result.append(
                {
                    "feature": self.config.feature_cols[int(idx)],
                    "shap_value": round(signed_value, 6),
                    "abs_shap_value": round(abs_value, 6),
                    "importance_percent": round(importance_percent, 2),
                    "effect": "increases predicted RUL" if signed_value >= 0 else "decreases predicted RUL",
                }
            )
        return result

    def predict_from_csv_path(
        self,
        csv_path: str | os.PathLike[str],
    ) -> Dict[str, Any]:
        sample = self._preprocess_csv(csv_path)
        seq = sample["sequence"]
        length = int(sample["length"])
        x = torch.tensor(seq, dtype=torch.float32, device=self.device).unsqueeze(0)
        lengths = torch.tensor([length], dtype=torch.long, device=self.device)
        pred = self._predict(x, lengths)
        all_feature_contributions = self._shap_feature_contributions(x=x, length=length)
        predicted_rul = max(0, min(int(math.floor(pred["predicted_rul"])), int(self.config.rul_cap)))
        return {
            "unit": sample["unit"],
            "cycle": sample["cycle"],
            "input_rows": sample["input_rows"],
            "predicted_rul": predicted_rul,
            "all_feature_contributions": all_feature_contributions,
            "operating_condition_summary": sample["operating_condition_summary"],
            "sensor_summary": sample["sensor_summary"],
            "rul_error_context": self._rul_error_context(float(predicted_rul)),
        }
