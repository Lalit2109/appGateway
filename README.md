# Dataverse + Copilot Studio (Step-by-Step for New Builders)

This branch is a standalone application for building a Copilot Studio agent that answers from Dataverse accurately, handles follow-up questions, and avoids made-up responses.

If you are new to Copilot Studio, follow this README top-to-bottom once.  
After first setup, use it as your implementation checklist.

---

## 1) What you are building

You will build:
1. **Copilot Studio agent** (chat experience)
2. **Power Automate flow** named `dv_secure_query` (data access layer)
3. **Dataverse table** (already exists in your case)

The agent should support examples like:
- "How many servers are Windows?"
- "How many belong to user X?"
- "How many are mapped to application Y?"
- "Give me the list"

---

## 2) Assumptions (replace with your real names)

Table (logical name): `cr2f_servers`  
Key columns (logical names):
- `cr2f_name`
- `cr2f_ostype`
- `cr2f_owner`
- `cr2f_application`
- `cr2f_patchingdate`

If your logical names are different, replace them in all steps.

---

## 3) Folder map in this branch

- `module/dataverse-copilot-studio-agent/submodule/prompts/`  
  Prompt text to paste into Copilot Studio
- `module/dataverse-copilot-studio-agent/submodule/flow/`  
  JSON request/response contract
- `module/dataverse-copilot-studio-agent/submodule/tests/`  
  Multi-turn regression test cases
- `module/dataverse-copilot-studio-agent/submodule/docs/`  
  Copy/paste flow expression guide

---

## 4) Build the flow first (Power Automate)

Build this exact flow to avoid mismatch with prompt instructions.

### 4.1 Create flow

1. Open Power Automate.
2. Create new cloud flow.
3. Name: `dv_secure_query`.
4. Trigger: **When an agent calls the flow**.
5. Add trigger inputs:
   - `userQuestion` (Text)
   - `contextJson` (Text, optional)

### 4.2 Add action: Parse question into JSON

