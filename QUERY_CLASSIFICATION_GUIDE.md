# Query Classification System - User Guide

## 📚 Overview

The Query Classification System stores **every SQL query** the chatbot generates, allowing you to manually review and classify them as correct/incorrect. This creates a training dataset that improves future query generation through:

1. **Smart Lookup**: Before generating new SQL, system checks classified queries
2. **Pattern Learning**: Learns from correctly classified queries
3. **Consistency**: Same questions get same (verified correct) answers
4. **Cost Reduction**: Reuses classified queries instead of calling LLM
5. **Reliability**: Human-verified queries have higher confidence

---

## 🎯 How It Works

### Automatic Storage
Every query is automatically stored with:
- User's natural language question
- Generated SQL
- Execution status (success/error)
- Number of rows returned
- System confidence score
- Tables used
- Classification status (defaults to "unclassified")

### Query Lifecycle

```
┌─────────────────┐
│  User asks      │
│  question       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 1. Check classified queries    │ ◄── Highest priority
│    (human-verified correct)     │
└─────────┬───────────────────────┘
          │ No match
          ▼
┌─────────────────────────────────┐
│ 2. Check session cache          │ ◄── Recent queries
│    (same session)                │
└─────────┬───────────────────────┘
          │ No match
          ▼
┌─────────────────────────────────┐
│ 3. Generate new SQL with LLM    │ ◄── Fallback
└─────────┬───────────────────────┘
          │
          ▼
┌─────────────────────────────────┐
│ Store for classification        │
└─────────────────────────────────┘
```

---

## 🔧 Usage

### 1. Access Classification Tool

Open in browser:
```
http://localhost:8000/classification
```

### 2. Review Unclassified Queries

The tool shows:
- **User's Question**: Natural language query
- **Generated SQL**: SQL that was generated
- **Confidence Score**: System's confidence (0-100%)
- **Results**: Number of rows returned
- **Tables Used**: Which database tables were queried

### 3. Classify Each Query

Choose one of:
- **✅ Correct**: SQL is accurate and produces expected results
- **❌ Incorrect**: SQL is wrong (can provide corrected SQL)
- **⏳ Needs Review**: Unsure, save for later review

Optional:
- Add notes explaining your decision
- Provide corrected SQL if marking as incorrect

### 4. Benefits Accumulate

Once classified:
- **Immediate reuse**: Similar future questions use this SQL
- **Pattern learning**: System learns which tables/joins work
- **Export training data**: Use for fine-tuning models

---

## 🎓 Classification Guidelines

### Mark as ✅ CORRECT when:
- SQL executes without errors
- Returns expected results
- Uses appropriate tables and joins
- Results match what user asked for
- Column names are correct

### Mark as ❌ INCORRECT when:
- SQL syntax is wrong
- Uses non-existent tables/columns
- Returns no results but should have data
- Wrong JOIN logic
- Misinterprets user's question

### Mark as ⏳ NEEDS REVIEW when:
- Unsure if results are correct
- Need to verify with database
- Question is ambiguous
- Need domain expert review

---

## 📊 API Endpoints

### Get Unclassified Queries
```http
GET /api/classification/unclassified?limit=50
```

Response:
```json
[
  {
    "query_id": "session123_20260129120000",
    "timestamp": "2026-01-29T12:00:00",
    "user_query": "Show me all bots",
    "generated_sql": "SELECT BOT_ID FROM bot_master LIMIT 100",
    "classification": "unclassified",
    "rows_returned": 42,
    "confidence": 0.85,
    "tables_used": ["bot_master"]
  }
]
```

### Classify a Query
```http
POST /api/classification/classify
Content-Type: application/json

{
  "query_id": "session123_20260129120000",
  "classification": "correct",
  "notes": "Accurate bot listing",
  "corrected_sql": null
}
```

### Get Statistics
```http
GET /api/classification/stats
```

Response:
```json
{
  "total_queries": 150,
  "correct": 120,
  "incorrect": 15,
  "needs_review": 5,
  "unclassified": 10,
  "accuracy": 0.88
}
```

### Export Training Dataset
```http
POST /api/classification/export
```

Exports all classified queries to:
```
data/training_dataset.json
```

### Search Queries
```http
GET /api/classification/search?query=bot&classification=correct&limit=20
```

---

## 💾 Data Storage

### Files Created

```
data/
├── classification/
│   ├── classified_queries.jsonl    # All queries (one per line)
│   └── learned_patterns.json       # Extracted patterns
└── training_dataset.json           # Exported training data
```

