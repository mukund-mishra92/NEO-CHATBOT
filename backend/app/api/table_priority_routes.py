"""
Table Priority Validation Routes
API endpoints for testing queries, validating table selections, and managing priorities
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Optional, Any
import json
import os
from datetime import datetime
from pathlib import Path

from app.core.config import settings

# Import the SQL engine for testing
from ..services.sql_engine import SQLEngine

router = APIRouter(prefix="/api/table-priority", tags=["table-priority"])

# Get project root directory (3 levels up from this file)
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent

# Get OpenAI config from environment
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
SQL_MODEL = os.getenv("SQL_GENERATION_MODEL", "gpt-4o")
SCHEMA_CSV_PATH = os.getenv("NEO_SCHEMA_CSV_PATH", str(PROJECT_ROOT / "data" / "database" / "Table_information.csv"))

# Storage paths
VALIDATIONS_FILE = PROJECT_ROOT / "data" / "database" / "table_priority_validations.jsonl"
PRIORITIES_FILE = PROJECT_ROOT / "data" / "database" / "table_priority_settings.json"

# Ensure directory exists
VALIDATIONS_FILE.parent.mkdir(parents=True, exist_ok=True)


class TestQueryRequest(BaseModel):
    query: str


class ValidateTableRequest(BaseModel):
    query: str
    table_name: str
    is_correct: bool


class PrioritySettings(BaseModel):
    priorities: Dict[str, float]


class ValidationRecord:
    def __init__(self, query: str, table_name: str, is_correct: bool):
        self.query = query
        self.table_name = table_name
        self.is_correct = is_correct
        self.timestamp = datetime.now().isoformat()
    
    def to_dict(self):
        return {
            "query": self.query,
            "table_name": self.table_name,
            "is_correct": self.is_correct,
            "timestamp": self.timestamp
        }


def save_validation(validation: ValidationRecord):
    """Append validation to JSONL file"""
    try:
        with open(VALIDATIONS_FILE, 'a', encoding='utf-8') as f:
            f.write(json.dumps(validation.to_dict()) + '\n')
        return True
    except Exception as e:
        print(f"Error saving validation: {e}")
        return False


def load_validations() -> List[Dict]:
    """Load all validations from JSONL file"""
    validations = []
    
    if not VALIDATIONS_FILE.exists():
        return validations
    
    try:
        with open(VALIDATIONS_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    validations.append(json.loads(line))
    except Exception as e:
        print(f"Error loading validations: {e}")
    
    return validations


def get_validation_rules() -> Dict[str, Dict[str, List[str]]]:
    """
    Convert validations to query-specific rules
    Returns: {query: {correct_tables: [...], incorrect_tables: [...]}}
    """
    validations = load_validations()
    rules = {}
    
    for v in validations:
        query = v['query'].lower().strip()
        table = v['table_name']
        is_correct = v['is_correct']
        
        if query not in rules:
            rules[query] = {'correct_tables': [], 'incorrect_tables': []}
        
        if is_correct and table not in rules[query]['correct_tables']:
            rules[query]['correct_tables'].append(table)
        elif not is_correct and table not in rules[query]['incorrect_tables']:
            rules[query]['incorrect_tables'].append(table)
    
    return rules


def load_priority_settings() -> Dict[str, float]:
    """Load custom priority settings"""
    default_priorities = {
        'bot_master': 3.0,
        'station_master': 3.0,
        'config_master': 1.5,
        'log_table': 0.5,
        'telemetry_table': 0.2,
        'general_table': 1.0
    }
    
    if not PRIORITIES_FILE.exists():
        return default_priorities
    
    try:
        with open(PRIORITIES_FILE, 'r', encoding='utf-8') as f:
            custom_priorities = json.load(f)
            return {**default_priorities, **custom_priorities}
    except Exception as e:
        print(f"Error loading priorities: {e}")
        return default_priorities


def save_priority_settings(priorities: Dict[str, float]) -> bool:
    """Save custom priority settings"""
    try:
        with open(PRIORITIES_FILE, 'w', encoding='utf-8') as f:
            json.dump(priorities, f, indent=2)
        return True
    except Exception as e:
        print(f"Error saving priorities: {e}")
        return False


@router.post("/test-query")
async def test_query(request: TestQueryRequest):
    """
    Test a query and get ranked tables with scores
    """
    try:
        query = request.query.strip()
        
        if not query:
            raise ValueError("Query cannot be empty")
        
        # Check if API key is available
        if not OPENAI_API_KEY:
            error_msg = f"OpenAI API key not configured. Please set OPENAI_API_KEY environment variable."
            print(f"❌ ERROR: {error_msg}")
            return {
                "success": False,
                "error": error_msg
            }
        
        # Check schema CSV path
        if not os.path.exists(SCHEMA_CSV_PATH):
            error_msg = f"Schema CSV not found at {SCHEMA_CSV_PATH}. Please ensure Table_information.csv exists."
            print(f"❌ ERROR: {error_msg}")
            return {
                "success": False,
                "error": error_msg
            }
        
        print(f"📝 Testing query: {query}")
        print(f"📚 Using schema CSV: {SCHEMA_CSV_PATH}")
        print(f"🤖 Using model: {SQL_MODEL}")
        
        # Initialize SQL engine with API key and model
        try:
            engine = SQLEngine(
                api_key=OPENAI_API_KEY,
                model=SQL_MODEL,
                schema_csv_path=SCHEMA_CSV_PATH
            )
        except Exception as e:
            error_msg = f"Failed to initialize SQL engine: {str(e)}"
            print(f"❌ ENGINE ERROR: {error_msg}")
            return {
                "success": False,
                "error": error_msg
            }
        
        # Get ranked tables (top 8)
        try:
            ranked_tables = engine.get_ranked_tables_for_query(query, top_k=8)
            print(f"✅ Found {len(ranked_tables)} ranked tables")
        except Exception as e:
            error_msg = f"Failed to rank tables: {str(e)}"
            print(f"❌ RANKING ERROR: {error_msg}")
            return {
                "success": False,
                "error": error_msg
            }
        
        return {
            "success": True,
            "query": query,
            "ranked_tables": ranked_tables
        }
    
    except Exception as e:
        error_msg = f"Unexpected error in test_query: {str(e)}"
        print(f"❌ UNEXPECTED ERROR: {error_msg}")
        import traceback
        traceback.print_exc()
        return {
            "success": False,
            "error": error_msg
        }


@router.post("/validate")
async def validate_table(request: ValidateTableRequest):
    """
    Validate whether a table selection was correct or incorrect for a query
    """
    try:
        validation = ValidationRecord(
            query=request.query,
            table_name=request.table_name,
            is_correct=request.is_correct
        )
        
        success = save_validation(validation)
        
        if success:
            return {
                "success": True,
                "message": f"Validation saved: {request.table_name} is {'CORRECT' if request.is_correct else 'INCORRECT'}"
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to save validation")
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@router.get("/history")
async def get_history():
    """
    Get validation history and statistics
    """
    try:
        validations = load_validations()
        
        # Group by query
        grouped = {}
        for v in validations:
            query = v['query']
            if query not in grouped:
                grouped[query] = {
                    'query': query,
                    'correct_tables': [],
                    'incorrect_tables': [],
                    'timestamp': v['timestamp']
                }
            
            if v['is_correct']:
                if v['table_name'] not in grouped[query]['correct_tables']:
                    grouped[query]['correct_tables'].append(v['table_name'])
            else:
                if v['table_name'] not in grouped[query]['incorrect_tables']:
                    grouped[query]['incorrect_tables'].append(v['table_name'])
        
        # Convert to list and sort by timestamp
        history = list(grouped.values())
        history.sort(key=lambda x: x['timestamp'], reverse=True)
        
        # Calculate statistics
        total_validations = len(validations)
        correct_count = sum(1 for v in validations if v['is_correct'])
        accuracy_rate = f"{(correct_count / total_validations * 100):.1f}%" if total_validations > 0 else "0%"
        
        stats = {
            'total_validations': total_validations,
            'correct_selections': correct_count,
            'accuracy_rate': accuracy_rate
        }
        
        return {
            "success": True,
            "validations": history,
            "stats": stats
        }
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@router.post("/set-priorities")
async def set_priorities(request: PrioritySettings):
    """
    Save custom category priority settings
    """
    try:
        success = save_priority_settings(request.priorities)
        
        if success:
            return {
                "success": True,
                "message": "Priority settings saved successfully"
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to save priorities")
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@router.get("/get-priorities")
async def get_priorities():
    """
    Get current priority settings
    """
    try:
        priorities = load_priority_settings()
        
        return {
            "success": True,
            "priorities": priorities
        }
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@router.get("/validation-rules")
async def get_validation_rules_endpoint():
    """
    Get validation rules for use in SQL generation
    """
    try:
        rules = get_validation_rules()
        
        return {
            "success": True,
            "rules": rules
        }
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@router.get("/all-tables")
async def get_all_tables():
    """
    Get all available tables from schema for search/manual selection
    """
    try:
        # Check if API key is available
        if not OPENAI_API_KEY:
            raise HTTPException(status_code=500, detail="OpenAI API key not configured")
        
        # Initialize SQL engine
        engine = SQLEngine(
            api_key=OPENAI_API_KEY,
            model=SQL_MODEL,
            schema_csv_path=SCHEMA_CSV_PATH
        )
        
        # Get all tables from schema registry
        all_tables = []
        for tname, tinfo in engine.registry.tables.items():
            all_tables.append({
                'table_name': tname,
                'category': tinfo.get('category', ''),
                'description': tinfo.get('description', ''),
                'columns': tinfo.get('columns_raw', '')
            })
        
        # Sort alphabetically by table name
        all_tables.sort(key=lambda x: x['table_name'].lower())
        
        return {
            "success": True,
            "tables": all_tables,
            "count": len(all_tables)
        }
    
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


# ========================================
# BUSINESS RULES MANAGEMENT ENDPOINTS
# ========================================

class BusinessRuleRequest(BaseModel):
    rule_name: str
    rule_config: Dict[str, Any]


@router.get("/business-rules")
async def get_business_rules():
    """
    Get current business rules from config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        if not config_path.exists():
            return {"business_rules": {}, "path": str(config_path)}
        
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        return {
            "business_rules": config.get("business_rules", {}),
            "total_rules": len(config.get("business_rules", {})),
            "path": str(config_path)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading business rules: {str(e)}")


@router.post("/business-rules")
async def update_business_rule(request: BusinessRuleRequest):
    """
    Add or update a business rule in config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        # Load existing config
        if config_path.exists():
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        else:
            config = {"business_rules": {}, "example_queries": {}}
        
        # Ensure business_rules exists
        if "business_rules" not in config:
            config["business_rules"] = {}
        
        # Update the rule
        config["business_rules"][request.rule_name] = request.rule_config
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        return {
            "success": True,
            "message": f"Business rule '{request.rule_name}' updated successfully",
            "total_rules": len(config["business_rules"])
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating business rule: {str(e)}")


@router.delete("/business-rules/{rule_name}")
async def delete_business_rule(rule_name: str):
    """
    Delete a business rule from config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        if not config_path.exists():
            raise HTTPException(status_code=404, detail="Config file not found")
        
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        if "business_rules" not in config or rule_name not in config["business_rules"]:
            raise HTTPException(status_code=404, detail=f"Rule '{rule_name}' not found")
        
        # Delete the rule
        del config["business_rules"][rule_name]
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        return {
            "success": True,
            "message": f"Business rule '{rule_name}' deleted successfully",
            "total_rules": len(config["business_rules"])
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting business rule: {str(e)}")


@router.put("/business-rules/bulk")
async def update_all_business_rules(business_rules: Dict[str, Any]):
    """
    Replace all business rules in config/sql_assistant_config.json
    """
    try:
        config_path = settings.DATA_DIR.parent / "config" / "sql_assistant_config.json"
        
        # Load existing config
        if config_path.exists():
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        else:
            config = {"business_rules": {}, "example_queries": {}}
        
        # Replace all business rules
        config["business_rules"] = business_rules
        
        # Save back to file
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        return {
            "success": True,
            "message": f"All business rules updated successfully",
            "total_rules": len(business_rules)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating all business rules: {str(e)}")
