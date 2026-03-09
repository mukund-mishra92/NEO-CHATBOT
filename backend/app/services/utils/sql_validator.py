"""
SQL Validator - Pre-execution validation to catch errors early
"""
import sqlparse
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass

@dataclass
class ValidationResult:
    """Validation result with details"""
    is_valid: bool
    confidence: float  # 0.0 to 1.0
    issues: List[str]
    suggestions: List[str]
    estimated_rows: int
    risk_level: str  # 'low', 'medium', 'high'

class SQLValidator:
    """
    Multi-level SQL validation before execution
    """
    
    def __init__(self, schema_registry, db_config):
        self.schema_registry = schema_registry
        self.db_config = db_config
        
    def validate(self, sql: str, question: str) -> ValidationResult:
        """
        Comprehensive validation with confidence scoring
        
        Returns:
            ValidationResult with validity, confidence, and suggestions
        """
        issues = []
        suggestions = []
        confidence = 1.0  # Start with perfect confidence
        
        # 1. SYNTAX CHECK
        syntax_valid = self._check_syntax(sql)
        if not syntax_valid:
            issues.append("SQL syntax error")
            suggestions.append("Check for missing commas, unclosed quotes, or invalid keywords")
            return ValidationResult(
                is_valid=False,
                confidence=0.0,
                issues=issues,
                suggestions=suggestions,
                estimated_rows=0,
                risk_level='high'
            )
        
        # 2. TABLE EXISTENCE CHECK
        tables_used = self._extract_tables(sql)
        invalid_tables = []
        for table in tables_used:
            if not self._table_exists(table):
                invalid_tables.append(table)
                issues.append(f"Table '{table}' does not exist")
                confidence -= 0.3
        
        if invalid_tables:
            # Try to suggest correct table names
            for invalid_table in invalid_tables:
                suggested = self._suggest_correct_table(invalid_table)
                if suggested:
                    suggestions.append(f"Did you mean '{suggested}' instead of '{invalid_table}'?")
            
            if confidence <= 0.3:
                return ValidationResult(
                    is_valid=False,
                    confidence=max(0.0, confidence),
                    issues=issues,
                    suggestions=suggestions,
                    estimated_rows=0,
                    risk_level='high'
                )
        
        # 3. COLUMN EXISTENCE CHECK
        invalid_columns = self._check_columns(sql, tables_used)
        if invalid_columns:
            for table, cols in invalid_columns.items():
                issues.append(f"Invalid columns in {table}: {', '.join(cols)}")
                confidence -= 0.2
                
                # Suggest correct columns
                for col in cols:
                    suggested = self._suggest_correct_column(table, col)
                    if suggested:
                        suggestions.append(f"In {table}, use '{suggested}' instead of '{col}'")
        
        # 4. JOIN VALIDATION
        join_issues = self._validate_joins(sql, tables_used)
        if join_issues:
            issues.extend(join_issues)
            confidence -= 0.1
        
        # 5. QUERY COMPLEXITY CHECK
        estimated_rows = self._estimate_query_cost(sql, tables_used)
        risk_level = 'low'
        
        if estimated_rows > 10_000_000:
            issues.append(f"Query may scan {estimated_rows:,} rows - very expensive")
            suggestions.append("Add WHERE clause with date range or other filters")
            confidence -= 0.15
            risk_level = 'high'
        elif estimated_rows > 1_000_000:
            issues.append(f"Query may scan {estimated_rows:,} rows")
            suggestions.append("Consider adding filters for better performance")
            confidence -= 0.05
            risk_level = 'medium'
        
        # 6. DANGEROUS OPERATIONS CHECK
        dangerous = self._check_dangerous_operations(sql)
        if dangerous:
            issues.append(f"Dangerous operation detected: {dangerous}")
            suggestions.append("Only SELECT queries are allowed")
            return ValidationResult(
                is_valid=False,
                confidence=0.0,
                issues=issues,
                suggestions=suggestions,
                estimated_rows=0,
                risk_level='high'
            )
        
        # 7. SEMANTIC VALIDATION (Does query match question intent?)
        semantic_confidence = self._validate_semantic_match(sql, question, tables_used)
        confidence = (confidence + semantic_confidence) / 2
        
        # Final decision
        is_valid = confidence >= 0.5 and not any(
            'does not exist' in issue for issue in issues
        )
        
        return ValidationResult(
            is_valid=is_valid,
            confidence=max(0.0, min(1.0, confidence)),
            issues=issues,
            suggestions=suggestions,
            estimated_rows=estimated_rows,
            risk_level=risk_level
        )
    
    def _check_syntax(self, sql: str) -> bool:
        """Validate SQL syntax using sqlparse"""
        try:
            parsed = sqlparse.parse(sql)
            return len(parsed) > 0 and parsed[0].get_type() in ['SELECT', 'SHOW', 'DESCRIBE']
        except:
            return False
    
    def _extract_tables(self, sql: str) -> List[str]:
        """Extract table names from SQL"""
        # Simple regex-based extraction
        # In production, use proper SQL parser
        from_pattern = r'FROM\s+(\w+)'
        join_pattern = r'JOIN\s+(\w+)'
        
        tables = []
        tables.extend(re.findall(from_pattern, sql, re.IGNORECASE))
        tables.extend(re.findall(join_pattern, sql, re.IGNORECASE))
        
        return list(set([t.lower() for t in tables]))
    
    def _table_exists(self, table_name: str) -> bool:
        """Check if table exists in schema"""
        return table_name.lower() in [t.lower() for t in self.schema_registry.tables.keys()]
    
    def _suggest_correct_table(self, wrong_table: str) -> Optional[str]:
        """Suggest correct table name using fuzzy matching"""
        from difflib import get_close_matches
        
        all_tables = list(self.schema_registry.tables.keys())
        matches = get_close_matches(wrong_table, all_tables, n=1, cutoff=0.6)
        
        return matches[0] if matches else None
    
    def _check_columns(self, sql: str, tables: List[str]) -> Dict[str, List[str]]:
        """
        Check if columns exist in tables
        
        Returns:
            Dict of {table: [invalid_columns]}
        """
        invalid = {}
        
        # Extract SELECT columns
        select_pattern = r'SELECT\s+(.*?)\s+FROM'
        match = re.search(select_pattern, sql, re.IGNORECASE | re.DOTALL)
        
        if not match:
            return invalid
        
        select_clause = match.group(1)
        
        # Parse column references (simplified - handle table.column)
        for table in tables:
            table_obj = self.schema_registry.tables.get(table)
            if not table_obj:
                continue
            
            valid_columns = [c['name'].lower() for c in table_obj.columns]
            
            # Find column references for this table
            pattern = f"{table}\\.(\w+)"
            column_refs = re.findall(pattern, sql, re.IGNORECASE)
            
            invalid_cols = [col for col in column_refs if col.lower() not in valid_columns]
            
            if invalid_cols:
                invalid[table] = invalid_cols
        
        return invalid
    
    def _suggest_correct_column(self, table: str, wrong_column: str) -> Optional[str]:
        """Suggest correct column name"""
        from difflib import get_close_matches
        
        table_obj = self.schema_registry.tables.get(table)
        if not table_obj:
            return None
        
        all_columns = [c['name'] for c in table_obj.columns]
        matches = get_close_matches(wrong_column, all_columns, n=1, cutoff=0.6)
        
        return matches[0] if matches else None
    
    def _validate_joins(self, sql: str, tables: List[str]) -> List[str]:
        """Validate JOIN relationships"""
        issues = []
        
        # Check if joins are using valid foreign key relationships
        # This is simplified - in production, check schema registry for relationships
        join_pattern = r'JOIN\s+(\w+)\s+ON\s+([\w.]+)\s*=\s*([\w.]+)'
        joins = re.findall(join_pattern, sql, re.IGNORECASE)
        
        for table, left_col, right_col in joins:
            # Check if join columns exist
            # In production, verify against schema registry relationships
            pass
        
        return issues
    
    def _estimate_query_cost(self, sql: str, tables: List[str]) -> int:
        """Estimate number of rows query will scan"""
        # Simplified estimation
        # In production, use EXPLAIN or actual table statistics
        
        total_rows = 0
        
        for table in tables:
            table_obj = self.schema_registry.tables.get(table)
            if table_obj:
                # Estimate based on table type
                if 'master' in table.lower():
                    estimated = 10000  # Master data tables
                elif 'log' in table.lower() or 'history' in table.lower():
                    estimated = 1000000  # Transaction logs
                else:
                    estimated = 100000  # Default
                
                total_rows += estimated
        
        # Check if WHERE clause exists to reduce estimate
        if 'WHERE' in sql.upper():
            total_rows = int(total_rows * 0.1)  # Assume WHERE reduces by 90%
        
        return total_rows
    
    def _check_dangerous_operations(self, sql: str) -> Optional[str]:
        """Check for dangerous SQL operations"""
        dangerous_keywords = ['DROP', 'DELETE', 'TRUNCATE', 'ALTER', 'GRANT', 'REVOKE']
        
        sql_upper = sql.upper()
        
        for keyword in dangerous_keywords:
            if keyword in sql_upper:
                return keyword
        
        return None
    
    def _validate_semantic_match(
        self, 
        sql: str, 
        question: str, 
        tables: List[str]
    ) -> float:
        """
        Check if generated SQL semantically matches the question
        
        Returns:
            Confidence score 0.0 to 1.0
        """
        confidence = 0.5  # Base confidence
        
        # Check if question keywords are reflected in SQL
        question_lower = question.lower()
        sql_lower = sql.lower()
        
        # Look for key entities in question
        important_keywords = ['customer', 'inventory', 'sales', 'order', 'product', 'sku']
        
        for keyword in important_keywords:
            if keyword in question_lower:
                # Check if related table is used
                if keyword in sql_lower or any(keyword in t for t in tables):
                    confidence += 0.1
        
        # Check for aggregation keywords
        if any(word in question_lower for word in ['total', 'sum', 'count', 'average', 'top']):
            if any(word in sql_lower for word in ['sum', 'count', 'avg', 'group by', 'order by']):
                confidence += 0.1
        
        # Check for time-based queries
        if any(word in question_lower for word in ['today', 'yesterday', 'this month', 'last month']):
            if 'date' in sql_lower or 'timestamp' in sql_lower:
                confidence += 0.1
        
        return min(1.0, confidence)