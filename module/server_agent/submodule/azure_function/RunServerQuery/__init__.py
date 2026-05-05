import json
import logging
from typing import Any, Dict

import azure.functions as func
import requests

from shared.query_engine import ConfigError, QueryEngine


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        payload = _read_payload(req)
        question_text = str(payload.get("questionText", "")).strip()
        previous_filters_json = str(payload.get("previousFiltersJson", "[]"))
        page_number = _safe_int(payload.get("pageNumber"), 1)
        page_size = _safe_int(payload.get("pageSize"), 50)
        paging_cookie = str(payload.get("pagingCookie", ""))

        engine = QueryEngine()
        result = engine.run(
            question_text=question_text,
            previous_filters_json=previous_filters_json,
            page_number=page_number,
            paging_cookie=paging_cookie,
            page_size=page_size,
        )
        return func.HttpResponse(
            json.dumps(result.to_dict(), default=str),
            status_code=200,
            mimetype="application/json",
        )
    except ConfigError as exc:
        logging.exception("Configuration error")
        return _error_response(500, "config_error", str(exc))
    except requests.RequestException as exc:
        logging.exception("Dataverse request error")
        return _error_response(502, "dataverse_error", f"Dataverse request failed: {exc}")
    except ValueError as exc:
        logging.exception("Validation error")
        return _error_response(400, "validation_error", str(exc))
    except Exception as exc:  # pylint: disable=broad-except
        logging.exception("Unexpected error")
        return _error_response(500, "unexpected_error", str(exc))


def _read_payload(req: func.HttpRequest) -> Dict[str, Any]:
    try:
        return req.get_json()
    except ValueError:
        question_text = req.params.get("questionText", "")
        if not question_text:
            raise ValueError("Request body must be valid JSON or contain questionText query parameter.")
        return {"questionText": question_text}


def _safe_int(value: Any, default_value: int) -> int:
    try:
        parsed = int(value)
        return parsed if parsed > 0 else default_value
    except (TypeError, ValueError):
        return default_value


def _error_response(status_code: int, error_type: str, message: str) -> func.HttpResponse:
    body = {"status": "error", "errorType": error_type, "message": message}
    return func.HttpResponse(json.dumps(body), status_code=status_code, mimetype="application/json")
