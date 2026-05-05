import json
import os
import re
from dataclasses import dataclass
from html import escape
from typing import Any, Dict, List, Optional
from urllib.parse import quote

import requests


@dataclass
class QueryResult:
    status: str
    query_type: str
    count: int
    rows: List[Dict[str, Any]]
    markdown_table: str
    applied_filters: List[Dict[str, Any]]
    has_more: bool
    next_paging_cookie: str
    next_page_number: int
    clarify_question: str
    message: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "queryType": self.query_type,
            "count": self.count,
            "rowsJson": json.dumps(self.rows, default=str),
            "markdownTable": self.markdown_table,
            "appliedFiltersJson": json.dumps(self.applied_filters, default=str),
            "hasMore": self.has_more,
            "nextPagingCookie": self.next_paging_cookie,
            "nextPageNumber": self.next_page_number,
            "clarifyQuestion": self.clarify_question,
            "message": self.message,
        }


class ConfigError(Exception):
    pass


class DataverseClient:
    def __init__(self) -> None:
        self.tenant_id = _required_env("AZURE_TENANT_ID")
        self.client_id = _required_env("AZURE_CLIENT_ID")
        self.client_secret = _required_env("AZURE_CLIENT_SECRET")
        self.dataverse_url = _required_env("DATAVERSE_URL").rstrip("/")
        self.entity_set_name = _required_env("DV_ENTITY_SET_NAME")

    def _access_token(self) -> str:
        token_url = f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
        payload = {
            "client_id": self.client_id,
            "scope": f"{self.dataverse_url}/.default",
            "client_secret": self.client_secret,
            "grant_type": "client_credentials",
        }
        response = requests.post(token_url, data=payload, timeout=30)
        response.raise_for_status()
        return response.json()["access_token"]

    def list_rows(self, fetch_xml: str) -> Dict[str, Any]:
        token = self._access_token()
        url = f"{self.dataverse_url}/api/data/v9.2/{self.entity_set_name}?fetchXml={quote(fetch_xml)}"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "OData-Version": "4.0",
            "OData-MaxVersion": "4.0",
            "Prefer": 'odata.include-annotations="*"',
        }
        response = requests.get(url, headers=headers, timeout=60)
        response.raise_for_status()
        return response.json()


