# SQL Generation Conditions & Rules
**Last Updated**: March 23, 2026
**Status**: Reference document — active prompt logic lives in `universal_sql_prompt.py`

---

## Core Rules (Enforced by System)

1. **Schema-only tables**: Only use tables present in the SCHEMA CONTEXT provided to the LLM.
2. **Schema-only columns**: Only use columns that exist in each table's verified column list.
3. **Value range awareness**: Use valid enum values (e.g., STATUS = 'ENABLED' not 'ACTIVE').
4. **Automatic JOIN detection**: System detects when single or multi-table JOINs are required.
5. **Single SQL per query**: System generates one SQL query per user question.
6. **Entity normalization**: System resolves "bot 1" / "BOT01" / "BOT-001" to correct BOT_ID values.
7. **Table priority**: `table_priority_validations.jsonl` (human-validated) overrides semantic selection.
8. **Learning loop**: Classified queries (`classified_queries.jsonl`) improve future table selection.

## Multi-Tenant Composite Key Rules (Added March 2026)

9. **`host-location` in every table**: All tables have a `host-location` column (requires backtick escaping).
10. **Composite primary keys**: Every table's true PK = (original_PK + `host-location`).
11. **No COUNT(DISTINCT id)**: IDs repeat across sites — use COUNT(*) with site filter instead.
12. **JOINs must include `host-location`**: Prevents cross-site data pollution.
13. **Tenant filter is programmatic**: `_inject_tenant_filter()` adds WHERE after LLM generation.
14. **Smart aggregate fallback**: Aggregate queries with no site → all-sites; specific queries → default site (frk).

## Security Rules (Enforced by Validator)

15. **Read-only only**: SELECT and WITH (CTE) statements only.
16. **No write operations**: INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, TRUNCATE blocked.
17. **No dangerous functions**: SLEEP, BENCHMARK, LOAD_FILE, INTO OUTFILE blocked.
18. **LIMIT required**: All non-aggregation queries must include LIMIT clause.
19. **Schema validation**: Every table and column in generated SQL checked against schema CSV.

## Pipeline Order

```
User Query → QueryPreprocessor (entities + tenant) → Cache Check → Reuse Engine Check
→ Table Selection (priority → learned → semantic) → Schema Enrichment
→ RetryEngine (max 3: LLM generate → validate → execute)
→ _inject_tenant_filter() → Re-execute → SemanticValidator → Format + Learn
```