# Step-by-Step Diagnostic Workflow Guide

## Overview

The NEO Chatbot now includes a **Step-by-Step Diagnostic Workflow** that parses multi-step solutions and SQL queries from support logs, executes them sequentially, and validates each step with user feedback before proceeding.

## How It Works

### 1. Solution Parsing

When a diagnostic session is started, the system automatically parses:

**Solution Text** - Splits solution into individual steps by detecting:
- Numbered lists: `1. Step one`, `2. Step two`
- Step format: `Step 1: Do this`, `Step 2: Do that`
- Numbered with parentheses: `1) First step`, `2) Second step`
- Multiple lines: If no numbered pattern, splits by newlines

**SQL Queries** - Splits SQL_Query column by:
- Semicolon delimiter: `SELECT * FROM orders; SELECT * FROM bots;`
- Each query is associated with its corresponding step

### 2. Interactive Workflow

The workflow follows this sequence:

```
┌─────────────────────────────────────────┐
│  1. User searches for issue             │
│  2. Clicks "Start Step-by-Step"         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  System creates diagnostic session      │
│  - Parses solution steps                │
│  - Parses SQL queries                   │
│  - Shows Step 1                         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  User executes Step 1                   │
│  - Reads step instructions              │
│  - Executes SQL query (if available)    │
│  - Checks if issue is resolved          │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  User provides feedback:                │
│  ✅ "Issue Fixed" → Session ends        │
│  ➡️ "Not Fixed" → Move to Step 2        │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Repeat for each step until:            │
│  - Issue is resolved, OR                │
│  - All steps exhausted                  │
└─────────────────────────────────────────┘
```

## API Endpoints

### 1. Start Diagnostic Session

**Endpoint:** `POST /api/diagnostic-support/session/start`

**Request:**
```json
{
  "issue_id": 5,
  "issue_type": "bot_level"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Diagnostic session started. Step 1 of 3",
  "data": {
    "session_id": "uuid-here",
    "problem": "Bot stuck at station",
    "severity": "High",
    "total_steps": 3,
    "current_step": {
      "step_number": 1,
      "step_text": "Check bot status in database",
      "sql_query": "SELECT * FROM bot_status WHERE bot_id = ?",
      "has_sql": true
    }
  }
}
```

### 2. Get Session Status

**Endpoint:** `GET /api/diagnostic-support/session/{session_id}/status`

**Response:**
```json
{
  "success": true,
  "message": "Step 2 of 3",
  "data": {
    "session_id": "uuid-here",
    "status": "active",
    "problem": "Bot stuck at station",
    "severity": "High",
    "current_step": {
      "step_number": 2,
      "total_steps": 3,
      "step_text": "Verify bot assignment",
      "sql_query": "SELECT * FROM bot_assignments WHERE bot_id = ?",
      "has_sql": true
    },
    "history": [
      {
        "step_number": 1,
        "step_text": "Check bot status in database",
        "sql_query": "SELECT * FROM bot_status WHERE bot_id = ?",
        "is_fixed": false,
        "feedback_notes": "",
        "timestamp": "2026-01-14T10:30:00"
      }
    ]
  }
}
```

### 3. Submit Step Feedback

**Endpoint:** `POST /api/diagnostic-support/session/feedback`

**Request:**
```json
{
  "session_id": "uuid-here",
  "is_fixed": false,
  "feedback_notes": "Bot status shows active but still stuck"
}
```

**Response (Not Fixed - Continue):**
```json
{
  "success": true,
  "message": "Moving to step 2",
  "data": {
    "session_id": "uuid-here",
    "status": "active",
    "next_step": {
      "step_number": 2,
      "total_steps": 3,
      "step_text": "Verify bot assignment",
      "sql_query": "SELECT * FROM bot_assignments WHERE bot_id = ?",
      "has_sql": true
    },
    "history": [...]
  }
}
```

**Response (Fixed):**
```json
{
  "success": true,
  "message": "✅ Issue resolved at step 2",
  "data": {
    "session_id": "uuid-here",
    "status": "resolved",
    "total_steps_used": 2,
    "history": [...]
  }
}
```

**Response (All Steps Exhausted):**
```json
{
  "success": true,
  "message": "⚠️ All diagnostic steps completed but issue not resolved. May need to escalate.",
  "data": {
    "session_id": "uuid-here",
    "status": "unresolved",
    "total_steps": 3,
    "history": [...]
  }
}
```

### 4. Close Session

**Endpoint:** `DELETE /api/diagnostic-support/session/{session_id}`

**Response:**
```json
{
  "success": true,
  "message": "Session closed",
  "data": {
    "final_status": "resolved",
    "history": [...]
  }
}
```

## Frontend Usage

### Search and Start Workflow

1. Go to **Diagnostic Support** page: `http://localhost:8000/diagnostic_support.html`
2. Search for an issue (e.g., "bot stuck")
3. Click **"🔍 Start Step-by-Step Diagnostic"** button on any result

### Execute Steps

1. **Modal opens** with first step
2. **Read the step instructions**
3. **Execute SQL query** (if provided) in your database
4. **Check if issue is resolved**
5. **Click feedback button:**
   - ✅ **"Issue Fixed"** - Completes session successfully
   - ➡️ **"Not Fixed - Next Step"** - Moves to next step

### Session History

Each step execution is recorded in history showing:
- Step number and text
- SQL query executed
- User feedback (fixed/not fixed)
- Timestamp

## CSV Data Format

The workflow expects support log CSV files with this structure:

### Required Columns