class QueryEngine:
    def __init__(self) -> None:
        self.entity_logical_name = _required_env("DV_ENTITY_LOGICAL_NAME")
        self.primary_key = _required_env("DV_PRIMARY_KEY")
        self.columns = {
            "name": _required_env("DV_COL_NAME"),
            "owner": _required_env("DV_COL_OWNER"),
            "os": _required_env("DV_COL_OS"),
            "patchStatus": _required_env("DV_COL_PATCH_STATUS"),
            "sizeGb": _required_env("DV_COL_SIZE_GB"),
            "environment": _required_env("DV_COL_ENVIRONMENT"),
            "lastPatchedDate": _required_env("DV_COL_LAST_PATCHED_DATE"),
        }
        self.os_windows_value = os.getenv("OS_WINDOWS_VALUE", "Windows")
        self.os_linux_value = os.getenv("OS_LINUX_VALUE", "Linux")
        self.patched_value = os.getenv("PATCHED_VALUE", "Patched")
        self.default_page_size = int(os.getenv("DEFAULT_PAGE_SIZE", "50"))
        self.max_page_size = int(os.getenv("MAX_PAGE_SIZE", "200"))
        self.client = DataverseClient()

    def run(
        self,
        question_text: str,
        previous_filters_json: str = "[]",
        page_number: int = 1,
        paging_cookie: str = "",
        page_size: Optional[int] = None,
    ) -> QueryResult:
        question = (question_text or "").strip()
        if not question:
            return QueryResult(
                status="clarify",
                query_type="list",
                count=0,
                rows=[],
                markdown_table="",
                applied_filters=[],
                has_more=False,
                next_paging_cookie="",
                next_page_number=1,
                clarify_question="Please share what you want to know about the servers.",
                message="Question text is empty.",
            )

        previous_filters = _safe_parse_filters(previous_filters_json)
        parsed = _parse_question(question, previous_filters, self.os_windows_value, self.os_linux_value, self.patched_value)

        if parsed["needs_clarification"]:
            return QueryResult(
                status="clarify",
                query_type=parsed["query_type"],
                count=0,
                rows=[],
                markdown_table="",
                applied_filters=parsed["filters"],
                has_more=False,
                next_paging_cookie="",
                next_page_number=page_number,
                clarify_question=parsed["clarify_question"],
                message="Clarification required before query execution.",
            )

        validated_filters = _validate_filters(parsed["filters"])
        safe_page_size = _resolve_page_size(page_size, self.default_page_size, self.max_page_size)
        current_page = page_number if page_number > 0 else 1

        conditions_xml = self._build_conditions_xml(validated_filters)
        count_value = 0
        rows: List[Dict[str, Any]] = []
        has_more = False
        next_cookie = ""

        if parsed["query_type"] in ("count", "count_and_list"):
            count_fetch = self._build_count_fetchxml(conditions_xml)
            count_data = self.client.list_rows(count_fetch)
            count_value = _parse_count(count_data)

        if parsed["query_type"] in ("list", "count_and_list"):
            list_fetch = self._build_list_fetchxml(conditions_xml, safe_page_size, current_page, paging_cookie)
            list_data = self.client.list_rows(list_fetch)
            rows = self._shape_rows(list_data.get("value", []))
            has_more = bool(list_data.get("@Microsoft.Dynamics.CRM.morerecords", False))
            next_cookie = str(list_data.get("@Microsoft.Dynamics.CRM.fetchxmlpagingcookie", "")) if has_more else ""

        markdown = _rows_to_markdown(rows)
        return QueryResult(
            status="ok",
            query_type=parsed["query_type"],
            count=count_value,
            rows=rows,
            markdown_table=markdown,
            applied_filters=validated_filters,
            has_more=has_more,
            next_paging_cookie=next_cookie,
            next_page_number=current_page + 1,
            clarify_question="",
            message=f"Executed {parsed['query_type']} query with {len(validated_filters)} filter(s).",
        )

    def _build_conditions_xml(self, filters: List[Dict[str, Any]]) -> str:
        condition_parts: List[str] = []
        for flt in filters:
            column_name = self.columns[flt["field"]]
            operator = "like" if flt["op"] == "contains" else flt["op"]
            value = str(flt["value"])
            if flt["op"] == "contains":
                value = f"%{value}%"
            condition_parts.append(
                f'<condition attribute="{escape(column_name)}" operator="{escape(operator)}" value="{escape(value)}" />'
            )
        return "".join(condition_parts)

    def _build_count_fetchxml(self, conditions_xml: str) -> str:
        filter_block = f"<filter type=\"and\">{conditions_xml}</filter>" if conditions_xml else ""
        return (
            "<fetch aggregate=\"true\">"
            f"<entity name=\"{escape(self.entity_logical_name)}\">"
            f"<attribute name=\"{escape(self.primary_key)}\" alias=\"total\" aggregate=\"count\" />"
            f"{filter_block}"
            "</entity>"
            "</fetch>"
        )

    def _build_list_fetchxml(self, conditions_xml: str, page_size: int, page_number: int, paging_cookie: str) -> str:
        filter_block = f"<filter type=\"and\">{conditions_xml}</filter>" if conditions_xml else ""
        cookie_part = f' paging-cookie="{escape(paging_cookie)}"' if paging_cookie else ""
        attributes = "".join([f'<attribute name="{escape(col)}" />' for col in self.columns.values()])
        return (
            f"<fetch count=\"{page_size}\" page=\"{page_number}\"{cookie_part}>"
            f"<entity name=\"{escape(self.entity_logical_name)}\">"
            f"{attributes}"
            f"<order attribute=\"{escape(self.columns['name'])}\" descending=\"false\" />"
            f"{filter_block}"
            "</entity>"
            "</fetch>"
        )

    def _shape_rows(self, rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for row in rows:
            out.append(
                {
                    "name": _formatted_or_raw(row, self.columns["name"]),
                    "owner": _formatted_or_raw(row, self.columns["owner"]),
                    "os": _formatted_or_raw(row, self.columns["os"]),
                    "patchStatus": _formatted_or_raw(row, self.columns["patchStatus"]),
                    "sizeGb": _formatted_or_raw(row, self.columns["sizeGb"]),
                    "environment": _formatted_or_raw(row, self.columns["environment"]),
                    "lastPatchedDate": _formatted_or_raw(row, self.columns["lastPatchedDate"]),
                }
            )
        return out


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ConfigError(f"Missing required environment variable: {name}")
    return value


def _safe_parse_filters(raw: str) -> List[Dict[str, Any]]:
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, list) else []
    except json.JSONDecodeError:
        return []


def _resolve_page_size(input_size: Optional[int], default_size: int, max_size: int) -> int:
    if input_size is None or input_size <= 0:
        return default_size
    return min(input_size, max_size)


def _parse_count(payload: Dict[str, Any]) -> int:
    values = payload.get("value", [])
    if not values:
        return 0
    raw_total = values[0].get("total", 0)
    try:
        return int(raw_total)
    except (TypeError, ValueError):
        return 0


def _formatted_or_raw(row: Dict[str, Any], column: str) -> Any:
    formatted_key = f"{column}@OData.Community.Display.V1.FormattedValue"
    if formatted_key in row:
        return row[formatted_key]
    return row.get(column, "")


