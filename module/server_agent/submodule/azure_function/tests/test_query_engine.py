import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shared.query_engine import QueryEngine


class FakeDataverseClient:
    def __init__(self) -> None:
        self.fetch_calls = []

    def list_rows(self, fetch_xml: str):
        self.fetch_calls.append(fetch_xml)
        if "aggregate=\"count\"" in fetch_xml:
            return {"value": [{"total": 3}]}
        return {
            "value": [
                {
                    "srv_name": "srv-win-01",
                    "srv_owner": "Alex",
                    "srv_os": "Windows",
                    "srv_patchstatus": "Missing",
                    "srv_sizegb": 128,
                    "srv_environment": "prod",
                    "srv_lastpatcheddate": "2026-05-01",
                }
            ],
            "@Microsoft.Dynamics.CRM.morerecords": False,
            "@Microsoft.Dynamics.CRM.fetchxmlpagingcookie": "",
        }


@pytest.fixture()
def query_engine(monkeypatch):
    monkeypatch.setenv("AZURE_TENANT_ID", "t")
    monkeypatch.setenv("AZURE_CLIENT_ID", "c")
    monkeypatch.setenv("AZURE_CLIENT_SECRET", "s")
    monkeypatch.setenv("DATAVERSE_URL", "https://example.crm.dynamics.com")
    monkeypatch.setenv("DV_ENTITY_SET_NAME", "serverinventories")
    monkeypatch.setenv("DV_ENTITY_LOGICAL_NAME", "serverinventory")
    monkeypatch.setenv("DV_PRIMARY_KEY", "serverinventoryid")
    monkeypatch.setenv("DV_COL_NAME", "srv_name")
    monkeypatch.setenv("DV_COL_OWNER", "srv_owner")
    monkeypatch.setenv("DV_COL_OS", "srv_os")
    monkeypatch.setenv("DV_COL_PATCH_STATUS", "srv_patchstatus")
    monkeypatch.setenv("DV_COL_SIZE_GB", "srv_sizegb")
    monkeypatch.setenv("DV_COL_ENVIRONMENT", "srv_environment")
    monkeypatch.setenv("DV_COL_LAST_PATCHED_DATE", "srv_lastpatcheddate")
    engine = QueryEngine()
    engine.client = FakeDataverseClient()
    return engine


def test_count_and_list(query_engine):
    result = query_engine.run("how many windows and give me list not patched")
    assert result.status == "ok"
    assert result.query_type == "count_and_list"
    assert result.count == 3
    assert len(result.rows) == 1
    assert "srv-win-01" in result.markdown_table


def test_followup_uses_previous_filter(query_engine):
    previous = json.dumps([{"field": "os", "op": "eq", "value": "Windows"}])
    result = query_engine.run("which are not patched", previous_filters_json=previous)
    assert result.status == "ok"
    assert result.query_type == "list"
    normalized = {(f["field"], f["op"], str(f["value"])) for f in result.applied_filters}
    assert ("os", "eq", "Windows") in normalized
    assert ("patchStatus", "ne", "Patched") in normalized


def test_ambiguous_request_gets_clarification(query_engine):
    result = query_engine.run("hello")
    assert result.status == "clarify"
    assert result.clarify_question
