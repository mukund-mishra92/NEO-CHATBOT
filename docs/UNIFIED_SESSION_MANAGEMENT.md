# Unified Session Management System

## Overview

The NEO Chatbot now has a **unified session management system** that provides ChatGPT-like conversation memory across all chatbot sections. Every conversation is tracked in a persistent session, allowing the chatbot to remember context and provide more intelligent, context-aware responses.

## Features

### 🎯 Core Capabilities

1. **Persistent Memory**: Conversations are stored in sessions that persist across all interactions
2. **Cross-Section Support**: Works seamlessly across all chatbot types:
   - Knowledge Base
   - SQL Assistant
   - Diagnostic Support
   - Semi-Auto Diagnostic
   - Intelligent Diagnostic
   - Agentic AI
3. **Automatic Session Creation**: Sessions are created automatically on first message
4. **Session Controls**: Users can create new sessions or view conversation history
5. **Context-Aware Responses**: The chatbot uses conversation history to provide better answers

### 🔄 Session Lifecycle

```
User Opens Chatbot
      ↓
First Message Sent
      ↓
Session Auto-Created
      ↓
All Messages Tracked
      ↓
Session Active (24hrs)
      ↓
User Can Create New Session
```

## Architecture

### Backend Components

#### 1. Unified Session Manager (`backend/app/utils/session_manager.py`)

**Purpose**: Centralized session management for all chatbot services

**Key Classes**:
- `UnifiedSessionManager`: Main session manager class
- `SessionType`: Enum for different chatbot types

**Key Methods**:
```python
# Create new session
session_id = session_manager.create_session(
    session_type=SessionType.KNOWLEDGE_BASE,
    initial_message="User's first question"
)

# Add message to conversation
session_manager.add_message(
    session_id=session_id,
    role='user',  # or 'assistant', 'system'
    message="User message",
    metadata={'confidence': 0.95}
)

# Get conversation history
history = session_manager.get_conversation_history(
    session_id=session_id,
    last_n=10  # Optional: get last N messages
)

# Get formatted context for LLM
llm_context = session_manager.get_context_for_llm(
    session_id=session_id,
    max_messages=10
)

# End session (marks inactive but preserves data)
session_manager.end_session(session_id)

# Delete session permanently
session_manager.delete_session(session_id)
```

**Session Data Structure**:
```python
{
    'session_id': 'abc123def456',
    'session_type': 'knowledge_base',
    'created_at': '2026-01-30T10:00:00',
    'last_updated': '2026-01-30T10:15:00',
    'conversation_history': [
        {
            'role': 'user',
            'content': 'What is NEO?',
            'timestamp': '2026-01-30T10:00:00',
            'metadata': {}
        },
        {
            'role': 'assistant',
            'content': 'NEO is a warehouse management system...',
            'timestamp': '2026-01-30T10:00:05',
            'metadata': {'confidence': 0.95, 'sources': [...]}
        }
    ],
    'context': {},  # Custom metadata per service
    'active': True,
    'message_count': 2
}
```

#### 2. Updated Services

**Knowledge Base Service** (`backend/app/services/knowledge_base_service.py`):
- Imports `get_session_manager()` and `SessionType`
- Creates/retrieves session at start of `process_query()`
- Adds user message to session
- Passes conversation history to LLM for context
- Stores assistant response with metadata

**SQL Assistant Service** (`backend/app/services/sql_assistant_service.py`):
- Same pattern as Knowledge Base
- Session tracks SQL queries and results
- Conversation history helps with query refinement
- Follow-up questions leverage previous context

**Diagnostic Services**:
- All diagnostic services follow the same pattern
- Session tracks diagnosis progress
- Previous interactions inform new suggestions

#### 3. API Endpoints (`backend/app/api/chatbot_endpoints.py`)

**New Unified Session Endpoints**:

