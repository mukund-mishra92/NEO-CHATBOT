# Semi-Auto Diagnostic - Session Memory Architecture

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                           │
│                  (semi_auto_diagnostic.html)                     │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Problem     │  │  Chat        │  │  Follow-up   │          │
│  │  Input       │  │  History     │  │  Questions   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                │ HTTP Requests
                                ↓
┌─────────────────────────────────────────────────────────────────┐
│                         API LAYER                                │
│                   (chatbot_endpoints.py)                         │
│                                                                   │
│  /diagnostic/start          → Start new session                 │
│  /diagnostic/followup       → Answer questions (NEW)            │
│  /diagnostic/feedback       → Process feedback                   │
│  /diagnostic/session/{id}   → Get history (NEW)                 │
│  /diagnostic/summary        → Get summary                        │
│  /diagnostic/audit-sql      → Run SQL audit                      │
│  /diagnostic/analyze-results → Analyze SQL results              │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                │ Service Calls
                                ↓
┌─────────────────────────────────────────────────────────────────┐
│                      SERVICE LAYER                               │
│            (semi_automated_diagnostic_service.py)                │
│                                                                   │
│  ┌───────────────────────────────────────────────────────┐     │
│  │     SemiAutomatedDiagnosticService                     │     │
│  │                                                        │     │
│  │  • start_diagnosis()      → Create session            │     │
│  │  • handle_followup_question() → Answer with context  │     │
│  │  • handle_user_feedback() → Process feedback          │     │
│  │  • get_session_history()  → Return full history       │     │
│  │  • update_sql_results()   → Store in session          │     │
│  │  • get_session_summary()  → Generate summary          │     │
│  └────────────────────┬──────────────────────────────────┘     │
│                       │                                          │
│                       │ Uses                                     │
│                       ↓                                          │
│  ┌───────────────────────────────────────────────────────┐     │
│  │            SessionManager (NEW)                        │     │
│  │                                                        │     │
│  │  sessions = {                                          │     │
│  │    'abc123': {                                         │     │
│  │      'session_id': 'abc123',                          │     │
│  │      'user_problem': 'Bot not moving',                │     │
│  │      'conversation_history': [                        │     │
│  │        {'role': 'user', 'message': '...'},           │     │
│  │        {'role': 'assistant', 'message': '...'},      │     │
│  │      ],                                               │     │
│  │      'context': {                                     │     │
│  │        'matched_cases': [...],                       │     │
│  │        'current_case_index': 0,                      │     │
│  │        'current_case': {...},                        │     │
│  │        'sql_results': {...}                          │     │
│  │      },                                               │     │
│  │      'resolved': False                                │     │
│  │    }                                                   │     │
│  │  }                                                     │     │
│  └───────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Conversation Flow

```
┌──────────┐
│  Start   │
└────┬─────┘
     │
     ↓
┌──────────────────────────────┐
│ User describes problem       │
│ "Bot not moving"             │
└──────┬───────────────────────┘
       │
       ↓
┌──────────────────────────────┐
│ System creates session       │
│ session_id: "abc123"         │
│ Matches 3 cases              │
└──────┬───────────────────────┘
       │
       ↓
┌──────────────────────────────┐
│ Shows Case 1 (highest impact)│
│ Added to conversation history│
└──────┬───────────────────────┘
       │
       ├─────────────────────────────┐
       │                             │
       ↓                             ↓
┌──────────────────┐      ┌────────────────────┐
│ User asks:       │      │ User chooses:      │
│ "Explain SQL?"   │      │ • Solution worked  │
└──────┬───────────┘      │ • Try next         │
       │                  └────────┬───────────┘
       ↓                           │
┌──────────────────┐              │
│ System answers   │              │
│ with context     │              │
│ from session     │              │
└──────┬───────────┘              │
       │                          │
       ↓                          ↓
┌────────────────────────────────────┐
│ All interactions stored in         │
│ conversation_history               │
└────────────────────────────────────┘
       │
       ↓
┌──────────────────────────────┐
│ Session persists until:      │
│ • Problem resolved           │
│ • 24 hours elapsed           │
└──────────────────────────────┘
```

