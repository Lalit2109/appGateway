# Power Automate + Copilot Studio Copy/Paste Guide

Use this guide to build a stable Dataverse Q&A agent for:
- 30+ columns
- around 3000 records
- multi-turn follow-up questions
- strict no-hallucination behavior

Assumed Dataverse columns (replace logical names with yours):
- `cr2f_name`
- `cr2f_ostype`
- `cr2f_owner`
- `cr2f_application`
- `cr2f_patchingdate`

Assumed table:
- `cr2f_servers`

---

## 1) Copilot Studio system instructions

Paste in: **Agent > Settings > Generative AI > Instructions**

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

## 2) Flow: `dv_secure_query`

### Trigger
- **When an agent calls the flow**

### Inputs
- `userQuestion` (Text)
- `contextJson` (Text, optional)

---

## 3) Parse question to structured JSON

Add action: **Create text with GPT** (or equivalent in your tenant).

Prompt:

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

Parse JSON schema:

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

---

## 4) Build OData filter (copy/paste expressions)

Initialize variable:
- `vFilterParts` (Array) = `[]`

If `ostype` exists:

```txt
concat("contains(cr2f_ostype,'", replace(body('Parse_JSON')?['filters']?['ostype'],'''',''''''), "')")
```

If `owner` exists:

```txt
concat("contains(cr2f_owner,'", replace(body('Parse_JSON')?['filters']?['owner'],'''',''''''), "')")
```

If `application` exists:

```txt
concat("contains(cr2f_application,'", replace(body('Parse_JSON')?['filters']?['application'],'''',''''''), "')")
```

If `patchFrom` exists:

```txt
concat("cr2f_patchingdate ge ", body('Parse_JSON')?['filters']?['patchFrom'], "T00:00:00Z")
```

If `patchTo` exists:

```txt
concat("cr2f_patchingdate le ", body('Parse_JSON')?['filters']?['patchTo'], "T23:59:59Z")
```

Final filter query:

```txt
join(variables('vFilterParts'),' and ')
```

---

## 5) Dataverse actions

### Count path (`operation == count`)
Use **List rows**:
- Table: `cr2f_servers`
- Filter rows: `vFilterQuery`
- Select columns: server primary key only
- Top count: `5000`
- Pagination: ON, threshold `5000`

Count expression:

```txt
length(body('List_rows_count')?['value'])
```

### List path (`operation == list`)
Use **List rows**:
- Table: `cr2f_servers`
- Filter rows: `vFilterQuery`
- Select columns:
  `cr2f_name,cr2f_ostype,cr2f_owner,cr2f_application,cr2f_patchingdate`
- Top count: `100`
- Pagination: ON

---

## 6) Return payload format

For count:

```json
{
  "source": "dataverse",
  "operation": "count",
  "count": 123,
  "records": [],
  "appliedFilter": "contains(cr2f_ostype,'windows')",
  "confidence": "high",
  "warnings": []
}
```

For list:

```json
{
  "source": "dataverse",
  "operation": "list",
  "count": 25,
  "records": [],
  "appliedFilter": "contains(cr2f_application,'SAP')",
  "confidence": "high",
  "warnings": []
}
```

For clarification:

```json
{
  "source": "dataverse",
  "operation": "clarification",
  "count": 0,
  "records": [],
  "appliedFilter": "",
  "confidence": "low",
  "warnings": [],
  "clarificationQuestion": "Which owner should I use?"
}
```

---

## 7) Copilot topic routing

After flow call:
- if `operation == clarification` -> ask `clarificationQuestion`
- if `operation == count` -> return count answer
- if `operation == list` -> show list/table result

Save variables every turn:
- `lastOsType`
- `lastOwner`
- `lastApplication`
- `lastDateFrom`
- `lastDateTo`
- `lastOperation`

This prevents multi-turn drift after a few questions.

---

## 8) Performance and safety notes

- Always set select columns (do not fetch all 30+ columns by default).
- For counts, fetch only ID column.
- Keep list responses capped to 100.
- Use pagination for larger filtered results.
- Add indexes/alternate keys on frequent filters:
  - os type
  - owner
  - application
  - patching date

---

## 9) Example user prompts this flow supports

- "How many servers are Windows?"
- "How many belong to user X?"
- "How many are mapped to application Y?"
- "Give me the list."
