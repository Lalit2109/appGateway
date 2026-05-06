# Dataverse + Copilot Studio Agent (Accurate, Follow-Up Safe)

This module gives you copy/paste assets to build a Copilot Studio agent that:
- queries Dataverse accurately,
- handles follow-up questions without drifting,
- avoids hallucinations and "funny" responses.

## Module structure

- `submodule/prompts/` -> paste-ready instructions for Copilot Studio
- `submodule/flow/` -> request/response contract for your Power Automate flow
- `submodule/tests/` -> regression scenarios for multi-turn and follow-up quality
- `submodule/checklists/` -> go-live checklist

## Recommended architecture (best-practice baseline)

1. **Copilot Studio Agent**
   - Handles conversation and follow-up context.
2. **Power Automate flow (`dv_secure_query`)**
   - Receives validated query request from Copilot.
   - Reads Dataverse with controlled table/column allowlist.
3. **Dataverse**
   - Source of truth.
4. **Response policy**
   - Agent can answer only from flow output, otherwise asks clarifying question.

## Build steps (copy/paste friendly)

### 1) Dataverse preparation

1. Create a service account with least privilege for required tables only.
2. For each target table, define:
   - allowed columns
   - primary key
   - searchable columns
3. Add alternate keys/indexes for high-frequency filters.
4. Add row-level security (business unit/team/owner as needed).

### 2) Create flow: `dv_secure_query`

In Power Automate:
1. Trigger: **When an action is called from Copilot**.
2. Input schema: use `submodule/flow/dv-secure-query-contract.json` (`requestSchema`).
3. Validate:
   - table is in allowlist
   - requested columns are in allowlist
   - `maxRows` within allowed range
4. Run Dataverse **List rows** with:
   - OData filter from validated payload
   - Select columns from validated payload only
   - Top count = `maxRows`
5. Map output to `responseSchema` in the same contract file.
6. Return fields: `records`, `recordCount`, `confidence`, `source`, `warnings`.

### 3) Configure Copilot Studio agent

1. Open agent -> **Settings -> Generative AI -> Instructions**.
2. Paste `submodule/prompts/agent-system-instructions.txt`.
3. Add a topic for data Q&A:
   - If question needs data -> call flow `dv_secure_query`.
   - If missing filter context -> ask one clear question (use `follow-up-questions.txt`).
4. Store conversation variables:
   - `lastTable`
   - `lastFilter`
   - `lastColumns`
   - `lastRecordIds`
   - `lastUserIntent`
5. Before every follow-up query:
   - reuse context only if unambiguous,
   - else ask disambiguation.

### 4) Strict response behavior

Use `submodule/prompts/response-policy.txt` for:
- no fabricated values,
- no jokes/funny answers,
- explicit "I don't have enough data yet" when needed,
- short, business-style responses.

### 5) Regression validation (must pass before go-live)

1. Import scenarios from `submodule/tests/conversation-regression-cases.csv`.
2. Run all scenarios in Copilot test pane.
3. Any failed scenario -> fix topic logic or flow validation, then retest.

## Why your agent may fail after 2-3 questions

Common causes:
1. Context variables not updated after each turn.
2. Agent tries to answer from memory instead of flow output.
3. No disambiguation step when follow-up reference is unclear.
4. Over-broad flow permissions returning inconsistent rows.

Fix:
- enforce strict instruction policy,
- force flow call for data questions,
- implement explicit follow-up disambiguation topic,
- run regression suite on every change.

## Quick start (minimal)

1. Copy `agent-system-instructions.txt` into Copilot instructions.
2. Build `dv_secure_query` flow using the JSON contract.
3. Add follow-up prompts from `follow-up-questions.txt`.
4. Test against all regression cases.
5. Go live only after checklist completion.
