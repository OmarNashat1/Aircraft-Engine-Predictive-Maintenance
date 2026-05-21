import os
import json
from typing import Any, Dict, List, Literal, Optional
import re

try:
    from groq import Groq
except Exception:
    Groq = None

from pydantic import BaseModel, ValidationError


GROQ_MODEL = os.getenv("GROQ_REPORT_MODEL", "openai/gpt-oss-120b")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")


class FeatureContribution(BaseModel):
    feature: str
    shap_value: float
    abs_shap_value: float
    importance_percent: float
    effect: str


class SummaryStats(BaseModel):
    mean: float
    min: float
    max: float
    std: float


class RULErrorContext(BaseModel):
    metric_name: str
    mae_cycles: float
    rul_range: str


class RULPredictionPayload(BaseModel):
    unit: int
    cycle: int
    input_rows: int
    predicted_rul: float
    all_feature_contributions: List[FeatureContribution]
    operating_condition_summary: Dict[str, SummaryStats]
    sensor_summary: Dict[str, SummaryStats]
    rul_error_context: Optional[RULErrorContext] = None


RiskLevel = Literal["ok", "watch", "critical"]


ReportSource = Literal["groq", "fallback"]


class RULReportResponse(BaseModel):
    unit: int
    cycle: int
    predicted_rul: float
    risk_level: RiskLevel
    maintenance_report: str
    recommendation: str
    report_source: ReportSource

UNSAFE_PHRASES = [
    "shap",
    "confidence",
    "caused damage",
    "causes damage",
    "causing damage",
    "caused failure",
    "causes failure",
    "directly caused",
    "directly causes",
    "proves degradation",
    "proved degradation",
    "confirms degradation",
    "confirms failure",
    "this sensor caused",
    "this feature caused",
    "physical cause",
    "root cause is",
]

def sanitize_llm_report_text(text: str) -> str:
    if not text:
        return ""

    cleaned = str(text)

    replacements = [
        (r"\bmodel confidence\b", "historical prediction-error context"),
        (r"\bconfidence score\b", "prediction-error context"),
        (r"\bconfidence interval\b", "error reference range"),
        (r"\bconfidence\b", "historical error context"),
        (r"\bSHAP\b", "feature contribution"),
    ]

    for pattern, replacement in replacements:
        cleaned = re.sub(
            pattern,
            replacement,
            cleaned,
            flags=re.IGNORECASE
        )

    return cleaned

SYSTEM_PROMPT = """
You are writing for maintenance engineers and operators who need a clear engineering-style RUL report.

Write a maintenance report as plain text only. Do not return JSON.

Use these exact section labels:
Executive Summary
Engine Performance Analysis
Critical Findings
Risk Classification Assessment
Review Focus
Recommendations and Action Items
Conclusion

Rules:
- Do not use the word SHAP.
- Do not mention model confidence.
- Do not use markdown bullets.
- Do not claim physical causality.
- Do not write root-cause claims.
- Explain feature contributions as model associations only.
- Use wording like "the model associated T50 with a lower remaining-life estimate".
- Do not say any feature caused damage, proved degradation, confirmed failure, or was the root cause.
- Use operating and sensor summaries only as context.
- Do not invent sensor meanings, physical mechanisms, thresholds, or maintenance procedures.
- You may recommend review, monitoring, inspection planning, trend comparison, and maintenance scheduling, but avoid specific physical repair claims unless provided in the input.
"""


def classify_risk(predicted_rul: float) -> RiskLevel:
    if predicted_rul <= 20:
        return "critical"
    if predicted_rul <= 40:
        return "watch"
    return "ok"


def normalize_prediction_payload(prediction_payload: Dict[str, Any]) -> Dict[str, Any]:
    payload = dict(prediction_payload)
    payload.pop("confidence", None)

    if "all_feature_contributions" not in payload:
        top_features = payload.get("top_contributing_features")
        if top_features is not None:
            payload["all_feature_contributions"] = top_features

    payload.pop("top_contributing_features", None)
    return payload


def compact_feature_text(features: List[FeatureContribution], max_items: int = 12) -> str:
    selected = features[:max_items]
    return "; ".join(
        f"{item.feature}: {item.effect}, relative influence {item.importance_percent}%, contribution value {item.shap_value}"
        for item in selected
    )


def compact_summary_text(summary: Dict[str, SummaryStats], max_items: int = 10) -> str:
    parts = []
    for key, value in list(summary.items())[:max_items]:
        parts.append(
            f"{key}: mean {value.mean}, range {value.min} to {value.max}, variation {value.std}"
        )
    return "; ".join(parts)


def validate_safe_language(report: Dict[str, Any]) -> None:
    text = json.dumps(report, ensure_ascii=False).lower()
    violations = [phrase for phrase in UNSAFE_PHRASES if phrase in text]
    if violations:
        raise ValueError(f"Unsafe or non-operator-friendly language detected in LLM report: {violations}")


