# Copilot Studio + Dataverse (Fresh Start, Click-by-Click)

This branch is a clean starter for your app.

Goal:
- User asks count/list questions from Dataverse server inventory.
- Bot answers only from Dataverse.
- Bot handles follow-up.
- Bot rejects joke/off-topic requests.

Examples that must work:
- "How many servers are windows?"
- "How many belong to user Alex?"
- "How many are mapped to application SAP?"
- "Give me the list."

---

## 0) Your confirmed assumptions

- Platform: Copilot Studio + Power Automate
- Dataverse table exists
- All relevant columns are text (not lookup)
- Response types: count + list
- Reject off-topic/jokes
- Use columns: `name`, `ostype`, `owner`, `patching date`, `application`

---

## 1) Fill these values first (do this before building)

Replace these placeholders everywhere in this README:

- `TABLE_LOGICAL_NAME` -> your table logical name (example: `cr2f_servers`)
- `COL_NAME` -> logical column name for Name (example: `cr2f_name`)
- `COL_OSTYPE` -> logical column name for OS type (example: `cr2f_ostype`)
- `COL_OWNER` -> logical column name for Owner (example: `cr2f_owner`)
- `COL_APP` -> logical column name for Application (example: `cr2f_application`)
- `COL_PATCH_DATE` -> logical column name for patching date (example: `cr2f_patchingdate`)
- `COL_PRIMARY_KEY` -> primary key column logical name

How to find logical names:
1. Power Apps -> Dataverse -> Tables -> your table
2. Columns -> open each column -> copy **Name** (not display name)

---

## 2) Build flow `dv_secure_query` (exact action order)

Open Power Automate and create a cloud flow.

### 2.1 Trigger
1. Add trigger: **When an agent calls the flow**
2. Add inputs:
   - `userQuestion` (Text)
   - `contextJson` (Text) (optional)

### 2.2 Action: parse question JSON with AI
1. Add action: **Create text with GPT**
2. Rename action to: `Create_text_with_GPT_Parse_Request`
3. Paste this prompt:

```txt
Convert the user query into strict JSON only.
Do not return markdown.

User query:
{{userQuestion}}

Previous context JSON:
{{contextJson}}

Return schema:
{
  "operation": "count|list",
  "filters": {
    "name": "string|null",
    "ostype": "string|null",
    "owner": "string|null",
    "application": "string|null",
    "patchDateFrom": "yyyy-MM-dd|null",
    "patchDateTo": "yyyy-MM-dd|null"
  },
  "needsClarification": false,
  "clarificationQuestion": "string|null"
}

Rules:
- "how many/count" -> operation=count
- "list/show/give me" -> operation=list
- Normalize window/windows/win to windows
- If user asks data question but critical info is missing, set needsClarification=true and ask one short question.
- Output valid JSON only.
```

4. Add action: **Parse JSON**
5. Rename action to: `Parse_Request_JSON`
6. Content: output of `Create_text_with_GPT_Parse_Request`
7. Schema:

```json
{
  "type": "object",
  "properties": {
    "operation": { "type": "string" },
    "filters": {
      "type": "object",
      "properties": {
        "name": { "type": ["string", "null"] },
        "ostype": { "type": ["string", "null"] },
        "owner": { "type": ["string", "null"] },
        "application": { "type": ["string", "null"] },
        "patchDateFrom": { "type": ["string", "null"] },
        "patchDateTo": { "type": ["string", "null"] }
      }
    },
    "needsClarification": { "type": "boolean" },
    "clarificationQuestion": { "type": ["string", "null"] }
  },
  "required": ["operation", "filters", "needsClarification"]
}
```

### 2.3 Action: clarification short-circuit
1. Add **Condition**
2. Rename to: `Condition_Clarification`
3. Expression:

```txt
@equals(body('Parse_Request_JSON')?['needsClarification'], true)
```

4. In **If yes**:
   - Add **Respond to an agent**
   - Return fields:
     - `source` = `dataverse`
     - `operation` = `clarification`
     - `count` = `0`
     - `records` = `[]`
     - `appliedFilter` = ``
     - `confidence` = `low`
     - `clarificationQuestion` = `body('Parse_Request_JSON')?['clarificationQuestion']`
     - `normalizedFilters` = `body('Parse_Request_JSON')?['filters']`

5. In **If no** continue with next steps.

### 2.4 Action: build OData filter
1. Add **Initialize variable**
   - Name: `vFilterParts`
   - Type: Array
   - Value: `[]`

2. Add these blocks (each block = Condition + Append to array variable).