## Memory Structure

```
Session Memory (In-Memory Storage)
├── Session abc123
│   ├── Metadata
│   │   ├── session_id: "abc123"
│   │   ├── created_at: "2026-01-29T10:30:00"
│   │   ├── user_problem: "Bot not moving"
│   │   └── resolved: false
│   │
│   ├── Conversation History
│   │   ├── [0] User: "Bot not moving"
│   │   ├── [1] Assistant: "Found 3 solutions..."
│   │   ├── [2] User: "How does the SQL work?"
│   │   ├── [3] Assistant: "The SQL query checks..."
│   │   ├── [4] System: "SQL audit completed: 2 rows"
│   │   └── [5] User: "This solution worked!"
│   │
│   └── Context
│       ├── matched_cases: [Case1, Case2, Case3]
│       ├── current_case_index: 0
│       ├── current_case: {Problem, Solution, SQL...}
│       └── sql_results: {row_count: 2, data: [...]}
│
└── Session xyz789
    └── (Another user's session)
```

## Follow-up Question Processing

```
User Question: "Can you explain the SQL query?"
        │
        ↓
┌───────────────────────────────┐
│ Retrieve Session Context     │
│ • Current case details        │
│ • SQL query in context        │
│ • Previous conversation       │
└───────┬───────────────────────┘
        │
        ↓
┌───────────────────────────────┐
│ Analyze Question Type         │
│ Keywords: "explain", "SQL"    │
└───────┬───────────────────────┘
        │
        ↓
┌───────────────────────────────┐
│ Generate Context-Aware Answer │
│ • Reference current SQL query │
│ • Explain expected outcome    │
│ • Provide relevant details    │
└───────┬───────────────────────┘
        │
        ↓
┌───────────────────────────────┐
│ Store in Conversation History │
│ [User: Question]              │
│ [Assistant: Answer]           │
└───────────────────────────────┘
```

## Key Components

### 1. SessionManager
- **Purpose**: Manage all diagnostic sessions
- **Storage**: In-memory dictionary (Python dict)
- **Lifecycle**: 24 hours auto-cleanup
- **Thread-safe**: Single-threaded FastAPI (consider locks for production)

### 2. Conversation History
- **Structure**: List of message objects
- **Fields**: role, message, timestamp, metadata
- **Roles**: user, assistant, system
- **Purpose**: Full context for AI responses

### 3. Session Context
- **matched_cases**: All potential solutions found
- **current_case_index**: Which solution we're on
- **current_case**: Detailed current solution info
- **sql_results**: Latest SQL audit results

### 4. Frontend Chat UI
- **Display**: Message bubbles with colors
- **Input**: Text area for questions
- **History**: Scrollable conversation view
- **Info**: Session ID and statistics

## Message Flow Example

```
Time    | Role      | Message                          | Action
--------|-----------|----------------------------------|------------------
10:30   | User      | "Bot not moving"                 | Create session
10:30   | Assistant | "Found 3 solutions..."           | Show Case 1
10:31   | User      | "How does SQL work?"             | Process followup
10:31   | Assistant | "The SQL query checks..."        | Context answer
10:32   | System    | "SQL audit: 2 rows found"        | Store in context
10:33   | User      | "What do results mean?"          | Process followup
10:33   | Assistant | "Results confirm problem..."     | Reference context
10:34   | User      | "This worked!"                   | Mark resolved
10:34   | Assistant | "Problem resolved! ✅"           | Close session
```

## Advantages of This Architecture

1. **Stateless API** - Session data stored server-side
2. **Context Preservation** - Full conversation available
3. **Scalable Design** - Easy to move to Redis/DB
4. **Clean Separation** - UI, API, Service, Storage layers
5. **Extensible** - Easy to add new question types

## Future Scalability

```
Current: In-Memory Storage (Dict)
    ↓
    ├─→ Redis (Cache)
    ├─→ PostgreSQL (Persistent)
    └─→ MongoDB (Document Store)
```

For production with multiple servers:
- Use Redis for session storage
- Enable session sharing across instances
- Add session expiration policies
- Implement backup/restore mechanisms