def mae_text(error_context: Optional[RULErrorContext]) -> str:
    if error_context is None:
        return "No model error-band value was provided with this response."
    return (
        f"The applicable historical error reference is {error_context.metric_name} = "
        f"{error_context.mae_cycles} cycles for the range {error_context.rul_range}."
    )


def features_by_effect(features: List[FeatureContribution], effect_word: str, max_items: int = 5) -> List[FeatureContribution]:
    return [feature for feature in features if effect_word in feature.effect.lower()][:max_items]


def feature_list_text(features: List[FeatureContribution]) -> str:
    if not features:
        return "no dominant measurements in this group"
    return ", ".join(f"{item.feature} ({item.importance_percent}% relative influence)" for item in features)


def build_recommendation(payload: RULPredictionPayload, risk_level: RiskLevel) -> str:
    lower = features_by_effect(payload.all_feature_contributions, "decrease", max_items=3)
    focus = ", ".join(item.feature for item in lower) or "the highest-ranked measurements"

    if risk_level == "critical":
        return (
            f"Prioritize immediate maintenance review for Unit {payload.unit} within the next operational cycles and focus trend checks on {focus}."
        )

    if risk_level == "watch":
        return (
            f"Schedule closer monitoring and inspection planning for Unit {payload.unit}, with particular attention to {focus} trends before the predicted RUL window is reached."
        )

    return (
        f"Continue routine monitoring for Unit {payload.unit} and use {focus} as the primary trend checks during the next review."
    )


def fallback_report(payload: RULPredictionPayload, risk_level: RiskLevel) -> str:
    lower = features_by_effect(payload.all_feature_contributions, "decrease", max_items=5)
    higher = features_by_effect(payload.all_feature_contributions, "increase", max_items=5)

    lower_text = feature_list_text(lower)
    higher_text = feature_list_text(higher)

    operating_parts = []
    for key in ("alt", "Mach", "TRA"):
        if key in payload.operating_condition_summary:
            value = payload.operating_condition_summary[key]
            operating_parts.append(f"{key} averaged {value.mean} with a range of {value.min} to {value.max}")
    operating_text = ", ".join(operating_parts) if operating_parts else "the available operating-condition summary"

    sensor_names = [item.feature for item in payload.all_feature_contributions[:6]]
    sensor_text = ", ".join(sensor_names) if sensor_names else "the highest-ranked measurements"
    error_text = mae_text(payload.rul_error_context)
    recommendation = build_recommendation(payload, risk_level)

    return (
        f"Executive Summary\n"
        f"The predictive analysis conducted on Unit {payload.unit} at cycle {payload.cycle} indicates a {risk_level} status with a predicted Remaining Useful Life of {payload.predicted_rul} cycles. {error_text} This estimate should be used as a maintenance-planning indicator rather than a direct physical diagnosis.\n\n"
        f"Engine Performance Analysis\n"
        f"The input window contains {payload.input_rows} rows of engine operating and sensor data. The model associated {lower_text} with a lower remaining-life estimate, while it associated {higher_text} with a higher remaining-life estimate. The final RUL reflects the balance between measurements that pulled the estimate downward and measurements that partially offset that movement.\n\n"
        f"Critical Findings\n"
        f"The measurements requiring the closest review are {sensor_text}. These values should be checked as trends across the uploaded cycle window and compared against prior healthy operation for the same unit or fleet. The operating context included {operating_text}, so the review should confirm whether this operating window is representative of normal use or whether the operating conditions influenced the model response.\n\n"
        f"Risk Classification Assessment\n"
        f"The health classification is {risk_level}. In this system, ok indicates a higher remaining-life range, watch indicates a maintenance-planning range requiring closer monitoring, and critical indicates a low remaining-life range requiring immediate review. The selected MAE reference provides an expected historical prediction-error context for this RUL range.\n\n"
        f"Review Focus\n"
        f"Maintenance engineers should focus on the measurements the model associated with lower RUL, especially {feature_list_text(lower[:3])}. These should be reviewed through recent trends, range changes, variation, and comparison with previous cycles.\n\n"
        f"Recommendations and Action Items\n"
        f"{recommendation} Review the uploaded data quality, verify that the cycle and operating conditions are correct, compare the highlighted measurements against historical baselines, and decide whether the unit requires closer monitoring, inspection planning, or scheduled maintenance.\n\n"
        f"Conclusion\n"
        f"Unit {payload.unit} is currently classified as {risk_level} based on the predicted RUL and the model's measurement-association pattern. The highlighted measurements should guide the next engineering review, but the report does not claim that any individual measurement physically caused degradation."
    )


