# Semi-Auto Diagnostic - User Guide

## What's New? 🎉

The Semi-Auto Diagnostic system now **remembers your conversation**! You can ask follow-up questions and the system will understand the context.

## Quick Start

### 1. Start a Diagnosis
1. Open the Semi-Auto Diagnostic page
2. Type your problem in the text box
   - Example: "Bot is not moving on station 5"
3. Click **"Start Diagnosis"**

### 2. Review the Solution
The system will show you:
- **Case Number**: Which solution (e.g., Case 1/3)
- **Problem Type**: BOT_LEVEL or STATION_LEVEL
- **Impact**: High, Medium, or Low
- **Solution**: Step-by-step fix
- **SQL Audit**: (if applicable) Query to verify the problem

### 3. Ask Follow-Up Questions ✨ NEW!
Instead of just accepting or rejecting, you can now **ask questions**!

**Type your question in the box at the bottom and click "Ask Question"**

## What Can You Ask?

### Understanding the Solution
❓ "Can you explain this solution?"  
❓ "How does this work?"  
❓ "Why do I need to do this?"

### About SQL Queries
❓ "What does this SQL query do?"  
❓ "Can you explain the query?"  
❓ "What am I checking with this SQL?"

### Looking for Alternatives  
❓ "Are there other solutions?"  
❓ "What else can I try?"  
❓ "Do you have alternative fixes?"

### Next Steps
❓ "What should I do next?"  
❓ "What's the next step?"  
❓ "What happens after this?"

### Understanding Results
❓ "What do these results mean?"  
❓ "Is this normal?"  
❓ "What does it mean if I got 2 rows?"

### Impact & Severity
❓ "How serious is this?"  
❓ "What's the impact of this issue?"  
❓ "Is this urgent?"

## Example Conversation

```
👤 YOU: Bot is not moving on station 5

🤖 SYSTEM: Found 3 potential solutions. Here's the most likely one.
          [Shows Case 1: Check bot error state]

👤 YOU: What does the SQL query do?

🤖 SYSTEM: The SQL query helps verify the problem by checking 
          if the bot is stuck in an error state. The query 
          checks the bot_status table for error records...

👤 YOU: Should I run it now?

🤖 SYSTEM: Next steps:
          1. Run the SQL audit to verify the problem
          2. Review the results
          3. Apply the solution if the audit confirms the issue
          4. Verify the problem is resolved

👤 YOU: [Clicks "Run SQL Audit"]

💻 SYSTEM: SQL audit completed: 2 rows found

👤 YOU: What does that mean?

🤖 SYSTEM: The SQL audit found 2 records. This confirms 
          the problem - the bot is stuck in an error state...

👤 YOU: [Clicks "✓ This Solved It"]

🤖 SYSTEM: Problem resolved successfully! ✅
```

## Conversation History

All your questions and answers are shown in the **Conversation History** section:
- **Blue messages**: Your questions
- **Purple messages**: System answers  
- **Orange messages**: System notifications (like SQL results)

Each message shows a timestamp so you can track the flow.

## Making Decisions

After reviewing the solution and asking any questions:

### ✅ If the solution worked:
Click **"✓ This Solved It"**
- System marks the problem as resolved
- Shows success message
- You can start a new diagnosis

### ❌ If the solution didn't work:
Click **"✗ Not Correct"**
- System shows the next possible solution
- You can ask questions about the new solution
- Process continues until resolved

## Tips for Best Results

### 🎯 Be Specific
**Good**: "What does the bot_status column check?"  
**Less helpful**: "Explain"

### 🎯 One Question at a Time
Ask one question, get the answer, then ask the next one.

### 🎯 Use Natural Language
You don't need to use technical terms. Ask naturally:
- "Why is this happening?"
- "What should I do if I can't access the database?"
- "Is there a simpler solution?"

### 🎯 Reference What You See
- "What does THIS SQL query do?" ✓
- "Can you explain THE SOLUTION?" ✓
- The system knows what you're referring to!

## Understanding System Responses

### When SQL Audit is Required
The system might say:
> "Click 'Run SQL Audit' to verify the problem"

This means you need to check the database first before applying the fix.

### When Multiple Solutions Exist
The system shows:
> "Case 1/3" 

This means there are 3 possible solutions. If the first doesn't work, click "Not Correct" to see the next one.

### When No More Solutions
If you've tried all solutions:
> "All known solutions tried. Escalating to development team."

This means you may need manual investigation.

## Session Information

At the top of the screen, you'll see:
```
Session ID: abc12345 | Cases Found: 3
```

- **Session ID**: Unique identifier for this diagnostic session
- **Cases Found**: How many potential solutions were matched

## Session Lifetime

Your conversation is saved for **24 hours**.

After 24 hours, the session expires and you'll need to start a new diagnosis.

## Troubleshooting

### "Session not found" Error
**Cause**: Session expired (24 hours old)  
**Solution**: Start a new diagnosis

### Follow-up Question Not Working
**Check**:
1. You started a diagnosis (not just opened the page)
2. You're connected to the server
3. Session hasn't expired

### No Response to Question
**Try**:
1. Rephrase your question
2. Be more specific
3. Ask about the current case directly

## Example Questions for Different Scenarios

### Scenario 1: Confused About the Solution
```
"I don't understand the solution. Can you break it down?"
"What's the first thing I should check?"
"Is there a simpler way to fix this?"
```

### Scenario 2: SQL Query Concerns
```
"Will this SQL query modify the database?"
"Is it safe to run this query?"
"What table does this query check?"
```

### Scenario 3: Exploring Options
```
"How reliable is this solution?"
"Has this worked for others?"
"What's the success rate of this fix?"
```

### Scenario 4: After Running SQL
```
"I got 5 rows. What does that mean?"
"The query returned nothing. Is that good or bad?"
"Should I be worried about these results?"
```

## Best Practices

### ✅ DO
- Ask questions when you're unsure
- Use the conversation history to review what was discussed
- Run SQL audits when suggested
- Provide feedback (worked/didn't work)

### ❌ DON'T
- Apply solutions you don't understand
- Skip SQL audits if they're recommended
- Forget to mark solutions as correct/incorrect
- Start a new diagnosis before completing the current one

## Getting Help

If you're still stuck after trying:
1. All suggested solutions
2. Asking follow-up questions
3. Running SQL audits

**Contact the development team** for manual investigation.

---

## Quick Reference

| Action | How |
|--------|-----|
| Start diagnosis | Type problem, click "Start Diagnosis" |
| Ask question | Type in bottom box, click "Ask Question" |
| Run SQL audit | Click "Run SQL Audit" button |
| Mark as solved | Click "✓ This Solved It" |
| Try next solution | Click "✗ Not Correct" |
| See conversation | Look at "Conversation History" section |
| Check session info | Top of screen shows session details |

---

**Remember**: The system remembers everything you discuss in the current session. Ask freely!
