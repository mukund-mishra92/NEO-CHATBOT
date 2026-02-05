# Semi-Auto Diagnostic - Session Memory Feature

## Overview
The Semi-Auto Diagnostic system now includes **session-based memory** that allows users to have conversational interactions with follow-up questions. The system remembers the entire conversation within a session.

## Key Features

### 1. **Session Management**
- Each diagnostic session gets a unique session ID
- All conversation history is stored in the session
- Sessions persist in memory (cleared after 24 hours by default)

### 2. **Conversation History**
- Every user question and assistant response is tracked
- Full context is maintained throughout the diagnostic process
- Chat history is displayed in a user-friendly format

### 3. **Follow-Up Questions**
The system can intelligently answer follow-up questions based on context:

**Supported Question Types:**
- **Explanation Questions**: "How does this solution work?", "Can you explain the SQL query?"
- **Alternative Solutions**: "Are there other solutions?", "What else can I try?"
- **Next Steps**: "What should I do next?", "What's the next step?"
- **SQL Results**: "What do the results mean?"
- **General Clarifications**: "Why is this happening?", "What if I can't do that?"

### 4. **Context-Aware Responses**
The system uses conversation history to provide relevant answers:
- References the current diagnostic case
- Recalls SQL audit results
- Understands which solution step you're on
- Provides specific guidance based on your situation

## How to Use

### Starting a Diagnosis
1. Open the Semi-Auto Diagnostic page
2. Describe your problem
3. Click "Start Diagnosis"
4. System creates a session and shows matched solutions

### During Diagnosis
1. **Review the suggested solution**
2. **Run SQL Audit** (if applicable)
3. **Ask follow-up questions** in the text box:
   - "Can you explain this SQL query?"
   - "Why do we need to run this?"
   - "What should I check next?"
4. **Mark solution as correct or try next**

### Example Conversation Flow

```
User: Bot is not moving on station 5
Assistant: Found 3 potential solutions. Here's the most likely one.
          [Shows Case 1: Check bot status in database]

User: How do I run the SQL query?
Assistant: Click the "Run SQL Audit" button. The query will check if the bot 
          is in an error state in the database...

User: The query returned 2 rows. What does that mean?
Assistant: The SQL audit found 2 records. This confirms the problem - 
          the bot is stuck in an error state...

User: What should I do next?
Assistant: Next steps:
          1. Apply the recommended solution
          2. Test to verify the problem is resolved
          3. Let me know if it worked...
```

## API Endpoints

### New Endpoints

1. **POST /api/chatbot/diagnostic/followup**
   ```
   Parameters:
   - session_id: string (required)
   - question: string (required)
   
   Returns:
   - answer: Contextual response
   - context: Current session context summary
   ```

2. **GET /api/chatbot/diagnostic/session/{session_id}**
   ```
   Returns:
   - Full conversation history
   - Session metadata
   - Current context
   - Resolution status
   ```

### Updated Endpoints

1. **POST /api/chatbot/diagnostic/feedback**
   - Now accepts `session_id` instead of `session_data`
   - Automatically updates conversation history

2. **POST /api/chatbot/diagnostic/analyze-results**
   - Now accepts optional `session_id` parameter
   - Stores SQL results in session context

## Technical Implementation

### Session Structure
```python
{
    'session_id': 'abc12345',
    'created_at': '2026-01-29T10:30:00',
    'user_problem': 'Original problem description',
    'conversation_history': [
        {
            'role': 'user',
            'message': 'Message text',
            'timestamp': '2026-01-29T10:30:00',
            'metadata': {}
        },
        ...
    ],
    'context': {
        'matched_cases': [...],
        'current_case_index': 0,
        'current_case': {...},
        'sql_results': {...},
        'user_feedback': [...]
    },
    'resolved': False
}
```

### SessionManager Class
- **create_session()**: Creates new session with unique ID
- **get_session()**: Retrieves session data
- **update_session()**: Updates session context
- **add_message()**: Adds message to conversation history
- **get_conversation_history()**: Returns full chat history
- **get_context_summary()**: Generates context summary for AI
- **clear_old_sessions()**: Removes sessions older than 24 hours

## Frontend Changes

### New UI Elements
1. **Session Info Bar**: Displays session ID and case count
2. **Chat History Container**: Shows full conversation
3. **Follow-up Input**: Text area for asking questions
4. **Message Bubbles**: Color-coded by role (user/assistant/system)

### Conversation Display
- **User messages**: Blue background
- **Assistant messages**: Purple background  
- **System messages**: Orange background (for SQL audits, etc.)
- Timestamps shown for each message
- Auto-scrolls to latest message

## Benefits

1. **Natural Interaction**: Users can ask clarifying questions
2. **Better Understanding**: Context helps provide more relevant answers
3. **Reduced Confusion**: Users can ask "why" and "how" questions
4. **Improved Learning**: Follow-up questions help users understand solutions
5. **Session Continuity**: All information stays together

## Session Management

### Automatic Cleanup
- Sessions older than 24 hours are automatically cleared
- Prevents memory buildup
- Can be configured in the service

### Manual Session Review
```python
# Get session history
GET /api/chatbot/diagnostic/session/{session_id}

# Get session summary
POST /api/chatbot/diagnostic/summary?session_id={session_id}
```

## Future Enhancements

Potential improvements:
1. Persistent storage (database/Redis) instead of in-memory
2. Session export for documentation
3. Learning from successful solutions
4. Multi-user session support
5. Session sharing between team members
6. Analytics on common questions

## Troubleshooting

### "Session not found" Error
- Session may have expired (24 hours)
- Start a new diagnosis
- Check that session_id is correct

### Follow-up Not Working
- Ensure you have an active session
- Check that diagnosis has been started
- Verify API endpoint connectivity

## Example Usage Patterns

### Pattern 1: Understanding Before Acting
```
1. Describe problem
2. Review suggested solution
3. Ask: "Can you explain this solution?"
4. Ask: "What if this doesn't work?"
5. Apply solution with confidence
```

### Pattern 2: Troubleshooting SQL
```
1. Describe problem
2. See SQL audit required
3. Ask: "What does this SQL query do?"
4. Run SQL audit
5. Ask: "What do these results mean?"
6. Apply solution based on understanding
```

### Pattern 3: Exploring Options
```
1. Describe problem
2. Review first solution
3. Ask: "Are there other solutions?"
4. Ask: "Which solution is most reliable?"
5. Choose best solution
```

---

**Note**: This feature works ONLY within a single session. Starting a new diagnosis creates a new session with no memory of previous sessions.