def build_user_prompt(payload: RULPredictionPayload, risk_level: RiskLevel) -> str:
    lower_features = features_by_effect(payload.all_feature_contributions, "decrease", max_items=5)
    higher_features = features_by_effect(payload.all_feature_contributions, "increase", max_items=5)
    all_feature_text = compact_feature_text(payload.all_feature_contributions, max_items=10)
    operating_text = compact_summary_text(payload.operating_condition_summary, max_items=3)
    sensor_text = compact_summary_text(payload.sensor_summary, max_items=8)
    error_text = mae_text(payload.rul_error_context)

    return (
        f"Unit: {payload.unit}\n"
        f"Cycle: {payload.cycle}\n"
        f"Predicted RUL: {payload.predicted_rul} cycles\n"
        f"Risk level: {risk_level}\n"
        f"Model error reference: {error_text}\n"
        f"Rows in input window: {payload.input_rows}\n"
        f"Features associated with lower remaining-life estimate: {feature_list_text(lower_features)}\n"
        f"Features associated with higher remaining-life estimate: {feature_list_text(higher_features)}\n"
        f"Ordered model feature-contribution results: {all_feature_text}\n"
        f"Operating context: {operating_text}\n"
        f"Sensor context: {sensor_text}\n\n"
        "Generate the maintenance report using the required sections. Keep it concise enough for a dashboard/detail page, around 500 to 750 words. "
        "Use association wording only. Do not mention confidence. Do not return JSON."
    )


class RULReportGenerator:
    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None, use_fallback_on_llm_error: bool = True):
        self.api_key = api_key or GROQ_API_KEY
        self.model = model or GROQ_MODEL
        self.use_fallback_on_llm_error = use_fallback_on_llm_error

        if not self.api_key and not self.use_fallback_on_llm_error:
            raise ValueError("Missing GROQ_API_KEY. Set it in your environment.")

        if Groq is None:
            self.client = None
        else:
            self.client = Groq(api_key=self.api_key) if self.api_key else None

    def generate_report(self, prediction_payload: Dict[str, Any]) -> Dict[str, Any]:
        normalized_payload = normalize_prediction_payload(prediction_payload)

        try:
            payload = RULPredictionPayload.model_validate(normalized_payload)
        except ValidationError as exc:
            raise ValueError(f"Invalid RUL prediction payload: {exc}") from exc

        risk_level = classify_risk(payload.predicted_rul)
        recommendation = build_recommendation(payload, risk_level)

        maintenance_report = ""
        report_source = "fallback"

        if self.client is not None:
            user_prompt = build_user_prompt(payload, risk_level)
            try:
                completion = self.client.chat.completions.create(
                    model=self.model,
                    temperature=0.1,
                    messages=[
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": user_prompt},
                    ],
                )
                maintenance_report = sanitize_llm_report_text(
                    completion.choices[0].message.content or ""
                ).strip()

                if maintenance_report:
                    report_source = "groq"
            except Exception as exc:
                print("Groq report generation failed:", repr(exc))
                if not self.use_fallback_on_llm_error:
                    raise

        if not maintenance_report:
            maintenance_report = fallback_report(payload, risk_level)
            report_source = "fallback"

        report = {
            "unit": payload.unit,
            "cycle": payload.cycle,
            "predicted_rul": payload.predicted_rul,
            "risk_level": risk_level,
            "maintenance_report": maintenance_report,
            "recommendation": recommendation,
            "report_source": report_source,
        }

        try:
            validate_safe_language(report)

        except ValueError as exc:
            print("Groq report rejected by safe-language validation:", str(exc))

            if report_source == "groq" and self.client is not None:
                try:
                    repair_prompt = f"""
        Rewrite the following maintenance report using the same section labels and the same meaning.

        Important rules:
        - Do not use the word confidence.
        - Do not use the word SHAP.
        - Do not claim physical causality.
        - Do not mention root cause.
        - Do not say any feature caused damage, failure, or degradation.
        - Keep plain text only.
        - Keep the same sections.

        Report to rewrite:
        {maintenance_report}
        """.strip()

                    repaired_completion = self.client.chat.completions.create(
                        model=self.model,
                        temperature=0.0,
                        messages=[
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": repair_prompt},
                        ],
                    )

                    repaired_report = sanitize_llm_report_text(
                        repaired_completion.choices[0].message.content or ""
                    ).strip()

                    if repaired_report:
                        report["maintenance_report"] = repaired_report
                        report["report_source"] = "groq"

                    validate_safe_language(report)
                    return RULReportResponse.model_validate(report).model_dump()

                except Exception as repair_exc:
                    print("Groq repair attempt failed:", repr(repair_exc))

            if not self.use_fallback_on_llm_error:
                raise

            report["maintenance_report"] = fallback_report(payload, risk_level)
            report["recommendation"] = recommendation
            report["report_source"] = "fallback"

            validate_safe_language(report)

        validated_report = RULReportResponse.model_validate(report)
        return validated_report.model_dump()