| Column | Description | Example |
|--------|-------------|---------|
| `S NO` | Issue ID | 1, 2, 3... |
| `Problem` | Problem description | "Bot stuck at station A" |
| `Severity` | Issue severity | High, Medium, Low |
| `Solution` | Multi-step solution | "1. Check status\n2. Verify assignment\n3. Reset bot" |
| `SQL_Query` | Multiple SQL queries | "SELECT * FROM bots; SELECT * FROM stations;" |
| `Outcome` | Expected outcome | "Bot resumed operation" |
| `Reported_to_Dev` | Escalation flag | Y/N |

### Solution Format Examples

**Numbered List:**
```
1. Check bot status in database
2. Verify bot is assigned to correct station
3. Check for error messages in logs
```

**Step Format:**
```
Step 1: Query bot status table
Step 2: Confirm bot assignment
Step 3: Review error logs
```

**Multi-line Format:**
```
Check bot status
Verify assignment
Reset if needed
```

### SQL Query Format

**Multiple queries separated by semicolon:**
```sql
SELECT * FROM bot_status WHERE bot_id = 123;
SELECT * FROM bot_tasks WHERE bot_id = 123;
SELECT * FROM error_logs WHERE bot_id = 123 ORDER BY timestamp DESC LIMIT 10;
```

## Session Management

### Session Storage

- Sessions are stored in memory (dictionary)
- Each session has a unique UUID
- Sessions persist until explicitly closed or server restart

### Session States

| State | Description |
|-------|-------------|
| `active` | Session in progress, awaiting feedback |
| `resolved` | Issue fixed during workflow |
| `unresolved` | All steps exhausted, issue not fixed |
| `completed` | Session finished (generic) |

## Best Practices

### For Support Engineers

1. **Review SQL queries** before execution
2. **Modify parameters** as needed (bot_id, order_id, etc.)
3. **Check database results** carefully
4. **Provide feedback notes** for future reference
5. **Escalate unresolved issues** to development team

### For CSV Maintainers

1. **Use numbered steps** for clarity (1., 2., 3.)
2. **Separate SQL queries** with semicolons
3. **Test solutions** before adding to CSV
4. **Keep steps atomic** - one action per step
5. **Include expected outcomes** in solution text

### For Developers

1. **Monitor session history** for patterns
2. **Analyze unresolved sessions** to improve solutions
3. **Update CSV files** based on real-world usage
4. **Add new SQL queries** as system evolves

## Troubleshooting

### Common Issues

**Issue:** Session not starting
- **Cause:** Invalid issue ID or type
- **Solution:** Verify issue exists in support logs CSV

**Issue:** SQL query fails
- **Cause:** Query parameters not updated
- **Solution:** Modify query with actual values (bot_id, etc.)

**Issue:** Steps don't match SQL queries
- **Cause:** Different number of steps vs queries
- **Solution:** System handles gracefully - shows queries for available steps

**Issue:** Session lost
- **Cause:** Server restart
- **Solution:** Sessions are in-memory - start new session after restart

## Future Enhancements

Planned improvements:
- [ ] Persistent session storage (database/file)
- [ ] SQL query parameter substitution UI
- [ ] Auto-execute SQL queries (read-only)
- [ ] Session sharing between users
- [ ] Session analytics and reporting
- [ ] Export session history as PDF/Excel
- [ ] Integration with ticket system
- [ ] Real-time collaboration on sessions

## Example Workflow

### Scenario: Bot Stuck at Station

**Step 1: Search**
```
User searches: "bot stuck"
Results show Issue #12: "Bot not moving from station A"
```

**Step 2: Start Session**
```
User clicks: "Start Step-by-Step Diagnostic"
System shows:
  - Problem: Bot not moving from station A
  - Severity: High
  - Step 1 of 4: "Check bot status in database"
  - SQL: SELECT * FROM bot_status WHERE station = 'A';
```

**Step 3: Execute & Feedback**
```
User:
  1. Executes SQL query
  2. Finds bot is in "WAITING" state
  3. Clicks "Not Fixed - Next Step"
```

**Step 4: Continue**
```
System shows Step 2: "Verify bot task assignment"
SQL: SELECT * FROM bot_tasks WHERE bot_id = 123;
User finds task is complete but bot not released
```

**Step 5: Continue**
```
System shows Step 3: "Release bot from completed task"
SQL: UPDATE bot_tasks SET status='RELEASED' WHERE bot_id=123;
User executes update query
Bot starts moving
```

**Step 6: Resolve**
```
User clicks: "Issue Fixed"
System shows: ✅ Issue resolved at step 3
Session completes with full history
```

## API Testing

### Using cURL

**Start Session:**
```bash
curl -X POST http://localhost:8000/api/diagnostic-support/session/start \
  -H "Content-Type: application/json" \
  -d '{"issue_id": 5, "issue_type": "bot_level"}'
```

**Submit Feedback:**
```bash
curl -X POST http://localhost:8000/api/diagnostic-support/session/feedback \
  -H "Content-Type: application/json" \
  -d '{"session_id": "uuid-here", "is_fixed": false, "feedback_notes": "Trying next step"}'
```

### Using Python

```python
import requests

# Start session
response = requests.post(
    'http://localhost:8000/api/diagnostic-support/session/start',
    json={'issue_id': 5, 'issue_type': 'bot_level'}
)
session = response.json()
session_id = session['data']['session_id']

# Submit feedback
response = requests.post(
    'http://localhost:8000/api/diagnostic-support/session/feedback',
    json={
        'session_id': session_id,
        'is_fixed': False,
        'feedback_notes': 'Still investigating'
    }
)
print(response.json())
```

## Support

For questions or issues with the diagnostic workflow:
1. Check server logs: `backend/logs/`
2. Review session history in API response
3. Contact development team with session ID
4. Submit feedback through NEO Chatbot

---

**Last Updated:** January 14, 2026  
**Version:** 1.0.0  
**Author:** NEO Chatbot Development Team