### Query Record Format
```json
{
  "query_id": "session_abc_20260129120000",
  "timestamp": "2026-01-29T12:00:00",
  "session_id": "session_abc",
  "user_query": "give me all bot ids",
  "generated_sql": "SELECT BOT_ID FROM bot_master LIMIT 100",
  "execution_status": "success",
  "rows_returned": 42,
  "confidence": 0.85,
  "tables_used": ["bot_master"],
  "classification": "correct",
  "classification_timestamp": "2026-01-29T12:05:00",
  "classification_notes": "Accurate bot listing",
  "corrected_sql": null,
  "metadata": {
    "intent": "list",
    "entities": ["bot"],
    "refinement_iterations": 1
  }
}
```

---

## 🚀 Performance Impact

### Before Classification System
```
User: "Show me bot ids"
→ LLM generates SQL (500ms, costs $0.001)
→ Returns results
```

### After Classification (2nd+ time)
```
User: "Show me bot ids" 
→ Finds similar classified query (10ms, $0)
→ Reuses verified SQL
→ Returns results

✅ 50x faster
✅ Free (no LLM call)
✅ Human-verified accuracy
```

### Expected Improvements
- **Consistency**: ↑ 95% (same questions → same SQL)
- **Cost**: ↓ 60-80% (reuse classified queries)
- **Response Time**: ↓ 90% (no LLM generation)
- **Accuracy**: ↑ 90%+ (human-verified)

---

## 📈 Workflow Example

### Day 1: Initial Queries
```
09:00 - User: "show me all bots"
        → System generates SQL, stores for classification
        
10:00 - User: "list all robots" 
        → System generates SQL, stores for classification
        
11:00 - You classify both as CORRECT
```

### Day 2: Same Questions Return
```
09:00 - User: "show me all bots"
        → 🎯 Finds classified query (similarity: 100%)
        → ♻️ Reuses verified SQL
        → ⚡ Instant response
        
10:30 - User: "get bot ids"
        → 🎯 Finds classified query (similarity: 87%)
        → ♻️ Reuses verified SQL
        → ⚡ Instant response
```

---

## 🔍 Advanced Features

### Similarity Matching
Recognizes paraphrased questions:
- "bot ids" ≈ "robot identifiers" ≈ "bot ID list"
- "completed tasks" ≈ "finished jobs" ≈ "done assignments"

Threshold: 85% similarity

### Pattern Learning
Learns from correct classifications:
- **Entity → Table**: "bot" usually needs `bot_master`
- **Intent → SQL Pattern**: "count" queries use `COUNT(*)`
- **Common JOINs**: `bot_master ⟕ task_master ON BOT_ID`

### Training Dataset Export
Generate training data for:
- Fine-tuning LLMs
- Few-shot learning
- Documentation
- Quality audits

---

## ⚠️ Best Practices

### 1. Classify Regularly
- Review queries daily or weekly
- Don't let unclassified queries pile up
- Fresh context helps accurate classification

### 2. Add Detailed Notes
```
✅ Good: "Correct - uses task_detail_log for historical data"
❌ Bad: "looks ok"
```

### 3. Provide Corrections
If marking as incorrect, provide corrected SQL:
```json
{
  "classification": "incorrect",
  "corrected_sql": "SELECT DISTINCT bot_id FROM task_detail WHERE status='COMPLETED'",
  "notes": "Original used wrong table, should use task_detail not task_master"
}
```

### 4. Review High-Confidence Errors
If system was very confident but wrong:
- Add detailed notes
- Help improve confidence scoring
- Identify systemic issues

### 5. Export Regularly
Export training dataset weekly to:
- Backup classifications
- Train new models
- Share with team

---

## 🎯 Success Metrics

Track these in the Classification Tool:

| Metric | Target | Impact |
|--------|--------|--------|
| **Accuracy** | >90% | Quality of classifications |
| **Classified/Total** | >80% | Coverage |
| **Reuse Rate** | >50% | Cost savings |
| **Avg Confidence** | >85% | System reliability |

---

## 🐛 Troubleshooting

### "Classification service unavailable"
- Check logs: `logs/neo_chatbot.log`
- Ensure `data/classification/` directory exists
- Restart server

### "No queries to classify"
- Users need to ask questions first
- Check if queries are being stored
- Verify storage path in logs

### "Export failed"
- Check write permissions on `data/` directory
- Ensure enough disk space
- Check error logs

---

## 📞 Support

For issues or questions:
1. Check logs: `logs/neo_chatbot.log`
2. Review API documentation: `http://localhost:8000/docs`
3. Examine stored queries: `data/classification/classified_queries.jsonl`

---

## 🎉 Quick Start Checklist

- [ ] Server running (`http://localhost:8000`)
- [ ] Users have asked queries (generates data)
- [ ] Open classification tool: `http://localhost:8000/classification`
- [ ] Review and classify queries
- [ ] Monitor stats dashboard
- [ ] Export training dataset weekly

**Your system will get smarter with every classification!** 🚀
