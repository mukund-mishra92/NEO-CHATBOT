# NEO Chatbot Module

## 🎯 Overview
Intelligent chatbot assistant for NEO Warehouse Management System with three main capabilities:

1. **📚 Documentation Q&A**: Answer questions about NEO documentation, guides, and manuals
2. **💾 Database Assistant**: Query database, show data insights, generate SQL queries
3. **🔧 Diagnostic Support**: Automated troubleshooting and solution recommendations

---

## 📁 Folder Structure

```
neo_chatbot/
├── services/               # Core chatbot services (will be created)
│   ├── knowledge_base_service.py     # Document Q&A
│   ├── sql_assistant_service.py      # Database queries
│   ├── diagnostic_service.py         # Issue troubleshooting
│   ├── llm_service.py                # AI/LLM integration
│   └── vector_store_service.py       # Document search
├── api/                    # REST API endpoints (will be created)
│   └── chatbot_endpoints.py
├── models/                 # Data models (will be created)
│   └── schemas.py
└── data/                   # YOUR DATA GOES HERE
    ├── documents/          # 📚 Place your documentation files here
    ├── database/           # 💾 Database schema or connection info
    └── support/            # 🔧 Support issues knowledge base
```

---

## 📥 What You Need to Provide

### 1️⃣ Documentation Files
**Location**: `data/documents/`

**Place your files here:**
- NEO user manuals (PDF, DOCX)
- Installation guides
- API documentation
- Technical guides
- Solution proposals
- Any other relevant documentation

**Supported formats**: `.pdf`, `.docx`, `.doc`, `.txt`, `.md`

**Example:**
```
data/documents/
├── NEO_User_Manual.pdf
├── Installation_Guide.docx
├── API_Documentation.pdf
├── Velocity_Analysis_Guide.pdf
└── Association_Mining_Tutorial.pdf
```

---

### 2️⃣ Database Information
**Location**: `data/database/`

**Option A - Schema File:**
Create a file called `schema.sql` with your database structure:
```sql
-- Example: data/database/schema.sql
CREATE TABLE order_history (
    order_id VARCHAR(50) PRIMARY KEY,
    sku VARCHAR(50),
    order_date DATE,
    quantity INT,
    customer_id VARCHAR(50)
);

CREATE TABLE sku_recommendations (
    parent_article_id VARCHAR(50),
    child_article_id VARCHAR(50),
    proximity_score DECIMAL(5,3)
);
-- ... rest of your tables
```

**Option B - Connection Info:**
Or add database credentials to your `.env` file:
```env
# Database connection for chatbot
CHATBOT_DB_HOST=localhost
CHATBOT_DB_PORT=3306
CHATBOT_DB_USER=root
CHATBOT_DB_PASSWORD=your_password
CHATBOT_DB_NAME=neo
```

---

### 3️⃣ Support Issues Document
**Location**: `data/support/issues.json` or `data/support/issues.csv`

**Choose format:**

**Option A - JSON Format:**
```json
{
  "issues": [
    {
      "issue_id": "DB_001",
      "issue_name": "Database Connection Failure",
      "category": "database",
      "severity": "critical",
      "symptoms": "Connection error | Red status badge | 500 errors",
      "root_causes": "MySQL stopped | Wrong credentials | Port blocked",
      "diagnostic_steps": "Step 1: Check MySQL service | Step 2: Test credentials | Step 3: Check port",
      "solution_1_title": "Start MySQL Service",
      "solution_1_steps": "Win+R -> services.msc -> Find MySQL -> Right-click -> Start",
      "solution_1_type": "client_side",
      "solution_2_title": "Update Credentials",
      "solution_2_steps": "Dashboard -> Database Config -> Enter credentials -> Test",
      "solution_2_type": "configuration",
      "prevention": "Auto-start MySQL | Health monitoring"
    }
  ]
}
```

**Option B - CSV Format:**
Create `data/support/issues.csv`:
```csv
issue_id,issue_name,category,severity,symptoms,root_causes,diagnostic_steps,solution_1_title,solution_1_steps,solution_1_type,prevention
DB_001,Database Connection Failure,database,critical,"Connection error | Red badge","MySQL stopped | Wrong creds","Check service | Test creds",Start MySQL Service,"Win+R -> services.msc -> Start",client_side,"Auto-start | Monitoring"
```

---

## 🚀 Quick Start

### Step 1: Prepare Your Data
1. Copy documentation files to `data/documents/`
2. Add database schema to `data/database/schema.sql` OR configure .env
3. Create support issues file in `data/support/issues.json` or `issues.csv`

### Step 2: Install Dependencies
```bash
pip install openai anthropic numpy PyPDF2 python-docx
```

### Step 3: Configure API Keys
Add to your `.env` file:
```env
# Choose one (OpenAI recommended)
OPENAI_API_KEY=your_openai_api_key_here
# OR
ANTHROPIC_API_KEY=your_anthropic_api_key_here
```

### Step 4: Start Development
Once your data is ready, the chatbot implementation will be created.

---

## 📊 Current Status

✅ Branch created: `chatbot-development`  
✅ Folder structure created  
⏳ Waiting for data sources:
   - [ ] Documentation files
   - [ ] Database schema/connection
   - [ ] Support issues document

🔄 Next: Once you provide the data, I'll create:
   - Document ingestion system
   - Vector search implementation
   - SQL query assistant
   - Issue troubleshooting system
   - Web UI for chatbot
   - API endpoints

---

## 💡 Example Chatbot Interactions

### Documentation Query
```
User: "How do I configure velocity analysis?"
Bot: Based on the Velocity Analysis Guide, here's how to configure...
     [Provides answer with source citation]
```

### Database Query
```
User: "Show me top 10 SKUs"
Bot: Here are the top 10 SKUs by order count:
     [Shows results in table format]
     [Shows SQL query used]
```

### Diagnostic Support
```
User: "My scheduler is not running"
Bot: Let me help you diagnose this issue.
     First, can you check the scheduler status?
     [Guides through troubleshooting steps]
```

---

## 📝 Notes

- This module is completely **isolated** from existing modules
- Works in separate `chatbot-development` branch
- No changes to production code
- Can be merged when ready and tested
- Easy to enable/disable without affecting other features

---

## 🆘 Need Help?

If you need help:
1. Check this README
2. Look at template files in `data/` folders
3. Ask for clarification on data format

Ready to start when you provide the three data sources! 🚀