```python
# Create new session
POST /api/chatbot/session/new?session_type=knowledge_base
Response: {
    "session_id": "abc123def456",
    "session_type": "knowledge_base",
    "created_at": "2026-01-30T10:00:00",
    "status": "active"
}

# Get session details
GET /api/chatbot/session/{session_id}
Response: {
    "session_id": "abc123def456",
    "session_type": "knowledge_base",
    "created_at": "2026-01-30T10:00:00",
    "conversation_history": [...],
    "message_count": 5,
    "active": true
}

# Get conversation history
GET /api/chatbot/session/{session_id}/history?last_n=10
Response: {
    "session_id": "abc123def456",
    "message_count": 5,
    "messages": [...]
}

# End session (mark inactive)
POST /api/chatbot/session/{session_id}/end
Response: {
    "status": "success",
    "message": "Session abc123def456 ended"
}

# Delete session permanently
DELETE /api/chatbot/session/{session_id}
Response: {
    "status": "success",
    "message": "Session abc123def456 deleted"
}

# List all active sessions
GET /api/chatbot/sessions?session_type=knowledge_base
Response: {
    "count": 3,
    "sessions": [...]
}

# Get session statistics
GET /api/chatbot/sessions/stats
Response: {
    "statistics": {
        "total": 10,
        "active": 7,
        "inactive": 3,
        "by_type": {
            "knowledge_base": 4,
            "sql_assistant": 3
        }
    }
}
```

### Frontend Components

#### 1. Session Controls UI (`frontend/chatbot.html`)

**Sidebar Updates**:
```html
<!-- Session Controls Section -->
<h3><i class="fas fa-history"></i> Session Controls</h3>

<div class="stat-card" style="background: gradient; color: white;">
    <h4>Current Session</h4>
    <p id="currentSessionId">No active session</p>
    <small>Session memory active</small>
</div>

<div style="display: flex; gap: 10px;">
    <button onclick="createNewSession()">
        <i class="fas fa-plus"></i> New Session
    </button>
    <button onclick="viewSessionHistory()">
        <i class="fas fa-history"></i> History
    </button>
</div>
```

#### 2. JavaScript Functions

**Session Management**:
```javascript
// Create new session
async function createNewSession() {
    const sessionType = sessionTypeMap[currentChatbotType];
    const response = await fetch(`/api/chatbot/session/new?session_type=${sessionType}`, {
        method: 'POST'
    });
    const data = await response.json();
    sessionId = data.session_id;
    // Update UI...
}

// View conversation history
async function viewSessionHistory() {
    const response = await fetch(`/api/chatbot/session/${sessionId}/history`);
    const data = await response.json();
    // Display in modal...
}

// Auto-create session on first message
async function sendMessage() {
    if (!sessionId) {
        await createNewSession();
    }
    // Continue with message send...
}
```

**Message Handling**:
```javascript
// Updated to maintain session across messages
const response = await fetch('/api/chatbot/chat', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        message: message,
        chatbot_type: currentChatbotType,
        session_id: sessionId,  // <-- Session ID passed
        conversation_history: []
    })
});
```

## User Experience

### Session Flow

1. **User Opens Chatbot**
   - No active session yet
   - UI shows "No active session"

2. **User Sends First Message**
   - System auto-creates session
   - Session ID displayed in sidebar
   - Message sent with session context

3. **Conversation Continues**
   - All messages tracked in session
   - Bot remembers previous context
   - Responses are more intelligent

4. **User Actions**:
   - **New Session**: Starts fresh conversation
   - **View History**: Opens modal with all messages
   - **Clear Chat**: Clears UI but keeps session active
   - **Switch Section**: Session persists across switches

### Example Conversation Flow

**Knowledge Base Example**:
```
User: "What is NEO?"
Bot: "NEO is a warehouse management system..." [stored in session]

User: "How does it work?"
Bot: "Building on what I mentioned about NEO, it works by..." [uses session context]

User: "What about the mining engine?"
Bot: "The mining engine I mentioned is part of NEO's core..." [full context]
```

**SQL Assistant Example**:
```
User: "Show me top customers"
Bot: [Generates SQL query] "Here are the top 10 customers..." [stored in session]

User: "Now filter by last month"
Bot: [Refines previous query with context] "Here are last month's top customers..." [uses session]

User: "Add revenue column"
Bot: [Further refines] "Updated query with revenue..." [full context awareness]
```

## Benefits

### For Users
✅ **Natural Conversations**: No need to repeat context
✅ **Follow-up Questions**: Bot understands "what I asked" or "that solution"
✅ **Session Persistence**: Can switch sections and return
✅ **History View**: Review entire conversation anytime
✅ **Fresh Start**: Easy to create new session when needed