Add action **Create text with GPT** (or your tenant's equivalent AI text action).

Prompt to paste (exact):

```txt
Convert user query to strict JSON only.
No explanation text, no markdown.

User query:
{{userQuestion}}

Previous context JSON:
{{contextJson}}

Output schema:
{
  "operation": "count|list",
  "filters": {
    "ostype": "string|null",
    "owner": "string|null",
    "application": "string|null",
    "patchFrom": "yyyy-MM-dd|null",
    "patchTo": "yyyy-MM-dd|null"
  },
  "top": 50,
  "needsClarification": false,
  "clarificationQuestion": "string|null"
}

Rules:
- If query asks “how many”, operation=count.
- If query asks “list/show/give me”, operation=list.
- If missing key business filter for vague query, set needsClarification=true with one short question.
- Normalize Windows variants (window/windows/win) to "windows".
- Return valid JSON only.
```

Then add action **Parse JSON** (name it `Parse_JSON`) with this schema:

```json
{
  "type": "object",
  "properties": {
    "operation": { "type": "string" },
    "filters": {
      "type": "object",
      "properties": {
        "ostype": { "type": ["string", "null"] },
        "owner": { "type": ["string", "null"] },
        "application": { "type": ["string", "null"] },
        "patchFrom": { "type": ["string", "null"] },
        "patchTo": { "type": ["string", "null"] }
      }
    },
    "top": { "type": "integer" },
    "needsClarification": { "type": "boolean" },
    "clarificationQuestion": { "type": ["string", "null"] }
  },
  "required": ["operation", "filters", "top", "needsClarification"]
}
```

### 4.3 Add clarification short-circuit branch

Add a **Condition**:
- Expression: `@equals(body('Parse_JSON')?['needsClarification'], true)`

If **Yes**, return response immediately via **Respond to an agent**:
- operation = `clarification`
- clarificationQuestion = `body('Parse_JSON')?['clarificationQuestion']`
- records = `[]`
- count = `0`
- source = `dataverse`
- confidence = `low`

If **No**, continue.

### 4.4 Build filter dynamically

Add variable:
- Name: `vFilterParts`
- Type: Array
- Value: `[]`

Then add conditions to append strings into `vFilterParts`.

If ostype exists:
```txt
concat("contains(cr2f_ostype,'", replace(body('Parse_JSON')?['filters']?['ostype'],'''',''''''), "')")
```

If owner exists:
```txt
concat("contains(cr2f_owner,'", replace(body('Parse_JSON')?['filters']?['owner'],'''',''''''), "')")
```

If application exists:
```txt
concat("contains(cr2f_application,'", replace(body('Parse_JSON')?['filters']?['application'],'''',''''''), "')")
```

If patchFrom exists:
```txt
concat("cr2f_patchingdate ge ", body('Parse_JSON')?['filters']?['patchFrom'], "T00:00:00Z")
```

If patchTo exists:
```txt
concat("cr2f_patchingdate le ", body('Parse_JSON')?['filters']?['patchTo'], "T23:59:59Z")
```

Add **Compose** `vFilterQuery`:
```txt
join(variables('vFilterParts'),' and ')
```

### 4.5 Add operation branch (count vs list)

Add Condition:
- `@equals(body('Parse_JSON')?['operation'], 'count')`

#### If count
Use **Dataverse - List rows**:
- Table: `cr2f_servers`
- Filter rows: output of `vFilterQuery`
- Select columns: primary key only (faster count)
- Top count: `5000`
- Pagination: ON (threshold 5000)

Set `count` as:
```txt
length(body('List_rows_count')?['value'])
```

Respond with:
- source: `dataverse`
- operation: `count`
- count: above expression
- records: `[]`
- appliedFilter: `outputs('vFilterQuery')`
- confidence: `high`
- warnings: `[]`

#### If list
Use **Dataverse - List rows**:
- Table: `cr2f_servers`
- Filter rows: output of `vFilterQuery`
- Select columns: `cr2f_name,cr2f_ostype,cr2f_owner,cr2f_application,cr2f_patchingdate`
- Top count: `100`
- Pagination: ON

Respond with:
- source: `dataverse`
- operation: `list`
- count: `length(body('List_rows_list')?['value'])`
- records: `body('List_rows_list')?['value']`
- appliedFilter: `outputs('vFilterQuery')`
- confidence: `high`
- warnings: `[]`

---

## 5) Connect flow to Copilot Studio

1. Open Copilot Studio agent.
2. Go to **Plugins/Actions** and add the flow `dv_secure_query`.
3. In your data Q&A topic, call this action for data questions.
4. Pass:
   - `userQuestion` = user utterance
   - `contextJson` = conversation context variable (optional)

After action:
- If operation = `clarification` -> ask clarificationQuestion
- If operation = `count` -> answer with count
- If operation = `list` -> show rows as a list/table

Store conversation variables every turn:
- `lastOsType`
- `lastOwner`
- `lastApplication`
- `lastDateFrom`
- `lastDateTo`
- `lastOperation`

This is the key to preventing drift after 2-3 questions.

---

## 6) Copilot Studio instructions (paste this)

Go to **Agent > Settings > Generative AI > Instructions** and paste:

```txt
You are an enterprise server inventory assistant.

Rules:
1) For data questions, answer only from action output `dv_secure_query`.
2) Never invent numbers, records, dates, owners, or applications.
3) If required detail is missing, ask one short clarification question.
4) If follow-up reference is ambiguous (“those”, “same one”), ask disambiguation.
5) Tone must be professional and concise. No jokes, no humor, no playful responses.
6) If no records match, say “No matching records found” and suggest a better filter.

Follow-up context:
- Reuse prior filter only when unambiguous.
- Keep last used: osType, owner, application, date range, and output mode (count/list).

Response format:
- Answer: <direct result>
- Basis: Dataverse (dv_secure_query)
- Applied filter: <short summary>
- Confidence: High | Medium | Low
```

---

## 7) Why your old setup may fail after a few follow-ups

Most common causes:
1. Not saving context variables after each turn
2. Agent answering from LLM text instead of flow output
3. No ambiguity check for terms like "those" or "same one"
4. Pulling too many columns unnecessarily and confusing response generation

Fixes are exactly what this README implements.

---

## 8) Validation checklist (run before go-live)

1. Ask: "How many servers are Windows?"
2. Follow-up: "How many belong to user Alex?"
3. Follow-up: "How many are mapped to application SAP?"
4. Ask: "Give me the list."
5. Ask ambiguous follow-up: "show details for that one" (should ask clarification)
6. Ask out-of-scope: "Tell me a joke" (should refuse politely)

Also run:
- `module/dataverse-copilot-studio-agent/submodule/tests/conversation-regression-cases.csv`

---

## 9) Performance notes for your volume (3000 records, 30+ columns)

- Always use **select columns** (do not return all 30+ by default)
- Count path should query only key column
- Limit list responses to top 100
- Enable pagination
- Add indexes/keys on common filters:
  - os type
  - owner
  - application
  - patching date

---

## 10) If something still does not match in your flow

Use this strict mapping:
- Natural language parsing -> `Create text with GPT` + `Parse_JSON`
- Clarification branch -> `needsClarification == true`
- Dataverse query branch -> `operation == count/list`
- Final answer source -> always `Respond to an agent` payload

If you keep this action order and names, your flow will match the instructions.
