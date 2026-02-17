# 🔧 Table Priority Analyzer - Troubleshooting Guide

## ✅ Fixed Issues

### 1. **Hardcoded `localhost:8000` → Dynamic URL**
**Problem:** Frontend was hardcoded to call `http://localhost:8000`, but you're accessing via `192.168.1.149:8000`

**Solution:** Updated frontend to dynamically detect the current hostname:
```javascript
// BEFORE (BROKEN)
const API_BASE = 'http://localhost:8000';

// AFTER (FIXED)
const API_BASE = window.location.protocol + '//' + window.location.hostname + 
                (window.location.port ? ':' + window.location.port : '');
```

**Files Updated:**
- ✅ `frontend/table_priority_validator.html` - Now uses dynamic URL

### 2. **Improved Error Handling**
**Added:**
- Better error messages from backend
- Check for missing OpenAI API key
- Check for missing schema CSV file
- Detailed logging to help debug issues

**Files Updated:**
- ✅ `backend/app/api/table_priority_routes.py` - Enhanced error handling

---

## 📋 Pre-Flight Checklist

Before accessing `http://192.168.1.149:8000/table_priority_analyzer`, make sure:

### 1. **Backend Server is Running**
```bash
# Check if backend is running
curl http://192.168.1.149:8000/health
```

Expected response:
```json
{"status": "healthy", "service": "NEO Chatbot", "version": "1.0.0"}
```

### 2. **Environment Variables Configured**
Set these environment variables before starting the backend:

```bash
# Required for test_query endpoint
export OPENAI_API_KEY="sk-your-actual-key"
export SQL_GENERATION_MODEL="gpt-4o"  # or gpt-5.2
export NEO_SCHEMA_CSV_PATH="/path/to/Table_information.csv"
```

**On Windows PowerShell:**
```powershell
$env:OPENAI_API_KEY = "sk-your-actual-key"
$env:SQL_GENERATION_MODEL = "gpt-4o"
$env:NEO_SCHEMA_CSV_PATH = "d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\Table_information.csv"
```

### 3. **Schema CSV File Exists**
The system looks for `Table_information.csv` at:
```
d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\Table_information.csv
```

Verify:
```powershell
Test-Path "d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\Table_information.csv"
```

### 4. **Network Access**
If accessing from another machine, ensure firewall allows port 8000:
```bash
# Test connectivity
curl http://192.168.1.149:8000/health
```

---

## 🚀 How to Start

### Option 1: Quick Start (Using Existing Setup)
```bash
cd d:\ML_Deployements\1.NEO_Chatbot\4_jan
python -m backend.main
```

### Option 2: With Environment Variables
```bash
# PowerShell
$env:OPENAI_API_KEY = "sk-..."
python -m backend.main

# Or CMD
set OPENAI_API_KEY=sk-...
python -m backend.main
```

### Option 3: Using Setup Script
```bash
cd d:\ML_Deployements\1.NEO_Chatbot\4_jan
./start.bat  # If exists
```

---

## 🐛 Troubleshooting Steps

### Issue: "Error: Failed to fetch"

**Step 1: Check Backend Connectivity**
```bash
curl http://192.168.1.149:8000/health
```
- ✅ If you see JSON response → Backend is running
- ❌ If timeout/refused → Backend not running

**Step 2: Check Browser Console**
1. Open browser DevTools (F12)
2. Go to **Console** tab
3. Look for error messages
4. Copy error and check against solutions below

**Step 3: Check Backend Error Logs**
Look at terminal where backend is running for:
- 📝 `"Testing query: ..."`
- ❌ `"ERROR: OpenAI API key not configured"`
- ❌ `"Schema CSV not found at ..."`
- ❌ `"Failed to initialize SQL engine"`

### Solution: Missing OpenAI API Key
**Error Message:** `"OpenAI API key not configured"`

**Fix:**
```bash
# Set the environment variable
set OPENAI_API_KEY=sk-write-your-actual-key-here

# Then restart backend
python -m backend.main
```

### Solution: Missing Schema CSV
**Error Message:** `"Schema CSV not found at ..."`