Block A: name
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['name']))
```
- If yes -> Append to array variable (`vFilterParts`) value:
```txt
concat("contains(", "COL_NAME", ",'", replace(body('Parse_Request_JSON')?['filters']?['name'],'''',''''''), "')")
```

Block B: ostype
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['ostype']))
```
- If yes append:
```txt
concat("contains(", "COL_OSTYPE", ",'", replace(body('Parse_Request_JSON')?['filters']?['ostype'],'''',''''''), "')")
```

Block C: owner
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['owner']))
```
- If yes append:
```txt
concat("contains(", "COL_OWNER", ",'", replace(body('Parse_Request_JSON')?['filters']?['owner'],'''',''''''), "')")
```

Block D: application
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['application']))
```
- If yes append:
```txt
concat("contains(", "COL_APP", ",'", replace(body('Parse_Request_JSON')?['filters']?['application'],'''',''''''), "')")
```

Block E: patchDateFrom
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['patchDateFrom']))
```
- If yes append:
```txt
concat("COL_PATCH_DATE", " ge ", body('Parse_Request_JSON')?['filters']?['patchDateFrom'], "T00:00:00Z")
```

Block F: patchDateTo
- Condition:
```txt
@not(empty(body('Parse_Request_JSON')?['filters']?['patchDateTo']))
```
- If yes append:
```txt
concat("COL_PATCH_DATE", " le ", body('Parse_Request_JSON')?['filters']?['patchDateTo'], "T23:59:59Z")
```

3. Add **Compose** action
   - Rename: `Compose_FilterQuery`
   - Expression:
```txt
join(variables('vFilterParts'),' and ')
```

### 2.5 MANDATORY: add Dataverse List rows actions
1. Add **Condition**:
```txt
@equals(body('Parse_Request_JSON')?['operation'], 'count')
```
2. Rename to: `Condition_Operation_Count`

#### If yes branch (count)
1. Add action: **Microsoft Dataverse -> List rows**
2. Rename to: `List_rows_count`
3. Configure:
   - Table name: `TABLE_LOGICAL_NAME`
   - Filter rows: output of `Compose_FilterQuery`
   - Select columns: `COL_PRIMARY_KEY`
   - Top count: `5000`
   - Pagination: ON, threshold `5000`

4. Add **Compose**, rename: `Compose_Count`
   - Expression:
```txt
length(body('List_rows_count')?['value'])
```

5. Add **Respond to an agent** with:
   - `source` = `dataverse`
   - `operation` = `count`
   - `count` = `outputs('Compose_Count')`
   - `records` = `[]`
   - `appliedFilter` = `outputs('Compose_FilterQuery')`
   - `confidence` = `high`
   - `clarificationQuestion` = ``
   - `normalizedFilters` = `body('Parse_Request_JSON')?['filters']`

#### If no branch (list)
1. Add action: **Microsoft Dataverse -> List rows**
2. Rename to: `List_rows_list`
3. Configure:
   - Table name: `TABLE_LOGICAL_NAME`
   - Filter rows: output of `Compose_FilterQuery`
   - Select columns: `COL_NAME,COL_OSTYPE,COL_OWNER,COL_APP,COL_PATCH_DATE`
   - Top count: `100`
   - Pagination: ON

4. Add **Compose**, rename: `Compose_List_Count`
   - Expression:
```txt
length(body('List_rows_list')?['value'])
```

5. Add **Respond to an agent** with:
   - `source` = `dataverse`
   - `operation` = `list`
   - `count` = `outputs('Compose_List_Count')`
   - `records` = `body('List_rows_list')?['value']`
   - `appliedFilter` = `outputs('Compose_FilterQuery')`
   - `confidence` = `high`
   - `clarificationQuestion` = ``
   - `normalizedFilters` = `body('Parse_Request_JSON')?['filters']`

Save flow.

---

## 3) Add flow into Copilot Studio (exact)

### 3.1 Agent instructions
Go to Agent -> Settings -> Generative AI -> Instructions and paste:

```txt
You are a server inventory assistant.

Rules:
1) For data questions, use dv_secure_query output only.
2) Never invent numbers or records.
3) If flow asks clarification, ask that exact question.
4) No jokes or off-topic responses.
5) Keep answers concise and professional.
```

### 3.2 Add action
1. Open your Copilot topic for server Q&A.
2. Add action/plugin: `dv_secure_query`.
3. Map inputs:
   - `userQuestion` -> latest user message
   - `contextJson` -> variable `varContextJson` (string, default `{}`)

### 3.3 Handle outputs
After action result:
1. If `operation == clarification` -> ask `clarificationQuestion`
2. If `operation == count` -> answer:
   - "Total matching servers: {count}"
3. If `operation == list` -> answer:
   - "Found {count} servers. Showing top results:"
   - then show `records`

### 3.4 Follow-up memory
After every successful action call:
1. Set `varContextJson` = `string(normalizedFilters)`
2. Reuse it in the next call input `contextJson`

This supports follow-up like:
- "How many are windows?"
- "Now only owner Alex"
- "Now show list"

---

## 4) Test script (run in Copilot test chat)

Run in this exact order:
1. `How many servers are windows?`
2. `How many belong to owner Alex?`
3. `How many are mapped to application SAP?`
4. `Give me the list`
5. `Now only for owner Priya`
6. `Tell me a joke`

Expected:
- First five return Dataverse-based answers.
- Joke request is rejected politely.

---

## 5) Quick fix table (if something fails)

- Error: empty results for known data
  - Check logical names and exact column names in List rows.
- Error: invalid filter syntax
  - Check `Compose_FilterQuery` output.
- Bot gives invented answers
  - Ensure topic response uses flow output fields, not free-text generation.
- Follow-up not working
  - Ensure `varContextJson` is updated after each call.
