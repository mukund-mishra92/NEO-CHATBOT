# 🧪 Session Memory Testing Guide

## Quick Test Scenario

### Test 1: Cross-Section Memory

**Step 1**: Open chatbot (Knowledge Base selected)
- Send: "What is NEO?"
- ✅ Session auto-created: `0f770f17-39e` (shown in sidebar)
- ✅ Message stored with timestamp

**Step 2**: Ask follow-up (still in Knowledge Base)
- Send: "Tell me more about its features"
- ✅ Bot remembers you asked about NEO
- ✅ Response builds on previous answer

**Step 3**: Switch to SQL Assistant
- Change chatbot type to "SQL Assistant"
- Send: "Show recent orders"
- ✅ **SAME** session ID still active: `0f770f17-39e`
- ✅ Both Knowledge Base and SQL messages in same session

**Step 4**: Switch to Diagnostic Support
- Change chatbot type to "Diagnostic Support"
- Send: "How do I diagnose bot issues?"
- ✅ **SAME** session ID still active: `0f770f17-39e`
- ✅ Now has 4 messages total across 3 services

**Step 5**: Back to Knowledge Base
- Change back to "Knowledge Base"
- Send: "Can you tell me what we have discussed so far?"
- ✅ Bot responds with FULL CONTEXT:
  - "You asked about NEO and its features"
  - "You asked for recent orders from SQL"
  - "You asked about bot diagnostics"
  - "Based on all this, here's what we discussed..."

### Test 2: View Conversation History

**Step 1**: Click "History" button in sidebar
- Modal opens showing full conversation
- ✅ All 5 messages displayed
- ✅ Timestamps show proper format (e.g., "1/30/2026, 10:30:45 AM")
- ✅ User messages show 👤 icon
- ✅ Assistant messages show 🤖 icon

**Step 2**: Scroll through history
- ✅ See full context of entire session
- ✅ Messages from all 3 services mixed together
- ✅ Easy to follow conversation flow

### Test 3: Create New Session

**Step 1**: Click "New Session" button
- ✅ New session ID generated (e.g., `a1b2c3d4e5f6`)
- ✅ Chat area cleared
- ✅ Old session preserved in history

**Step 2**: Start fresh conversation
- Send: "New question"
- ✅ Only this new message in session
- ✅ Old messages NOT mixed in

**Step 3**: Go back to old session
- (No direct UI for this yet, but session data still exists on server)
- Can test via API: `/api/chatbot/session/0f770f17-39e`

### Test 4: Session Persists Across Switches

**Step 1**: Knowledge Base conversation
- Send: "What is inventory management?"
- Session: `abc123xyz789`

**Step 2**: Switch to SQL Assistant
- Send: "Show inventory levels"
- ✅ Same session ID: `abc123xyz789`
- ✅ Both messages in session

**Step 3**: Refresh page (simulate new browser visit)
- ⚠️ Note: Sessions stored in-memory currently
- Refresh clears memory (expected behavior)
- New session created on next message

## Expected Behavior

### ✅ Correct Behavior

**When asking context-aware question**:
```
User: "Can you summarize what we discussed?"
Bot: "Of course! In our conversation you:
    1. Asked about NEO features
    2. Requested SQL data
    3. Asked about diagnostics
    
    Based on this context, here's the summary..."
```

**When timestamps display**:
```
👤 USER - 1/30/2026, 10:15:30 AM
What is NEO?

🤖 ASSISTANT - 1/30/2026, 10:15:35 AM
NEO is a warehouse management system...
```

**When switching sections**:
```
Sidebar shows: Session ID: abc123xyz789 (SAME ID across all switches)
Message count increases as you ask questions in different sections
All messages stored in same session
```

## API Testing (Advanced)

### Create Session
```bash
curl -X POST http://localhost:8000/api/chatbot/session/new?session_type=knowledge_base
```
**Response**:
```json
{
    "session_id": "abc123xyz789",
    "session_type": "knowledge_base",
    "created_at": "2026-01-30T10:15:30.123456",
    "status": "active"
}
```

### Send Message
```bash
curl -X POST http://localhost:8000/api/chatbot/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is NEO?",
    "chatbot_type": "knowledge_base",
    "session_id": "abc123xyz789"
  }'
```

### Get Session History
```bash
curl http://localhost:8000/api/chatbot/session/abc123xyz789/history
```
**Response**:
```json
{
    "session_id": "abc123xyz789",
    "message_count": 2,
    "messages": [
        {
            "role": "user",
            "content": "What is NEO?",
            "timestamp": "2026-01-30T10:15:30.123456",
            "metadata": {}
        },
        {
            "role": "assistant",
            "content": "NEO is a warehouse management system...",
            "timestamp": "2026-01-30T10:15:35.234567",
            "metadata": {"confidence": 0.95}
        }
    ]
}
```

## Debugging Tips

### Issue: Timestamps still show "Invalid Date"
- Check browser console for errors
- Ensure `timestamp` field is ISO format string
- Try clearing browser cache

### Issue: Session ID changing on each message
- Check if `session_id` is being passed in request
- Verify `fetch` call includes `session_id` parameter
- Look for errors in browser network tab

### Issue: Bot doesn't remember context
- Check server logs for session creation
- Verify conversation history is being retrieved
- Look for LLM prompt to see if context included

### Issue: Messages mixed between sessions
- Check if correct `session_id` passed
- Verify old session not being reused
- Look at `/api/chatbot/sessions` to see all active sessions

## Expected Browser Console Output

When working correctly, you should see:
```
✅ New session created: 0f770f17-39e
✅ Chat response generated: confidence=0.95, session=0f770f17-39e
```

When switching sections:
```
✅ Chat response generated: confidence=0.87, session=0f770f17-39e
(same session ID!)
```

## Troubleshooting Checklist

- [ ] Timestamps display in History modal
- [ ] Session ID visible in sidebar
- [ ] Same session ID across Knowledge Base → SQL → Diagnostic
- [ ] "New Session" button works and creates new ID
- [ ] "History" button shows all messages
- [ ] Bot references previous conversation
- [ ] No "Invalid Date" errors in console
- [ ] Server logs show sessions being created
- [ ] Browser network tab shows session_id in requests

## Performance Notes

- Conversations limited to ~10,000 messages per session (in-memory)
- Sessions expire after 24 hours of inactivity
- Clearing browser cache won't affect server-side sessions
- Multiple sessions can be active simultaneously

## Next Steps

Once verified working:
1. Test with actual work scenarios
2. Monitor performance with longer conversations
3. Consider database persistence for production
4. Add session export/import features
