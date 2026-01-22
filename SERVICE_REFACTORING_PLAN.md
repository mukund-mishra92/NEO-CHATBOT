# Service Refactoring Plan

## Problem
- `diagnostic_support_service.py`: 700 lines, 19 methods
- `sql_assistant_service.py`: 3,629 lines, 50+ methods
- Both violate Single Responsibility Principle
- Hard to test, maintain, and extend

## Solution: Module Breakdown

### 1. Diagnostic Support Service Refactoring

**Before:** 1 monolithic file
**After:** 5 focused modules

```
backend/app/services/diagnostic/
├── __init__.py                        # Public API
├── csv_loader.py                      # CSV loading & parsing (3 methods)
├── issue_search.py                    # Search & matching logic (4 methods)
├── session_manager.py                 # Step-by-step workflow (4 methods)
├── report_formatter.py                # Output formatting (3 methods)
└── text_utils.py                      # Text cleaning & parsing (5 methods)
```

**Responsibilities:**
- `csv_loader.py`: Load bot/station CSVs, handle encodings, build issue records
- `issue_search.py`: Keyword search, scoring, filtering, recommendations
- `session_manager.py`: Session CRUD, step navigation, feedback handling
- `report_formatter.py`: Format reports, statistics, diagnostic output
- `text_utils.py`: Clean text, parse steps, parse SQL, normalize bullets

### 2. SQL Assistant Service Refactoring

**Before:** 1 massive 3,629-line file
**After:** 12 focused modules

```
backend/app/services/sql_assistant/
├── __init__.py                        # Public API
├── core.py                            # Main SQLAssistantService (coordinator)
├── schema/
│   ├── __init__.py
│   ├── parser.py                      # Schema loading & parsing (6 methods)
│   ├── validator.py                   # Table/column validation (8 methods)
│   └── discovery.py                   # Table discovery & joins (5 methods)
├── query/
│   ├── __init__.py
│   ├── generator.py                   # SQL generation strategies (4 methods)
│   ├── extractor.py                   # Extract SQL from LLM (3 methods)
│   ├── validator.py                   # Query value validation (4 methods)
│   └── executor.py                    # Safe query execution (2 methods)
├── intent/
│   ├── __init__.py
│   ├── classifier.py                  # Intent classification (2 methods)
│   └── temporal.py                    # Temporal scope detection (2 methods)
├── context/
│   ├── __init__.py
│   ├── session_cache.py               # Session query cache (3 methods)
│   └── conversation.py                # Conversation context (4 methods)
├── judge/
│   ├── __init__.py
│   └── llm_judge.py                   # Query quality judging (3 methods)
└── prompts/
    ├── __init__.py
    └── prompt_builder.py              # System prompt construction (5 methods)
```

**Responsibilities:**
- `core.py`: Orchestrates all components, main process_query method
- `schema/`: All schema-related operations
- `query/`: SQL generation, extraction, validation, execution
- `intent/`: User intent classification and temporal detection
- `context/`: Session management and conversation history
- `judge/`: LLM-as-judge for query refinement
- `prompts/`: Centralized prompt engineering

## Benefits

1. **Maintainability**: Each file < 300 lines, single purpose
2. **Testability**: Easy to unit test isolated components
3. **Readability**: Clear module names describe function
4. **Extensibility**: Add new validators/strategies without touching core
5. **Team Collaboration**: Multiple devs can work on different modules
6. **Reusability**: Components can be imported independently

## Migration Strategy

### Phase 1: Create new structure (non-breaking)
- Create new module folders
- Extract and move code to focused files
- Keep old services working

### Phase 2: Update imports (breaking)
- Update imports in routes/other services
- Run tests to verify functionality
- Remove old monolithic files

### Phase 3: Cleanup
- Remove duplicate code
- Add module-level documentation
- Update API documentation

## Backward Compatibility

Old imports will work via `__init__.py` re-exports:
```python
# backend/app/services/diagnostic/__init__.py
from .core import DiagnosticSupportService
__all__ = ['DiagnosticSupportService']
```

Existing code using:
```python
from app.services.diagnostic_support_service import DiagnosticSupportService
```

Will continue to work until Phase 2.

## Implementation Priority

1. ✅ SQL Assistant (highest impact - 3,629 lines)
2. ✅ Diagnostic Support (moderate - 700 lines)

Would you like me to proceed with implementation?