### For System
✅ **Better Context**: LLMs have full conversation history
✅ **Improved Accuracy**: Context-aware responses are more relevant
✅ **Reduced Errors**: Less confusion from out-of-context questions
✅ **Analytics**: Track conversation patterns and user behavior
✅ **Debugging**: Full conversation logs for troubleshooting

## Technical Details

### Session Storage
- **Type**: In-memory dictionary (Python `Dict[str, Dict[str, Any]]`)
- **Lifecycle**: 24 hours for inactive sessions
- **Cleanup**: Automatic cleanup of old sessions
- **Scale**: Suitable for single-server deployments

### Session ID Format
- **Length**: 12 characters
- **Format**: UUID prefix (e.g., `abc123def456`)
- **Uniqueness**: Guaranteed unique per session

### Memory Management
- Sessions auto-expire after 24 hours of inactivity
- Inactive sessions are preserved but marked
- Cleanup runs periodically to remove old sessions

### Future Enhancements
🔮 **Redis Integration**: For distributed deployments
🔮 **Database Persistence**: Store sessions in database
🔮 **Session Export**: Download conversation history
🔮 **Session Sharing**: Share sessions between users
🔮 **Advanced Analytics**: Conversation flow analysis

## Migration Notes

### From Old System to Unified Sessions

**Before** (Semi-Auto Diagnostic only):
```python
# Each service had own session management
class SemiAutomatedDiagnosticService:
    def __init__(self):
        self.sessions = {}  # Local storage
```

**After** (All Services):
```python
# All services use unified manager
from ..utils.session_manager import get_session_manager

class AnyService:
    def __init__(self):
        self.session_manager = get_session_manager()  # Shared
```

**Benefits**:
- Single source of truth for sessions
- Consistent API across all services
- Better code maintainability
- Easier to add new features

## Testing

### Manual Testing Steps

1. **Test Session Creation**:
   - Open chatbot
   - Send first message
   - Verify session ID appears in sidebar

2. **Test Memory**:
   - Send "What is NEO?"
   - Send "How does it work?" (without context)
   - Verify bot uses previous context

3. **Test New Session**:
   - Click "New Session"
   - Verify new session ID
   - Verify fresh conversation starts

4. **Test History**:
   - Send several messages
   - Click "History"
   - Verify all messages shown

5. **Test Cross-Section**:
   - Start conversation in Knowledge Base
   - Switch to SQL Assistant
   - Switch back to Knowledge Base
   - Verify session persists

### API Testing

```bash
# Create session
curl -X POST http://localhost:8000/api/chatbot/session/new?session_type=knowledge_base

# Send message
curl -X POST http://localhost:8000/api/chatbot/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is NEO?", "session_id": "abc123def456", "chatbot_type": "knowledge_base"}'

# Get history
curl http://localhost:8000/api/chatbot/session/abc123def456/history

# End session
curl -X POST http://localhost:8000/api/chatbot/session/abc123def456/end
```

## Troubleshooting

### Common Issues

**Issue**: Session not persisting
- **Cause**: Server restart clears memory
- **Solution**: Sessions in memory are temporary; use Redis for production

**Issue**: Old messages not showing in history
- **Cause**: Session expired or deleted
- **Solution**: Sessions expire after 24 hours; create new session

**Issue**: Bot doesn't remember context
- **Cause**: Session ID not passed to API
- **Solution**: Check frontend passes `session_id` in request

## Configuration

### Session Cleanup

Adjust cleanup interval in `session_manager.py`:
```python
# Default: 24 hours
session_manager.clear_old_sessions(max_age_hours=24)
```

### History Limits

Adjust context window in services:
```python
# Get last 10 messages for LLM context
conversation_history = session_manager.get_context_for_llm(
    session_id,
    max_messages=10  # Adjust based on token limits
)
```

## Summary

The unified session management system transforms the NEO Chatbot from a stateless request-response system into a **ChatGPT-like conversational AI** with full memory and context awareness. This significantly improves user experience and response quality across all chatbot sections.

**Key Achievement**: Users can now have natural, flowing conversations with the chatbot, and it will remember everything discussed within the session.