def _rows_to_markdown(rows: List[Dict[str, Any]]) -> str:
    header = "| Name | Owner | OS | Patch Status | Size GB | Environment | Last Patched |\n|---|---|---|---|---:|---|---|"
    lines = [header]
    for row in rows:
        line = (
            f"| {_pipe_safe(row.get('name'))}"
            f" | {_pipe_safe(row.get('owner'))}"
            f" | {_pipe_safe(row.get('os'))}"
            f" | {_pipe_safe(row.get('patchStatus'))}"
            f" | {_pipe_safe(row.get('sizeGb'))}"
            f" | {_pipe_safe(row.get('environment'))}"
            f" | {_pipe_safe(row.get('lastPatchedDate'))} |"
        )
        lines.append(line)
    return "\n".join(lines)


def _pipe_safe(value: Any) -> str:
    return str(value if value is not None else "-").replace("|", "\\|")


def _parse_question(
    question: str,
    previous_filters: List[Dict[str, Any]],
    windows_value: str,
    linux_value: str,
    patched_value: str,
) -> Dict[str, Any]:
    lower = question.lower()
    reset_scope = bool(re.search(r"\b(reset|all servers|all|everything|overall)\b", lower))
    filters: List[Dict[str, Any]] = [] if reset_scope else list(previous_filters)

    count_intent = bool(re.search(r"\b(how many|count|total)\b", lower))
    list_intent = bool(re.search(r"\b(list|show|which|give me|display)\b", lower))
    next_page_intent = bool(re.search(r"\b(next|more)\b", lower))

    if next_page_intent and not (count_intent or list_intent):
        list_intent = True

    if count_intent and list_intent:
        query_type = "count_and_list"
    elif count_intent:
        query_type = "count"
    else:
        query_type = "list"

    if re.search(r"\b(windows|win|windows server)\b", lower):
        filters = _upsert_filter(filters, {"field": "os", "op": "eq", "value": windows_value}, replace_field="os")
    elif re.search(r"\b(linux|ubuntu|rhel)\b", lower):
        filters = _upsert_filter(filters, {"field": "os", "op": "eq", "value": linux_value}, replace_field="os")

    if re.search(r"\b(not patched|unpatched|without patch|pending patch)\b", lower):
        filters = _upsert_filter(filters, {"field": "patchStatus", "op": "ne", "value": patched_value}, replace_field="patchStatus")
    elif re.search(r"\bpatched\b", lower):
        filters = _upsert_filter(filters, {"field": "patchStatus", "op": "eq", "value": patched_value}, replace_field="patchStatus")

    owner_match = re.search(r"\b(?:owned by|owner is|owner)\s+([a-z0-9._ -]+)", lower)
    if owner_match:
        owner_value = owner_match.group(1).strip().title()
        filters = _upsert_filter(filters, {"field": "owner", "op": "eq", "value": owner_value}, replace_field="owner")

    size_match = re.search(r"\bsize\s*(>=|<=|>|<|=)\s*(\d+)\b", lower)
    if size_match:
        op_map = {">": "gt", "<": "lt", "=": "eq", ">=": "ge", "<=": "le"}
        filters = _upsert_filter(
            filters,
            {"field": "sizeGb", "op": op_map[size_match.group(1)], "value": int(size_match.group(2))},
            replace_field="sizeGb",
        )

    environment_match = re.search(r"\b(env|environment)\s+(is\s+)?([a-z0-9_-]+)\b", lower)
    if environment_match:
        env_value = environment_match.group(3).strip()
        filters = _upsert_filter(filters, {"field": "environment", "op": "eq", "value": env_value}, replace_field="environment")

    needs_clarification = False
    clarify_question = ""
    no_query_intent = not (count_intent or list_intent or next_page_intent)
    if no_query_intent:
        needs_clarification = True
        clarify_question = "Do you want a count, a list, or both?"

    return {
        "query_type": query_type,
        "filters": filters,
        "needs_clarification": needs_clarification,
        "clarify_question": clarify_question,
    }


def _upsert_filter(filters: List[Dict[str, Any]], new_filter: Dict[str, Any], replace_field: str) -> List[Dict[str, Any]]:
    updated = [flt for flt in filters if flt.get("field") != replace_field]
    updated.append(new_filter)
    return updated


def _validate_filters(filters: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    allowed_fields = {"os", "owner", "patchStatus", "sizeGb", "environment", "lastPatchedDate"}
    allowed_ops = {"eq", "ne", "gt", "lt", "ge", "le", "contains"}
    validated: List[Dict[str, Any]] = []
    for flt in filters:
        field = str(flt.get("field", "")).strip()
        op = str(flt.get("op", "")).strip()
        if field in allowed_fields and op in allowed_ops and "value" in flt:
            validated.append({"field": field, "op": op, "value": flt["value"]})
    return validated
