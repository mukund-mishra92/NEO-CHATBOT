# 🔐 NEO Chatbot Configuration Guide

## Quick Setup

### Step 1: Get Your Grok API Key

1. Visit: **https://console.x.ai/**
2. Sign up or log in
3. Generate an API key
4. Copy the key (starts with `xai-...`)

### Step 2: Configure Your .env File

Create a `.env` file in your project root:

```bash
# Copy .env.example to .env
copy .env.example .env
```

Then edit `.env` and add:

```bash
# ========================================
# 🤖 GROK AI CONFIGURATION
# ========================================
GROK_API_KEY=xai-your-actual-key-here

# ========================================
# 💾 DATABASE CONFIGURATION  
# ========================================
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_actual_mysql_password
DB_NAME=neo
```

### Step 3: Restart Your Server

After saving `.env`, restart:

```bash
# Stop the server (Ctrl+C if running)
# Then restart using:
quick_start.bat
```

---

## ✅ Where Each Setting Is Used

### 1. **GROK_API_KEY** (Required for Chatbot)

**Used by:**
- ✅ Knowledge Base Chatbot (Documentation Q&A)
- ✅ SQL Assistant (Natural language to SQL)
- ✅ Diagnostic Support (Issue troubleshooting)
- ✅ Document embedding generation (for semantic search)

**Location in code:**
- `app/modules/neo_chatbot/services/llm_service.py`

**What happens without it:**
- Chatbot runs in "mock mode" with limited functionality
- Still works for basic diagnostics if you have issues.json
- SQL Assistant can show schema but won't generate queries

---

### 2. **Database Credentials** (Required for SQL Assistant)

**Used by:**
- ✅ Association Mining module
- ✅ SQL Assistant (reads schema and can execute queries)
- ✅ All database operations

**Where they're already configured:**
- Your database credentials are in `app/shared/config/config.py`
- They load from `.env` file automatically
- Same credentials used across entire application

**SQL Assistant will use:**
```python
DB_HOST=localhost      # Your MySQL server
DB_PORT=3306          # Default MySQL port
DB_USER=root          # Your username
DB_PASSWORD=******    # Your password (already have this)
DB_NAME=neo           # Your database name
```

**Location in code:**
- `app/shared/config/config.py` - Loads from .env
- `app/modules/neo_chatbot/services/sql_assistant_service.py` - Uses schema

---

## 📂 Optional: Add Database Schema File

For better SQL generation, create:

**File:** `app/modules/neo_chatbot/data/database/schema.sql`

**Content:** Your actual MySQL schema

```sql
-- Your actual tables
CREATE TABLE wms_to_wcs_order_line_request_data (
    order_id VARCHAR(50),
    sku VARCHAR(50),
    -- ... your actual columns
);

CREATE TABLE sku_master (
    -- ... your columns
);

-- Add all your tables here
```

**Why?**
- SQL Assistant generates more accurate queries
- Knows exact column names and types
- Provides better suggestions

**Don't have schema.sql?**
- No problem! SQL Assistant uses a default NEO schema
- Still works, just less specific to your exact database

---

## 🧪 Testing Your Configuration

### Test Grok API Key

Open chatbot at: http://localhost:5000/chatbot

Try asking:
- "What is NEO system?"
- "Show me top 10 customers"
- "Scheduler not working"

**Should see:** AI-generated responses (not mock responses)

**If you see mock responses:**
- Check `.env` file exists in project root
- Check `GROK_API_KEY=xai-...` is set correctly
- Restart server after adding key

### Test Database Connection

Already working in your association mining module!

SQL Assistant will use the **same database credentials**.

---

## 🎯 Summary

| Setting | Where to Add | Used For |
|---------|-------------|----------|
| **GROK_API_KEY** | `.env` file | All chatbot AI features |
| **DB_HOST** | Already in `.env` | SQL queries & mining |
| **DB_USER** | Already in `.env` | Database access |
| **DB_PASSWORD** | Already in `.env` | Database access |
| **DB_NAME** | Already in `.env` | Database selection |

---

## 💡 Pro Tips

### 1. Security
```bash
# Never commit .env to git
# Add to .gitignore (already done)
.env
```

### 2. Multiple Environments
```bash
# Development
.env

# Production
.env.production
```

### 3. Check Current Configuration
Visit: http://localhost:8080/api/chatbot/statistics

Shows:
- Active LLM provider (grok/openai/anthropic/mock)
- Database schema loaded
- Number of documents indexed

---

## ❓ Troubleshooting

### "⚠️ No LLM API keys found - using mock responses"

**Fix:**
1. Check `.env` file exists in: `c:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system\`
2. Check it contains: `GROK_API_KEY=xai-...`
3. Restart server

### "Database connection failed"

**Fix:**
- Your database credentials already work for mining module
- SQL Assistant uses the **same credentials**
- No additional setup needed

### "No schema.sql found, using default"

**Fix (Optional):**
- Create `app/modules/neo_chatbot/data/database/schema.sql`
- Paste your actual CREATE TABLE statements
- Restart server

---

## 📞 Need Help?

Check logs for detailed error messages:
- Flask server console output
- Look for `⚠️` or `❌` messages
- Check if Grok key is being detected

**Grok initialized correctly:**
```
✅ Grok (xAI) LLM initialized
✅ SQL Assistant Service initialized
✅ Diagnostic Service initialized with X known issues
```

**Mock mode (no API key):**
```
⚠️ No LLM API keys found - using mock responses
   Add GROK_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY to .env file
```