**Fix:**
1. Verify file exists:
   ```bash
   dir "d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\Table_information.csv"
   ```

2. If missing, check if it's at a different location:
   ```bash
   # Find the file
   Get-ChildItem -Path "d:\ML_Deployements" -Name "Table_information.csv" -Recurse
   ```

3. Set correct path:
   ```bash
   set NEO_SCHEMA_CSV_PATH=d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\Table_information.csv
   ```

### Solution: CORS Issues
**Error Message:** Browser console shows CORS error

**Why:** Fixed! CORS is now configured to allow all origins in `backend/app/main.py`:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### Solution: URL Mismatch
**Symptom:** Query button works but shows wrong API URL in browser console

**Fix:** Already fixed! Dynamic URL now properly detects:
- ✅ `http://localhost:8000` 
- ✅ `http://192.168.1.149:8000`
- ✅ `http://mycomputer.local:8000`
- ✅ `https://secured.domain.com:8443`

---

## ✅ Verification Steps

Once you've applied the fixes:

### 1. Restart Backend
```bash
# Kill any existing Python processes
taskkill /F /IM python.exe

# Start fresh
cd d:\ML_Deployements\1.NEO_Chatbot\4_jan
python -m backend.main
```

### 2. Clear Browser Cache
- Press `Ctrl+Shift+Delete` → Clear browsing data
- Close all browser tabs
- Reopen `http://192.168.1.149:8000/table_priority_analyzer`

### 3. Test the Endpoint
Run this in browser console (F12 → Console):
```javascript
// TestAPI connectivity
fetch('http://192.168.1.149:8000/health')
  .then(r => r.json())
  .then(d => console.log('✅ Backend OK:', d))
  .catch(e => console.error('❌ Backend Error:', e));

// Test query endpoint
fetch('http://192.168.1.149:8000/api/table-priority/test-query', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({query: 'show me bot locations'})
})
  .then(r => r.json())
  .then(d => console.log('✅ Query Result:', d))
  .catch(e => console.error('❌ Query Error:', e));
```

### 4. Expected Success Response
```json
{
  "success": true,
  "query": "show me bot locations",
  "ranked_tables": [
    {
      "table_name": "bot_master",
      "description": "Bot master table with locations",
      "columns": "BOT_ID, LOCATION_ID, ...",
      "category": "bot"
    },
    ...
  ]
}
```

---

## 📊 Files Modified

| File | Change | Impact |
|------|--------|--------|
| `frontend/table_priority_validator.html` | Hardcoded localhost → Dynamic URL | ✅ Fixes "Failed to fetch" error |
| `backend/app/api/table_priority_routes.py` | Better error logging | ✅ Easier debugging |

---

## 🆘 Still Not Working?

### Debug Command
Run this to get full diagnostics:
```bash
# Test backend health
curl -X GET http://192.168.1.149:8000/health

# Test with network interface
curl -X GET http://localhost:8000/health

# Check if backend is listening
netstat -ano | findstr :8000
```

### Collect Logs
When reporting issues, include:
1. Browser console output (F12)
2. Backend terminal output
3. Output of: `echo %OPENAI_API_KEY%` (redact the actual key)
4. Output of: `dir d:\ML_Deployements\1.NEO_Chatbot\4_jan\data\database\`

---

## 📝 Summary

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| "Failed to fetch" from 192.168.1.149 | Hardcoded localhost | ✅ Dynamic URL |
| Unhelpful error messages | Weak exception handling | ✅ Better logging |
| CORS issues | No CORS middleware | ✅ Already configured |
| API key not found | Environment variable | ⚠️ User must set manually |
| Schema CSV missing | Wrong path | ⚠️ User must verify path |

---

## ✅ Quick Fix Checklist

- [ ] Backend is running (`python -m backend.main`)
- [ ] Environment variables set (OPENAI_API_KEY, NEO_SCHEMA_CSV_PATH)
- [ ] Schema CSV file exists
- [ ] Browser cache cleared
- [ ] Accessing via correct IP: `http://192.168.1.149:8000`
- [ ] Test query button shows dynamic URL in browser console
- [ ] Backend logs show queries being processed
