# AgriConnect — AI Agents Complete Guide

> Everything about LLMs, RAG, Agents, Tool Use, System Prompts — and a deep dive into all three agents:
> FarmBot, BuyerBot, and DevOpsBot, with every line of code explained.

---

## Table of Contents

1. [What is an LLM?](#1-what-is-an-llm)
2. [What is a System Prompt?](#2-what-is-a-system-prompt)
3. [What is an AI Agent?](#3-what-is-an-ai-agent)
4. [What is Tool Use (Function Calling)?](#4-what-is-tool-use-function-calling)
5. [What is RAG?](#5-what-is-rag)
6. [What is LangChain?](#6-what-is-langchain)
7. [What is LangGraph?](#7-what-is-langgraph)
8. [How to Build an Agent from Scratch](#8-how-to-build-an-agent-from-scratch)
9. [The Agentic Loop — The Core Pattern](#9-the-agentic-loop--the-core-pattern)
10. [Agent 1: FarmBot — Plant Disease Diagnosis](#10-agent-1-farmbot--plant-disease-diagnosis)
11. [Agent 2: BuyerBot — Live Marketplace Assistant](#11-agent-2-buyerbot--live-marketplace-assistant)
12. [Agent 3: DevOpsBot — Infrastructure AI Agent](#12-agent-3-devopsbot--infrastructure-ai-agent)
13. [How the Three Agents Compare](#13-how-the-three-agents-compare)
14. [AWS Bedrock — What It Is and Why Used](#14-aws-bedrock--what-it-is-and-why-used)
15. [Amazon Nova — The Model Used](#15-amazon-nova--the-model-used)

---

## 1. What is an LLM?

**LLM = Large Language Model**

An LLM is a neural network trained on hundreds of billions of words from the internet, books, code, and academic papers. The training teaches it to predict "given this text, what word comes next?" — but at scale, this simple objective produces a model that can reason, write, translate, summarize, answer questions, and write code.

Examples: GPT-4 (OpenAI), Claude (Anthropic), Gemini (Google), Amazon Nova (AWS Bedrock).

### How an LLM Processes Your Message

```
Your message: "What disease is on this leaf?"
                    ↓
     Tokenizer splits into tokens:
     ["What", " disease", " is", " on", " this", " leaf", "?"]
                    ↓
     Tokens → Numbers (embeddings)
     "disease" → [0.23, -0.45, 0.87, ...] (a 4096-dim vector)
                    ↓
     Transformer layers process all tokens in context window
     (attention mechanism: each token "looks at" all other tokens)
                    ↓
     Output probability distribution over the entire vocabulary
     Next token: "Blight" (probability 0.42), "rust" (0.28), etc.
                    ↓
     Repeat: output "Blight" → now predict next token → "disease" → ...
                    ↓
     Final text: "Blight disease. Treat with copper fungicide."
```

### What an LLM Does NOT Do

- It does NOT have access to the internet
- It does NOT know current prices, live data, or real-time information
- It does NOT remember previous conversations (each call is stateless)
- It only knows what was in its training data (up to a cutoff date)

This is why agents with tools were built — to give the LLM access to real data.

### Tokens

Everything an LLM reads and writes is counted in **tokens** (roughly ¾ of a word). Most LLMs have a **context window** — the maximum tokens they can process in one call.

```
"I want tomatoes under ₹30"
 ↓ tokenized ↓
["I", " want", " tomatoes", " under", " ₹", "30"]  =  6 tokens
```

- `maxTokens: 1024` in our code = maximum 1024 tokens in the LLM's response
- Long conversation history = more tokens = more cost + slower

---

## 2. What is a System Prompt?

A system prompt is an invisible instruction given to the LLM **before** any user message. It tells the LLM who it is, what it can and cannot do, and how to respond.

```
Without system prompt:
User: "What should I bid on tomatoes?"
LLM:  "It depends on the market. Usually ₹20-40/kg is a fair range..."
      ← guesses based on training data, may be wrong

With system prompt that says "NEVER guess prices without calling get_price_stats":
User: "What should I bid on tomatoes?"
LLM:  [calls get_price_stats("Tomatoes")]
      [tool returns: min ₹18, max ₹35, avg ₹24]
LLM:  "Current tomato prices are ₹18–35/kg with an average of ₹24. To be competitive..."
      ← real data, no guessing
```

**The system prompt is the most important part of building an agent.** It controls:
- The LLM's persona and domain
- What it is allowed and not allowed to do
- When to use which tools
- Output format

All three agents have carefully crafted system prompts. The DevOpsBot's system prompt tells it to run 5 security tools simultaneously when asked for a security audit. FarmBot's system prompt tells it to switch between two response modes (conversation vs. disease diagnosis template) depending on what the farmer asked.

---

## 3. What is an AI Agent?

A plain LLM is like a very knowledgeable person locked in a room with no internet, no tools, and no memory. They can only answer based on what they already know.

**An AI Agent = LLM + Tools + Memory + Agentic Loop**

```
Plain LLM:
User → LLM → Answer
(single call, no tools, no external data)

AI Agent:
User → LLM → "I need to call search_listings" → Tool executes → Real data returned
            ↓
       LLM reads tool result → "I need more info, call get_price_stats too"
            ↓
       Tool executes → More real data
            ↓
       LLM: "Now I have enough. Here's my answer."
            ↓
       Answer to User
(multiple LLM calls, real external data, decisions made between calls)
```

**The key insight:** An agent is not a single LLM call. It is a **loop** where the LLM decides what to do next, executes it, reads the result, and decides again — until it has enough information to answer.

### Types of Agents

| Type | How It Works | Example in This Project |
|---|---|---|
| **ReAct** | Reason → Act → Observe → Repeat | BuyerBot, DevOpsBot |
| **Multimodal** | Accepts images in addition to text | FarmBot |
| **Tool-use** | LLM decides which functions to call | BuyerBot, DevOpsBot |
| **RAG-based** | Retrieves documents before generating | (not used, explained below) |

---

## 4. What is Tool Use (Function Calling)?

Tool use is the mechanism that turns an LLM into an agent. You tell the LLM: "here are some functions you can call." When the LLM needs real data, instead of guessing, it outputs a **tool call request** — a structured JSON saying "run this function with these arguments."

```
LLM receives: "What tomatoes are available under ₹25?"

LLM outputs (instead of an answer):
{
  "stopReason": "tool_use",
  "content": [{
    "toolUse": {
      "name": "search_listings",
      "input": {"search": "tomatoes", "max_price": 25},
      "toolUseId": "tool-abc123"
    }
  }]
}

Your code sees stopReason == "tool_use" → runs search_listings(search="tomatoes", max_price=25)
→ calls marketplace API → gets real listings
→ sends result back to LLM

LLM now has real data → outputs the final answer
```

### How Tool Schemas Work

Before the LLM can call a tool, you must describe every tool to it using a JSON schema. The LLM reads these schemas to understand: what each tool does, what inputs it needs, and what types those inputs should be.

```python
# From buyerbot/bedrock_client.py
TOOL_CONFIG = {
    "tools": [
        {
            "toolSpec": {
                "name": "search_listings",          # ← function name (must match Python fn)
                "description": (
                    "Search real-time produce listings from the marketplace. "
                    "Use this to find products by name, filter by category or maximum price. "
                    "Always call this before making any claims about what is available."
                ),                                  # ← tells LLM WHEN to use this tool
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {
                            "search": {
                                "type": "string",
                                "description": "Product name or keyword, e.g. 'tomatoes', 'wheat'"
                            },
                            "max_price": {
                                "type": "number",
                                "description": "Maximum price per unit in INR"
                            }
                        }
                    }
                }
            }
        }
    ]
}
```

The `description` field is not for humans — it's for the LLM. The LLM reads it to decide "when should I call this tool?" A good description dramatically improves tool selection accuracy.

---

## 5. What is RAG?

**RAG = Retrieval-Augmented Generation**

RAG is a pattern where before calling the LLM, you first retrieve relevant documents from a knowledge base and inject them into the prompt.

```
Without RAG:
User: "What is the MSP rate for wheat in 2024?"
LLM:  "I don't know recent MSP rates." (knowledge cutoff)

With RAG:
User asks → Vector Search in document database
           → Finds relevant document: "2024 MSP: Wheat ₹2,275/quintal"
           → Injects into prompt: "Context: [2024 MSP document]"
           → LLM answers: "The MSP for wheat in 2024 is ₹2,275/quintal."
```

### How RAG Works — Step by Step

```
Step 1: INDEXING (done once)
   PDF documents, web pages, manuals
        ↓
   Split into chunks (paragraphs)
        ↓
   Embedding model converts each chunk to a vector
   "MSP wheat 2024 ₹2,275" → [0.23, -0.45, 0.87, ...] (768-dim vector)
        ↓
   Store vectors + original text in Vector Database (Pinecone, ChromaDB, FAISS, OpenSearch)

Step 2: RETRIEVAL (at query time)
   User question: "What is wheat MSP?"
        ↓
   Same embedding model converts question to vector
        ↓
   Cosine similarity search: find top-K most similar vectors
        ↓
   Return the original text chunks

Step 3: GENERATION
   System prompt: "Answer based on this context only: [retrieved chunks]"
   + User question
        ↓
   LLM generates grounded answer
```

### Is RAG Used in This Project?

**No — but FarmBot's system prompt acts like a hand-crafted RAG.**

The FarmBot system prompt is 80 lines of agricultural domain knowledge (crop diseases, products available in India, dosages, urgency levels). Instead of retrieving this dynamically from a vector database, it's hardcoded into the system prompt.

For a production FarmBot, RAG would be the right approach:
- Index thousands of pages from ICAR (Indian Council of Agricultural Research) crop manuals
- Index disease identification guides with images
- When a farmer asks about rice blast, retrieve the specific disease section and inject it

**Why RAG wasn't used here:**
- The project uses Nova Lite (small, fast model)
- Retrieval requires a vector database (Pinecone, OpenSearch) — extra cost and complexity
- For this capstone scale, a well-crafted system prompt achieves similar results
- Building full RAG is a separate infrastructure project

### RAG vs Tool Use — When to Use Which

| Situation | Use RAG | Use Tool Use |
|---|---|---|
| Static knowledge (docs, manuals, policies) | ✅ | ❌ |
| Real-time data (prices, pod status, live DB) | ❌ | ✅ |
| Large knowledge base (10,000+ docs) | ✅ | ❌ |
| Structured data (APIs, databases) | ❌ | ✅ |
| Agricultural disease library | ✅ | ❌ |
| Live marketplace listings | ❌ | ✅ |

BuyerBot uses tool use (live API data). FarmBot could benefit from RAG (disease knowledge base). DevOpsBot uses tool use (live AWS/K8s APIs).

---

## 6. What is LangChain?

LangChain is a Python/JavaScript framework that provides pre-built components for building LLM applications. It abstracts away common patterns:

```python
# Without LangChain — manual:
messages = [{"role": "user", "content": "Hello"}]
response = bedrock.converse(modelId="...", messages=messages)
text = response["output"]["message"]["content"][0]["text"]

# With LangChain — abstracted:
from langchain_aws import ChatBedrock
llm = ChatBedrock(model_id="amazon.nova-lite-v1:0")
response = llm.invoke("Hello")
```

LangChain provides:
- **Chains** — link multiple LLM calls together (`PromptTemplate | LLM | OutputParser`)
- **Memory** — ConversationBufferMemory, ConversationSummaryMemory
- **Document loaders** — load PDFs, web pages, CSV files
- **Text splitters** — split documents into chunks for RAG
- **Vector stores** — connect to Pinecone, ChromaDB, FAISS
- **Retrieval chains** — full RAG pipeline in ~10 lines

### Is LangChain Used in This Project?

**No.** The agents in this project are built directly using the **AWS Boto3 SDK** and the Bedrock `converse` API. LangChain was deliberately not used because:

1. **Direct control** — the agentic loop is written explicitly so you can see exactly what's happening at each step
2. **No hidden magic** — LangChain abstracts away the tool-use loop, making it harder to understand
3. **Simpler dependencies** — no LangChain package (and its 50+ transitive dependencies) in the Lambda zip
4. **AWS-native** — Boto3 is already available in Lambda without any installation

If you wanted to rebuild BuyerBot with LangChain, it would look like:

```python
from langchain_aws import ChatBedrock
from langchain.tools import tool

@tool
def search_listings(search: str, max_price: float = None) -> dict:
    """Search real-time produce listings from the marketplace."""
    return tools.search_listings(search=search, max_price=max_price)

llm = ChatBedrock(model_id="amazon.nova-lite-v1:0").bind_tools([search_listings])
# LangChain handles the agentic loop internally
```

---

## 7. What is LangGraph?

LangGraph is LangChain's library for building **stateful, multi-step agent workflows** as directed graphs. Where LangChain handles simple chains (A → B → C), LangGraph handles complex flows with conditionals, loops, and parallel branches.

```
LangGraph workflow for a complex agent:

START
  ↓
[classify_intent]  ← "is this a security, K8s, or cost question?"
  ↓         ↓         ↓
[security] [k8s]   [finops]   ← parallel branches
  ↓         ↓         ↓
[merge_results]
  ↓
[generate_report]
  ↓
END
```

LangGraph gives you:
- **StateGraph** — a graph where each node has access to shared state
- **Conditional edges** — go to different nodes based on LLM decision
- **Parallel execution** — run multiple tool calls simultaneously
- **Checkpointing** — save and resume agent state mid-execution
- **Human-in-the-loop** — pause and wait for human approval at certain nodes

### Is LangGraph Used in This Project?

**No.** The DevOpsBot's three-mode behavior (Security / Kubernetes / FinOps) could be implemented as a LangGraph graph. Instead, it's implemented as a single system prompt that tells the LLM which tools belong to which mode.

LangGraph would be used if you needed explicit control over the flow — for example, "always run security scan first, then if critical findings exist, skip K8s check and go straight to remediation." The current approach lets the LLM decide, which works well for this use case.

---

## 8. How to Build an Agent from Scratch

Here is the general recipe — all three agents in this project follow this exact pattern:

### Step 1: Define the system prompt

```python
SYSTEM_PROMPT = """You are [NAME], a [role] for [context].

You help with:
- [capability 1]
- [capability 2]

RULES:
- NEVER [bad behavior]
- ALWAYS call [tool] before [action]
- Format output as [format]"""
```

### Step 2: Define your tools as Python functions

```python
def search_listings(search: str, max_price: float = None) -> dict:
    # Call your actual API/database/service
    response = requests.get(f"http://api/listings?search={search}")
    return response.json()
```

### Step 3: Write tool schemas for the LLM

```python
TOOLS = [
    {
        "toolSpec": {
            "name": "search_listings",
            "description": "Search produce listings. Call this before making any claims about availability.",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "search": {"type": "string", "description": "Product name"},
                        "max_price": {"type": "number", "description": "Max price in INR"}
                    }
                }
            }
        }
    }
]
```

### Step 4: Write the agentic loop

```python
def run_agent(message: str, history: list = []) -> str:
    # Build message history
    messages = [{"role": h["role"], "content": [{"text": h["text"]}]} for h in history]
    messages.append({"role": "user", "content": [{"text": message}]})
    
    # Agentic loop — runs until LLM decides it's done
    for _ in range(10):  # safety cap on iterations
        response = bedrock.converse(
            modelId="amazon.nova-lite-v1:0",
            messages=messages,
            system=[{"text": SYSTEM_PROMPT}],
            toolConfig={"tools": TOOLS},
            inferenceConfig={"maxTokens": 1024, "temperature": 0.1}
        )
        
        stop_reason = response["stopReason"]
        assistant_msg = response["output"]["message"]
        messages.append(assistant_msg)  # add to context
        
        if stop_reason == "end_turn":
            # LLM finished — return the text
            return assistant_msg["content"][0]["text"]
        
        if stop_reason == "tool_use":
            # LLM wants to call a tool — run it and feed result back
            tool_results = []
            for block in assistant_msg["content"]:
                if "toolUse" in block:
                    name = block["toolUse"]["name"]
                    inputs = block["toolUse"]["input"]
                    result = search_listings(**inputs)  # run the function
                    tool_results.append({
                        "toolResult": {
                            "toolUseId": block["toolUse"]["toolUseId"],
                            "content": [{"text": json.dumps(result)}]
                        }
                    })
            messages.append({"role": "user", "content": tool_results})
            # Loop again — LLM reads the tool result and decides what to do next
```

### Step 5: Connect to API Gateway + Lambda

```python
def lambda_handler(event, context):
    body = json.loads(event.get("body", "{}"))
    message = body.get("message", "")
    history = body.get("history", [])
    
    answer = run_agent(message, history)
    
    return {
        "statusCode": 200,
        "headers": {"Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"response": answer})
    }
```

That's the complete pattern. Now let's look at each agent's actual implementation.

---

## 9. The Agentic Loop — The Core Pattern

The agentic loop is the engine of every agent. Understanding it is the key to understanding all three agents.

```
         ┌─────────────────────────────────────────┐
         │          AGENTIC LOOP                    │
         │                                          │
  User   │  Build        LLM Call      LLM output  │
Message ─┤  messages ──► converse() ──► stopReason │
         │    list                        │         │
         │              ┌─────────────────┤         │
         │              │                 │         │
         │         end_turn           tool_use      │
         │              │                 │         │
         │          Return text     Execute tools   │
         │          to user         (real APIs)     │
         │                               │          │
         │               Add tool results to        │
         │               messages list              │
         │                               │          │
         │               Loop back ──────┘          │
         └─────────────────────────────────────────┘
```

**`stop_reason == "end_turn"`** — LLM said "I'm done, here's my answer." Extract the text and return it to the user.

**`stop_reason == "tool_use"`** — LLM said "I need to call a function." Your code runs the function, gets the result, appends it to messages as a `toolResult`, then calls the LLM again. The LLM now has the real data and continues.

The loop has a safety cap (max 6-20 iterations depending on the agent) so it never runs forever. BuyerBot caps at 6, DevOpsBot at 20 (because it might call 15 tools in one security audit).

---

## 10. Agent 1: FarmBot — Plant Disease Diagnosis

**Files:** `stage-infra/lambda/farmbot/lambda_function.py`, `system_prompt.py`
**Type:** Multimodal conversational agent (NO tool use)
**Model:** `amazon.nova-lite-v1:0` (multimodal capable)

### What FarmBot Does

FarmBot is an agricultural advisor for Indian farmers. It has two capabilities:
1. **Text conversations** — farming advice, crop selection, irrigation, government schemes
2. **Image diagnosis** — farmers upload a photo of a sick plant → FarmBot identifies the disease and gives treatment

### Architecture

```
React Frontend (FarmBot page)
       ↓  POST /chat  {message: "...", image: "<base64>", history: [...]}
API Gateway (HTTP API)
       ↓
Lambda (farmbot/lambda_function.py)
       ↓
Bedrock (amazon.nova-lite-v1:0) ← multimodal: accepts text + image bytes
       ↓
Response: {response: "Blight detected. Treat with...", critical: false}
       ↓
React Frontend shows response
       (if critical=true, shows alert banner)
```

### System Prompt Design

FarmBot has TWO response modes in one system prompt — this is a key design pattern:

```python
# system_prompt.py
SYSTEM_PROMPT = """You are FarmBot — a senior agricultural advisor for Indian farmers...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MODE 1 — NATURAL CONVERSATION (for general questions)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use this when the farmer asks about:
• Crop selection, market prices, irrigation, fertilizers, government schemes

How to respond:
→ Talk like an experienced advisor, not a template
→ Give a clear direct answer first, then explain why
→ End with 1 practical next action they can take today
→ NEVER output CRITICAL: YES for advisory questions

Example Mode 1: "Should I switch from wheat to soybean on 2 acres in Maharashtra?"
"Given Maharashtra's climate and your 30% yield drop, soybean is a strong alternative..."
[natural paragraph response, like a real advisor talking]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MODE 2 — DISEASE/PEST DIAGNOSIS (ONLY for symptom/photo questions)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use this ONLY when farmer uploads a photo or describes specific symptoms.

Format:
🔍 WHAT I SEE:
⚠️ DIAGNOSIS: [Disease name — Confidence: High/Medium/Low]
🌱 CAUSE:
✅ TREATMENT (Step by Step):
💊 PRODUCT: [Real product available in India — never invent one]
👁️ WATCH NEXT 7 DAYS:
CRITICAL: [YES only if crop will be destroyed within 48 hours]

STRICT RULES:
1. NEVER invent a pesticide not sold in India
2. NEVER give uncertain dosage — say "confirm with your agri shop"
3. Max 300 words per response"""
```

**Why two modes?** Without explicit instructions, LLMs often apply the diagnosis template to every question ("What's the weather like? 🔍 WHAT I SEE: ..."). The system prompt uses a MODE 1 / MODE 2 distinction to force the right format for the right context.

**Domain-specific rules:**
- "NEVER invent a pesticide" — LLMs hallucinate product names. A farmer acting on a fake product name is dangerous.
- "confirm dosage with your agri shop" — wrong pesticide dosage can destroy a crop or harm a farmer
- "respond in English only" — even if the farmer writes in Hindi, the response is in English (consistent for the demo; production would add Hindi support)

### Lambda Code — Line by Line

```python
# lambda_function.py

import json
import boto3
import os
import base64

bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION", "us-east-1"))
# Bedrock is not available in all regions. Nova models are in us-east-1.
# Lambda runs in ap-south-1 but calls Bedrock cross-region.
```

```python
def detect_image_format(image_bytes: bytes) -> str:
    if image_bytes[:8] == b'\x89PNG\r\n\x1a\n':
        return 'png'
    if image_bytes[:2] == b'\xff\xd8':
        return 'jpeg'
    ...
```
Reads the first few bytes (magic bytes) to detect image format. PNG always starts with `\x89PNG`. JPEG always starts with `\xff\xd8`. This is more reliable than trusting a filename extension.

```python
def lambda_handler(event, context):
    body       = json.loads(event.get("body", "{}"))
    message    = body.get("message", "").strip()
    image_b64  = body.get("image")        # base64-encoded image from frontend
    history    = body.get("history", [])  # previous turns [{role, text}]
    history    = history[-20:]            # keep last 10 exchanges = last 20 messages
```
`history[-20:]` — truncates history. If a farmer has been chatting for 2 hours, the history could be 200 messages. Sending all of them to Bedrock would be slow and expensive. Keep only the last 20 messages (10 exchanges) for context.

```python
    # Build conversation history
    messages = []
    for turn in history:
        role = "user" if turn.get("role") == "user" else "assistant"
        messages.append({
            "role": role,
            "content": [{"text": turn.get("text", "")}]
        })
```
Converts the simple `{role, text}` history format into Bedrock's message format. Each message has `role` (user/assistant) and `content` (a list — because content can have multiple parts like text + image).

```python
    # Build current turn content
    content = []
    if image_b64:
        image_bytes = base64.b64decode(image_b64)
        fmt = detect_image_format(image_bytes)
        content.append({
            "image": {
                "format": fmt,
                "source": {"bytes": image_bytes}  # ← raw bytes, not base64
            }
        })
```
Decodes the base64 image back to raw bytes. Bedrock's Nova model accepts `"source": {"bytes": ...}` for inline images — the image is sent directly in the API call body, not as a URL. The `content` list will have both the image and the text, making this a multimodal request.

```python
    if message:
        content.append({"text": message})
    elif image_b64:
        # Image with no text → auto-prompt for analysis
        content.append({
            "text": "Please analyse this crop image. Describe what you see, identify any diseases..."
        })
```
If the farmer uploads an image without typing anything, FarmBot automatically adds a default diagnosis prompt. This is better UX — the farmer can just tap "upload photo" without needing to type "please diagnose this."

```python
    response = bedrock.converse(
        modelId=os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0"),
        messages=messages,
        system=[{"text": SYSTEM_PROMPT}],
        inferenceConfig={"maxTokens": 1024, "temperature": 0.7}
    )
```
`temperature: 0.7` — higher temperature = more creative/varied responses. For FarmBot, slightly more variation is good (conversational, not robotic). BuyerBot uses `0.1` (very factual, consistent). DevOpsBot uses `0.1` (needs precise, reproducible analysis).

`maxTokens: 1024` — allows up to ~750 words response. Good for disease diagnosis which needs detailed treatment steps.

```python
    reply = response["output"]["message"]["content"][0]["text"]

    # Flag critical plant health issues
    critical_terms = ["critical", "severe", "blight", "wilt", "rot", "rust", "dying", "emergency"]
    is_critical = bool(image_b64) and any(t in reply.lower() for t in critical_terms)

    return {
        "statusCode": 200,
        "body": json.dumps({"response": reply, "critical": is_critical})
    }
```
After getting the reply, FarmBot scans for critical-sounding words. If the LLM mentions "blight" or "dying" and there was an image, `critical: true` is returned. The React frontend uses this flag to show a red alert banner: "⚠️ Critical issue detected — contact your agricultural officer immediately."

### FarmBot is NOT a Tool-Use Agent

FarmBot does NOT have tools. It uses a single `bedrock.converse()` call with no `toolConfig`. The LLM's knowledge IS the tool — its training data includes agriculture information. For the capstone scale, this is sufficient. In production, RAG (retrieving from ICAR disease databases) would make FarmBot dramatically more accurate.

---

## 11. Agent 2: BuyerBot — Live Marketplace Assistant

**Files:** `stage-infra/lambda/buyerbot/bedrock_client.py`, `tools.py`, `system_prompt.py`, `lambda_function.py`
**Type:** Tool-use agent with agentic loop (uses live marketplace data)
**Model:** `amazon.nova-lite-v1:0`
**Tools:** 4 tools — search listings, price stats, bid data, categories

### What BuyerBot Does

BuyerBot helps agricultural buyers on the marketplace. The critical constraint: **it must NEVER guess or make up prices or availability.** All data must come from the live marketplace API.

```
User: "What tomatoes are available under ₹30?"
                ↓
BuyerBot calls: search_listings(search="tomatoes", max_price=30)
                ↓
Tool calls marketplace-service API via ALB:
GET http://alb-url/api/marketplace/listings?search=tomatoes&limit=10
                ↓
Returns: [{product: "Cherry Tomatoes", price: 25, farm: "Krishna Farms", location: "Pune"}...]
                ↓
LLM formats response:
"I found 3 tomato listings under ₹30:
1. Cherry Tomatoes — ₹25/kg, 200kg available | Krishna Farms, Pune
2. Desi Tamatar — ₹22/kg, 500kg available | Ram Agro, Nashik..."
```

### The Four Tools

```python
# tools.py — four actual Python functions

def search_listings(search=None, category=None, max_price=None, limit=10):
    """Searches the live marketplace API and returns structured listings."""
    params = {"limit": min(int(limit or 10), 50)}
    if search: params["search"] = search
    if category: params["category"] = category
    qs = urllib.parse.urlencode(params)
    data = _fetch(f"/api/marketplace/listings?{qs}")  # calls real API
    
    # Filter by price (API doesn't support this param, done in Python)
    if max_price is not None:
        listings = [l for l in listings if float(l.get("price", 0)) <= float(max_price)]
    
    # Return simplified structure (less tokens = cheaper + faster)
    return {"total_found": len(listings), "listings": simplified}


def get_price_stats(product_name):
    """Gets min/max/avg prices by fetching all listings for that product."""
    data = _fetch(f"/api/marketplace/listings?search={product_name}&limit=100")
    prices = [float(l["price"]) for l in listings]
    return {
        "min_price": min(prices), "max_price": max(prices),
        "avg_price": round(sum(prices)/len(prices), 2),
        "summary": f"₹{min(prices):.0f}–₹{max(prices):.0f} per kg"
    }


def get_listing_bids(listing_id, token=None):
    """Gets all bids on a listing — helps buyer decide competitive bid amount."""
    data = _fetch(f"/api/marketplace/bids/{listing_id}", token=token)
    highest = max([float(b["amount"]) for b in bids])
    return {
        "highest_bid": f"₹{highest:.0f}",
        "competitive_suggestion": f"To win, bid above ₹{highest:.0f}"
    }


def get_available_categories():
    """Returns all product categories currently in the marketplace."""
    data = _fetch("/api/marketplace/categories")
    return {"categories": data, "count": len(data)}
```

### How BuyerBot Calls the Marketplace

```python
def _fetch(path, token=None):
    alb_url = os.environ.get('ALB_URL', '')
    url = f"http://{alb_url}{path}"
    req = urllib.request.Request(url)
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    with urllib.request.urlopen(req, timeout=12) as resp:
        return json.loads(resp.read().decode())
```

`ALB_URL` is the EKS Application Load Balancer DNS. The Lambda function calls the real marketplace-service running in EKS. This is how BuyerBot has access to live listings — it calls your microservice directly.

No AWS SDK needed here — just Python's built-in `urllib.request`. The request goes: Lambda → ALB → marketplace-service pod in EKS.

### The Agentic Loop in BuyerBot

```python
# bedrock_client.py
def get_response(message, buyer_token=None, history=None):
    bedrock = boto3.client('bedrock-runtime', ...)
    
    messages = []
    for h in (history or [])[-20:]:
        messages.append({"role": h["role"], "content": [{"text": h["text"]}]})
    messages.append({"role": "user", "content": [{"text": message}]})

    for _ in range(6):              # ← safety cap: max 6 iterations
        response = bedrock.converse(
            modelId=model_id,
            messages=messages,
            system=[{"text": SYSTEM_PROMPT}],
            toolConfig=TOOL_CONFIG, # ← gives LLM the 4 tool schemas
            inferenceConfig={"maxTokens": 600, "temperature": 0.1}
        )

        stop_reason = response['stopReason']
        assistant_msg = response['output']['message']
        messages.append(assistant_msg)  # ← add assistant turn to history

        if stop_reason == 'end_turn':
            # LLM is done — extract and return text
            for block in assistant_msg.get('content', []):
                if 'text' in block:
                    return block['text']

        if stop_reason == 'tool_use':
            tool_results = []
            for block in assistant_msg.get('content', []):
                if 'toolUse' not in block:
                    continue
                name   = block['toolUse']['name']     # e.g. "search_listings"
                inputs = block['toolUse']['input']    # e.g. {"search": "tomatoes"}
                use_id = block['toolUse']['toolUseId'] # unique ID to match result
                
                result = _run_tool(name, inputs, buyer_token)  # execute Python function
                
                tool_results.append({
                    "toolResult": {
                        "toolUseId": use_id,  # ← must match the request ID
                        "content": [{"text": json.dumps(result)}]
                    }
                })
            
            # Feed all tool results back as a "user" message
            messages.append({"role": "user", "content": tool_results})
            # ← Loop again. LLM now reads the tool results and decides next step.
```

**Why tool results are sent as "user" role:**
The Bedrock API alternates: user → assistant → user → assistant. Tool results are returned as a `user` message (role = "user"). The next LLM call sees: assistant called tool → user (tool results) → assistant should now answer.

**The cap of 6 iterations:**
A simple query like "find tomatoes" takes 2 iterations: (1) LLM calls search_listings → (2) LLM formats answer. A complex query like "find tomatoes under ₹25 AND tell me if ₹22 is a fair price" might take 3-4 iterations (two tool calls, then format). The cap of 6 prevents infinite loops if something goes wrong.

### BuyerBot System Prompt — Key Design Decisions

```python
# system_prompt.py (key sections)

SYSTEM_PROMPT = """
CRITICAL RULES — NEVER break these:

NEVER state or guess a price without first calling get_price_stats or search_listings.
NEVER claim a product is available without calling search_listings first.
NEVER suggest a bid amount without calling get_listing_bids first.
ALL data in your response must come from tool results — never from training knowledge.

When to call which tool:
→ "Find me tomatoes" / "cheap onions"          → search_listings
→ "What is the price of wheat?"                → get_price_stats
→ "What should I bid on listing #7?"           → get_listing_bids
→ "What's available?" / "What categories?"    → get_available_categories
→ Price fairness question: call BOTH search_listings + get_price_stats
"""
```

The "when to call which tool" section is a **routing guide** for the LLM. Without it, the LLM might call `search_listings` when asked about price stats (it works but is less precise). With it, the LLM picks the right tool for the right question.

`"NEVER state or guess a price"` — this is the most important rule. Without it, BuyerBot would say "tomatoes are usually ₹20-40/kg" based on its training data — which could be months out of date and wrong for a specific market.

---

## 12. Agent 3: DevOpsBot — Infrastructure AI Agent

**Files:** `devops-agent/lambda/bedrock_client.py`, `tools/security_tools.py`, `tools/kubernetes_tools.py`, `tools/finops_tools.py`, `lambda_function.py`
**Type:** Multi-tool agentic system with DynamoDB session persistence
**Model:** `us.amazon.nova-pro-v1:0` (Nova **Pro** — the most capable Nova model, used here because infra analysis requires deeper reasoning)
**Tools:** 15 tools across 3 domains

### What DevOpsBot Does

DevOpsBot is an AI operations assistant for the AgriConnect AWS infrastructure. You can ask it:
- "Run a security audit" → it calls all 5 security tools, analyzes findings, gives CRITICAL/HIGH/MEDIUM breakdown
- "Why is auth-service crashing?" → it checks pod status, fetches pod logs, describes the pod, reads cluster events, identifies root cause
- "How much are we spending?" → it pulls Cost Explorer data, Compute Optimizer recommendations, and gives a savings plan

This is the most complex agent — 15 tools, DynamoDB session storage, cross-service authentication, and EKS access from Lambda.

### Architecture

```
React Frontend (devops-agent/frontend/)
       ↓  POST /agent  {message: "Run security audit", session_id: "abc123"}
API Gateway (HTTP API, Lambda function URL)
       ↓
Lambda (lambda_function.py)
       │
       ├── Load history from DynamoDB (session_id: "abc123")
       │
       ↓
bedrock_client.run_agent(message, history)
       │
       ├── [Security Mode] → scan_ecr_images, get_guardduty_findings,
       │                      check_public_s3_buckets, check_open_security_groups,
       │                      check_iam_issues
       │
       ├── [K8s Mode] → get_pod_status, get_failing_pods, get_pod_logs,
       │                 describe_pod, get_cluster_events, get_node_status
       │
       └── [FinOps Mode] → get_cost_breakdown, get_current_resources,
                            get_rightsizing_recommendations, get_savings_recommendations
       │
       ↓
Save updated history to DynamoDB (TTL: 24 hours)
       ↓
Return {answer: "...", tools_used: ["scan_ecr_images", ...], session_id: "abc123"}
```

### DynamoDB Session Persistence

The key differentiator from FarmBot and BuyerBot: **DevOpsBot maintains conversation memory in DynamoDB.**

FarmBot and BuyerBot receive history from the frontend (the browser stores it in React state). DevOpsBot stores history server-side in DynamoDB so conversations persist across browser refreshes and device switches.

```python
# lambda_function.py

DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "devops-agent-sessions")
dynamodb       = boto3.resource("dynamodb", region_name="ap-south-1")
table          = dynamodb.Table(DYNAMODB_TABLE)


def _load_history(session_id: str) -> list:
    """Load previous conversation turns from DynamoDB."""
    resp = table.get_item(Key={"session_id": session_id})
    item = resp.get("Item", {})
    return item.get("history", [])  # returns [] if session doesn't exist yet


def _save_history(session_id: str, history: list):
    """Save conversation history with 24-hour TTL."""
    ttl = int(datetime.now(timezone.utc).timestamp()) + 86400  # now + 24 hours
    table.put_item(Item={
        "session_id": session_id,
        "history":    history[-20:],   # keep last 10 exchanges
        "ttl":        ttl,             # DynamoDB auto-deletes after TTL
        "updated":    datetime.now(timezone.utc).isoformat()
    })
```

`ttl` — DynamoDB Time To Live. You add a Unix timestamp to an item, and DynamoDB automatically deletes it when that time passes. No cron job, no cleanup code. Here: 24 hours from last activity. DevOpsBot chat sessions expire after a day of inactivity.

```python
def lambda_handler(event, context):
    body       = json.loads(event.get("body", "{}"))
    message    = body.get("message", "")
    session_id = body.get("session_id", "default")
    
    history = _load_history(session_id)          # load from DynamoDB
    
    answer, tools_used = run_agent(message, history)  # run agent
    
    history.append({"role": "user",      "text": message})
    history.append({"role": "assistant", "text": answer})
    _save_history(session_id, history)           # save back to DynamoDB
    
    return _response(200, {
        "answer":     answer,
        "tools_used": tools_used,   # ← list of which tools were called
        "session_id": session_id
    })
```

`tools_used` is returned in every response. The React frontend shows a panel: "Tools used: scan_ecr_images, get_guardduty_findings, check_public_s3_buckets..." This is "explainability" — the user can see exactly what data sources the agent used.

### The DevOpsBot System Prompt — Three Modes

```python
SYSTEM_PROMPT = """You are DevOpsBot — an expert AI agent for the AgriConnect platform
on AWS EKS (cluster: agriconnect-dev-eks, ap-south-1).

CRITICAL RULES:
- NEVER output <thinking> tags. Respond directly with your final answer only.
- ALWAYS call tools to get real data. Never guess.
- Be concise and actionable.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECURITY MODE — use these tools:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
scan_ecr_images → CVE vulnerabilities in container images
get_guardduty_findings → AWS threat detections
check_public_s3_buckets → accidentally public S3 buckets
check_open_security_groups → dangerous ports open to internet
check_iam_issues → overly permissive IAM roles and stale access keys

WORKFLOW: Run ALL 5 tools. Then produce:
1. CRITICAL findings (fix immediately)
2. HIGH findings (fix this week)
3. MEDIUM findings (schedule)
4. Quick Wins: top 3 exact CLI commands to run RIGHT NOW

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
KUBERNETES MODE — use these tools:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
get_pod_status → all pods with state and restart count
get_failing_pods → only crashing/pending/erroring pods
get_pod_logs → last N lines from a specific pod
describe_pod → full pod spec, events, resource limits
get_cluster_events → Warning events across the cluster
get_node_status → node health and resource capacity

WORKFLOW: Start with get_pod_status + get_failing_pods.
For each failing pod, call get_pod_logs AND describe_pod to find root cause.
Then give the exact fix.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINOPS MODE — use these tools:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
get_cost_breakdown → 30-day AWS spend by service with daily trend
get_current_resources → full inventory of running resources
get_rightsizing_recommendations → over-provisioned EC2/Lambda
get_savings_recommendations → Savings Plans and RI opportunities

WORKFLOW: Run ALL 4 tools. Show: total spend, top 3 cost drivers with exact $,
recommended actions with estimated savings $, and "what to do this week" plan.

FORMAT RULES:
- Use ## headers, bullet points, code blocks for CLI commands
- Show real numbers from tools — no "varies" or "estimated"
- End every response with ## Quick Wins section"""
```

The three-mode design means:
- User says "audit security" → LLM recognizes Security Mode → calls all 5 security tools
- User says "why is auth-service crashing" → LLM recognizes K8s Mode → calls pod tools
- User says "cost report" → LLM recognizes FinOps Mode → calls all 4 cost tools

The LLM switches modes automatically based on what the user asked. No routing code is needed.

**`"NEVER output <thinking> tags"`** — Nova Pro tends to output its reasoning inside `<thinking>` tags before the final answer. This would pollute the response shown to the user. The rule suppresses it, and `_strip_thinking()` in the code is a backup safety:
```python
def _strip_thinking(text: str) -> str:
    return re.sub(r"<thinking>.*?</thinking>", "", text, flags=re.DOTALL).strip()
```

### The Security Tools — Deep Dive

```python
# tools/security_tools.py

def scan_ecr_images():
    """Checks ECR scan results for all container images."""
    ecr = boto3.client("ecr", region_name="ap-south-1")
    repos = ecr.describe_repositories()["repositories"]
    
    for repo in repos:
        images = ecr.describe_images(repositoryName=repo_name, filter={"tagStatus": "TAGGED"})
        # Get the LATEST image (most recently pushed)
        images.sort(key=lambda x: x["imagePushedAt"], reverse=True)
        latest = images[0]
        
        # Get the scan findings
        resp = ecr.describe_image_scan_findings(
            repositoryName=repo_name,
            imageId={"imageDigest": latest["imageDigest"]}
        )
        counts = resp["imageScanFindings"].get("findingSeverityCounts", {})
        # Returns: {"CRITICAL": 0, "HIGH": 2, "MEDIUM": 5, "top_findings": [...]}
```

This reads the ECR native scan results (scan_on_push=true in Terraform). The agent doesn't need to run Trivy — ECR already scanned the images when they were pushed. The agent just reads the pre-existing results.

```python
def get_guardduty_findings(severity: str = "MEDIUM"):
    """Gets AWS GuardDuty threat detections."""
    gd = boto3.client("guardduty", region_name="ap-south-1")
    detectors = gd.list_detectors()["DetectorIds"]
    
    if not detectors:
        # GuardDuty is NOT enabled — this itself is a security issue
        return {
            "enabled": False,
            "message": "GuardDuty is NOT enabled in ap-south-1. Enable it immediately.",
            "enable_command": "aws guardduty create-detector --enable ..."
        }
    
    finding_ids = gd.list_findings(
        DetectorId=detector_id,
        FindingCriteria={"Criterion": {"severity": {"Gte": 4.0}}}  # 4.0 = MEDIUM
    )["FindingIds"]
    # Returns: list of GuardDuty findings (unauthorized IAM usage, port scans, etc.)
```

GuardDuty monitors AWS accounts for threats like:
- IAM credentials used from an unusual location
- EC2 instances scanning other ports (reconnaissance)
- Unusual API calls from Lambda
- Data exfiltration patterns from S3

If GuardDuty isn't enabled, the tool returns both the finding AND the CLI command to enable it.

```python
def check_public_s3_buckets():
    """Finds S3 buckets that are accidentally public."""
    s3 = boto3.client("s3", region_name="us-east-1")
    
    for bucket in buckets:
        # Check if it's an INTENTIONAL static website
        is_website = False
        try:
            s3.get_bucket_website(Bucket=name)  # succeeds = has website config
            is_website = True
        except Exception:
            pass
        
        pab = s3.get_public_access_block(Bucket=name)
        fully_blocked = all([pab["BlockPublicAcls"], pab["IgnorePublicAcls"], ...])
        
        if fully_blocked:
            safe.append(name)           # all good
        elif is_website:
            skipped.append(name)        # intentionally public (frontend bucket)
        else:
            risky.append({
                "bucket": name,
                "risk": "HIGH",
                "fix": f"aws s3api put-public-access-block --bucket {name} ..."
            })
```

The `is_website` check is critical. The AgriConnect frontend bucket is intentionally public (it hosts the React app). Without this check, DevOpsBot would flag the frontend bucket as a security issue every time — false positive. The tool skips buckets that have `get_bucket_website` configured.

```python
def check_open_security_groups():
    """Finds dangerous security group rules."""
    
    # First: find which SGs belong to load balancers
    alb_sg_ids = set()
    for lb in elb.describe_load_balancers()["LoadBalancers"]:
        for sg in lb.get("SecurityGroups", []):
            alb_sg_ids.add(sg)  # ALB SGs are expected to have 80/443 open
    
    for sg in sgs:
        is_alb = sg["GroupId"] in alb_sg_ids
        
        for rule in sg["IpPermissions"]:
            if exposed:  # rule allows 0.0.0.0/0
                if proto == "-1":
                    issues.append({"port": "ALL", "severity": "CRITICAL"})  # ALL ports = very bad
                elif port in (22, 3389):
                    issues.append({"severity": "CRITICAL"})  # SSH/RDP open = critical
                elif is_alb and port in (80, 443):
                    continue  # ← skip — ALB needs 80/443 open, that's expected
                else:
                    issues.append({"severity": "HIGH"})
```

Port 22 (SSH) or 3389 (RDP) open to `0.0.0.0/0` is CRITICAL — any internet user can attempt brute-force attacks. Ports 80/443 on an ALB SG are fine — that's what an ALB is for. The tool intelligently distinguishes expected from unexpected exposure.

```python
def check_iam_issues():
    """Finds overly permissive IAM roles and stale access keys."""
    
    # Check roles
    for role in all_roles:
        attached = iam.list_attached_role_policies(RoleName=role)
        for p in attached:
            if p["PolicyName"] == "AdministratorAccess":
                issues.append({"severity": "CRITICAL", "fix": "aws iam detach-role-policy ..."})
        
        # Also check inline policies for wildcard permissions
        for policy in inline_policies:
            doc = iam.get_role_policy(RoleName=role, PolicyName=policy)
            if "*" in actions and "*" in resources:
                issues.append({"severity": "CRITICAL"})
    
    # Check user access key age
    for user in all_users:
        for key in iam.list_access_keys(UserName=user):
            if key["Status"] == "Active":
                age = (now - key["CreateDate"]).days
                if age > 90:
                    issues.append({
                        "severity": "HIGH" if age > 180 else "MEDIUM",
                        "issue": f"Access key {key['AccessKeyId']} is {age} days old",
                        "fix": f"aws iam delete-access-key --user-name {user} ..."
                    })
```

Access keys older than 90 days are a security risk — if the key was leaked at some point, it's been potentially in attackers' hands for months. Keys older than 180 days are HIGH severity. Every finding includes the exact `fix` command — DevOpsBot doesn't just identify problems, it tells you exactly how to fix them.

### The Kubernetes Tools — EKS Access Without kubectl

The most technically interesting part of DevOpsBot: it connects to EKS from Lambda without `kubectl` installed. It uses the Kubernetes Python SDK + a custom STS presigned URL token.

```python
# tools/kubernetes_tools.py

EKS_CLUSTER = os.environ.get("EKS_CLUSTER_NAME", "agriconnect-dev-eks")
EKS_REGION  = os.environ.get("EKS_REGION", "ap-south-1")


def _get_eks_token():
    """Generate EKS authentication token via STS presigned URL."""
    import botocore.auth
    import botocore.awsrequest
    
    session     = boto3.session.Session()
    credentials = session.get_credentials().get_frozen_credentials()
    
    # Build a GetCallerIdentity STS request
    url = f"https://sts.{EKS_REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15"
    
    request = botocore.awsrequest.AWSRequest(
        method="GET",
        url=url,
        headers={"X-K8s-Aws-Id": EKS_CLUSTER}  # ← tells EKS which cluster this token is for
    )
    
    # Sign the request with SigV4 (expires in 60 seconds)
    signer = botocore.auth.SigV4QueryAuth(credentials, "sts", EKS_REGION, expires=60)
    signer.add_auth(request)
    
    # Base64-encode the signed URL → this IS the K8s auth token
    token = "k8s-aws-v1." + base64.urlsafe_b64encode(request.url.encode()).decode().rstrip("=")
    return token
```

**How this works:**
1. Lambda has an IAM role (via IRSA or its Lambda execution role) that has permission to call `eks:DescribeCluster` and access the cluster
2. The EKS cluster's `aws-auth` ConfigMap maps the Lambda IAM role to a Kubernetes user/group
3. This function creates a presigned STS URL (signed with AWS credentials) that EKS can verify
4. EKS accepts this presigned URL as authentication — no Kubeconfig file needed

```python
def _init_k8s():
    """Initialize Kubernetes Python SDK with EKS credentials."""
    global _k8s_core, _k8s_apps
    
    if _k8s_core is not None:
        return True  # already initialized in this Lambda invocation (warm start)
    
    from kubernetes import client as k8s_client
    
    # Get cluster endpoint and CA certificate from EKS
    eks = boto3.client("eks", region_name=EKS_REGION)
    cluster = eks.describe_cluster(name=EKS_CLUSTER)["cluster"]
    
    ca_data = base64.b64decode(cluster["certificateAuthority"]["data"])
    _ca_file = tempfile.NamedTemporaryFile(delete=False, suffix=".crt")
    _ca_file.write(ca_data)  # write CA cert to temp file
    
    token = _get_eks_token()
    
    cfg = k8s_client.Configuration()
    cfg.host           = cluster["endpoint"]  # EKS API server URL
    cfg.verify_ssl     = True
    cfg.ssl_ca_cert    = _ca_file.name        # verify EKS server cert
    cfg.api_key        = {"authorization": f"Bearer {token}"}  # our auth token
    
    api_client  = k8s_client.ApiClient(cfg)
    _k8s_core   = k8s_client.CoreV1Api(api_client)  # pods, services, events
    _k8s_apps   = k8s_client.AppsV1Api(api_client)  # deployments, replicasets
    
    return True
```

**Lazy initialization + warm start optimization:**
`if _k8s_core is not None: return True` — the Kubernetes client is only initialized once per Lambda execution environment. On a "warm" Lambda invocation (Lambda reuses the same container), `_k8s_core` is already set and we skip the 500ms EKS describe call. On a cold start, it initializes fresh.

```python
def get_pod_status(namespace: str = "all") -> dict:
    if not _init_k8s():
        return {"error": "Could not connect to EKS cluster."}
    
    if namespace == "all":
        items = _k8s_core.list_pod_for_all_namespaces().items
    else:
        items = _k8s_core.list_namespaced_pod(namespace).items
    
    pods = []
    for pod in items:
        state    = _pod_state(pod)    # handles CrashLoopBackOff, OOMKilled, etc.
        restarts = _pod_restarts(pod)
        ready    = _is_ready(pod)
        pods.append({
            "name":      pod.metadata.name,
            "namespace": pod.metadata.namespace,
            "state":     state,    # "Running", "CrashLoopBackOff", "OOMKilled", etc.
            "ready":     ready,
            "restarts":  restarts,
            "node":      pod.spec.node_name
        })
    
    healthy  = [p for p in pods if p["state"] == "Running" and p["ready"]]
    problems = [p for p in pods if not p["ready"] or p["state"] not in ("Running", "Succeeded")]
    
    return {"total": len(pods), "healthy": len(healthy), "problems": len(problems), "pods": pods}
```

```python
def get_pod_logs(pod_name: str, namespace: str = "dev", lines: int = 80) -> dict:
    logs = _k8s_core.read_namespaced_pod_log(
        name=pod_name, namespace=namespace, tail_lines=lines
    )
    
    # Highlight error lines for the LLM
    error_patterns = [
        r"Error|ERROR|Exception",
        r"FATAL|fatal|panic",
        r"Connection refused|ECONNREFUSED",
        r"timeout|deadline exceeded"
    ]
    flagged = []
    for i, line in enumerate(logs.split("\n")):
        if any(re.search(p, line) for p in error_patterns):
            flagged.append(f"L{i+1}: {line.strip()}")
    
    return {
        "logs": logs,
        "error_lines": flagged[:15]  # ← pre-highlighted error lines for the LLM
    }
```

The `error_lines` list is pre-extracted error lines from the logs. When the LLM receives this, it can immediately focus on the error lines without reading through 80 lines of normal output. This reduces the tokens the LLM needs to process and improves accuracy of diagnosis.

### The FinOps Tools

```python
def get_cost_breakdown(days: int = 30) -> dict:
    ce = boto3.client("ce", region_name="us-east-1")  # Cost Explorer only in us-east-1
    
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["BlendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}]
    )
    
    # Build per-service totals
    service_totals = {}
    for period in resp["ResultsByTime"]:
        for group in period["Groups"]:
            svc  = group["Keys"][0]          # "Amazon Elastic Kubernetes Service"
            cost = float(group["Metrics"]["BlendedCost"]["Amount"])
            service_totals[svc] = service_totals.get(svc, 0.0) + cost
    
    total_usd = sum(service_totals.values())
    
    # Convert to INR (83.5 exchange rate)
    by_service = [
        {"service": svc, "usd": cost, "inr": cost * 83.5, "pct": cost/total_usd*100}
        for svc, cost in sorted_svcs[:15]
    ]
    
    return {
        "total_usd": total_usd,
        "total_inr": total_usd * 83.5,
        "projected_monthly_usd": avg_daily * 30,
        "by_service": by_service,
        "daily_trend_14d": trend  # last 14 days for spotting spikes
    }
```

`INR_RATE = 83.5` — costs are shown in both USD and INR. For an Indian team, seeing `₹14,690/month` is more intuitive than `$176/month`.

```python
def get_savings_recommendations() -> dict:
    # 1. AWS Savings Plans (commit to 1yr usage for 30-40% discount)
    sp = ce.get_savings_plans_purchase_recommendation(
        SavingsPlansType="COMPUTE_SP",
        TermInYears="ONE_YEAR",
        PaymentOption="NO_UPFRONT"
    )
    monthly_savings = float(summary["EstimatedMonthlySavingsAmount"])
    
    # 2. EBS gp2 → gp3 migration (20% cheaper, same performance)
    vols = ec2.describe_volumes(Filters=[{"Name": "volume-type", "Values": ["gp2"]}])
    total_gb = sum(v["Size"] for v in vols)
    monthly_saving = total_gb * 0.02  # gp2=$0.10/GB, gp3=$0.08/GB → $0.02/GB saving
    
    # 3. NAT Gateway VPC endpoint tip
    # NAT processes data at $0.045/GB. VPC endpoints eliminate NAT charges for S3/SQS.
    results["nat_gateway_tip"] = {
        "action": "aws ec2 create-vpc-endpoint --service-name com.amazonaws.ap-south-1.s3 ..."
    }
    
    return results
```

Every recommendation includes the exact CLI command. The DevOpsBot principle: don't just identify what's wrong, give the exact command to fix it. A DevOps engineer should be able to copy-paste the output directly into their terminal.

### The 15 Tools at a Glance

**Security (5 tools)**

| Tool | What It Does | AWS Service Used |
|---|---|---|
| `scan_ecr_images` | CVE counts in latest ECR images | ECR + Inspector2 |
| `get_guardduty_findings` | Active threat detections | GuardDuty |
| `check_public_s3_buckets` | S3 buckets without public access block | S3 GetPublicAccessBlock |
| `check_open_security_groups` | Dangerous inbound rules (SSH/all ports) | EC2 DescribeSecurityGroups |
| `check_iam_issues` | Admin roles, wildcard policies, old access keys | IAM |

**Kubernetes (6 tools)**

| Tool | What It Does | K8s API Used |
|---|---|---|
| `get_pod_status` | All pods with state/ready/restarts | CoreV1.list_pod_for_all_namespaces |
| `get_failing_pods` | Only CrashLoopBackOff / OOMKilled / Pending | CoreV1.list_pod + filter |
| `get_pod_logs` | Last N log lines + pre-extracted error lines | CoreV1.read_namespaced_pod_log |
| `describe_pod` | Full pod spec, env vars, resource limits, events | CoreV1.read_namespaced_pod |
| `get_cluster_events` | Warning events across all namespaces | CoreV1.list_event_for_all_namespaces |
| `get_node_status` | Node health, capacity, utilization from metrics-server | CoreV1.list_node + CustomObjectsApi |

**FinOps (4 tools)**

| Tool | What It Does | AWS Service Used |
|---|---|---|
| `get_cost_breakdown` | 30-day spend by service + daily trend + INR conversion | Cost Explorer |
| `get_current_resources` | Full inventory (EC2, EKS, RDS, Lambda, S3, ALB, NAT) | Multiple APIs |
| `get_rightsizing_recommendations` | Over-provisioned EC2/Lambda instances | Compute Optimizer |
| `get_savings_recommendations` | Savings Plans, gp2→gp3 migration, VPC endpoint tip | Cost Explorer + EC2 |

---

## 13. How the Three Agents Compare

| Aspect | FarmBot | BuyerBot | DevOpsBot |
|---|---|---|---|
| **Type** | Multimodal conversational | Tool-use agent | Multi-tool agentic system |
| **Model** | Nova Lite | Nova Lite | Nova **Pro** |
| **Tools** | 0 (no tools) | 4 tools | 15 tools |
| **Data source** | LLM training data + system prompt knowledge | Live marketplace API via ALB | Live AWS APIs + Kubernetes API |
| **Memory** | Frontend stores history (React state) | Frontend stores history | DynamoDB (server-side, 24h TTL) |
| **Max iterations** | 1 (single call) | 6 | 20 |
| **Temperature** | 0.7 (creative, conversational) | 0.1 (factual, consistent) | 0.1 (precise, reproducible) |
| **Input types** | Text + Images (multimodal) | Text only | Text only |
| **Output** | Plain text (+ critical flag) | Formatted markdown | Structured markdown + code blocks |
| **Who uses it** | Farmers (non-technical) | Agricultural buyers | DevOps engineers |
| **Domain** | Agriculture / India | Marketplace / bidding | AWS / Kubernetes / FinOps |

### Why Different Models?

**FarmBot and BuyerBot → Nova Lite:**
- Low latency (farmers and buyers need fast responses)
- Lower cost per token
- Simple reasoning tasks (find listings, format advice)
- Nova Lite handles these well at 0.1-0.7 temperature

**DevOpsBot → Nova Pro:**
- Complex multi-step reasoning ("auth-service is crashing — why? read logs, describe pod, correlate events")
- Must synthesize findings from 15 different data sources
- Generates exact CLI commands (requires precise, confident output)
- Users are DevOps engineers who need high-quality analysis
- Cost is secondary to quality for an internal operations tool

---

## 14. AWS Bedrock — What It Is and Why Used

**AWS Bedrock** is a managed AI service that provides access to multiple foundation models via a single API. Instead of:
- Calling OpenAI's API (data leaves AWS, different auth)
- Running your own model (enormous infrastructure)
- Using SageMaker (requires model deployment)

Bedrock gives you: `bedrock.converse(modelId="...", messages=...)` — one line, and you're talking to a model.

**Why Bedrock for this project:**
1. **IAM-native auth** — no API keys to manage. Lambda's IAM role (with `bedrock:InvokeModel` permission) is sufficient. IRSA handles this automatically.
2. **Stays within AWS** — data never leaves your AWS account. Important for agricultural pricing data and security audit results.
3. **Same SDK** — Boto3 is already installed in Lambda. No additional packages needed.
4. **Cross-region calls** — Lambda runs in `ap-south-1` but calls Bedrock in `us-east-1` where Nova models are available. AWS traffic stays on the AWS backbone.

**The `converse` API:**
All three agents use `bedrock.converse()`. This is Bedrock's unified conversational API that works identically across different models (Anthropic Claude, Amazon Nova, Meta Llama). If you wanted to switch from Nova to Claude, you change one line: `modelId="anthropic.claude-3-5-sonnet-20241022-v2:0"`.

---

## 15. Amazon Nova — The Model Used

**Amazon Nova** is AWS's own family of foundation models, launched in late 2024.

| Model | Use Case | Context Window | Multimodal |
|---|---|---|---|
| Nova Micro | Fastest, cheapest, text only | 128K tokens | No |
| **Nova Lite** | Balance of speed + quality | 300K tokens | **Yes (images/video)** |
| **Nova Pro** | Most capable Nova | 300K tokens | Yes |
| Nova Canvas | Image generation | - | - |
| Nova Reel | Video generation | - | - |

**This project uses:**
- `amazon.nova-lite-v1:0` — FarmBot (needs multimodal for images) and BuyerBot (fast, cheap, sufficient)
- `us.amazon.nova-pro-v1:0` — DevOpsBot (needs superior reasoning for complex infra analysis)

**`us.` prefix** — Nova Pro requires cross-region inference in the US inference profile. The `us.` prefix tells Bedrock to route the request across multiple US regions for higher availability and throughput. This is why the `BEDROCK_REGION` is `us-east-1` even though the Lambda runs in `ap-south-1`.

**Why Nova over Claude Sonnet:**
- Nova is significantly cheaper than Claude Sonnet per token
- Nova Lite's 300K context window is enormous (entire conversation histories fit)
- Nova supports multimodal input (needed for FarmBot's image diagnosis)
- AWS-native model = no additional data processing agreements needed

---

*All code in this guide is from the actual project — FarmBot and BuyerBot in `stage-infra/lambda/`, DevOpsBot in `devops-agent/lambda/`.*
