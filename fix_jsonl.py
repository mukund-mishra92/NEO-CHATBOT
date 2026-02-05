"""Fix JSONL file format - split single line into multiple lines"""
import json
import sys
import re

def fix_jsonl_file(filepath):
    """Read malformed JSONL and rewrite it correctly"""
    try:
        # Read the entire file
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read().strip()
        
        print(f"File size: {len(content)} characters")
        
        # Check if content has literal \n (escaped newlines)
        if '\\n{' in content:
            print("Found escaped newlines (\\n) - fixing...")
            # Split on }\\n{ pattern (literal backslash-n, not newline)
            parts = content.split('}\\n{')
            queries = []
            
            for i, part in enumerate(parts):
                if i == 0:
                    # First part - add closing brace
                    json_str = part + '}'
                elif i == len(parts) - 1:
                    # Last part - add opening brace
                    json_str = '{' + part
                else:
                    # Middle parts - add both braces
                    json_str = '{' + part + '}'
                
                try:
                    query = json.loads(json_str)
                    queries.append(query)
                except json.JSONDecodeError as e:
                    print(f"Warning: Failed to parse query {i}: {e}")
                    print(f"Problematic JSON (first 200 chars): {json_str[:200]}")
                    continue
        elif '}\n{' in content:
            print("Found real newlines between objects - fixing...")
            # Split on }\n{ pattern (actual newline)
            parts = content.split('}\n{')
            queries = []
            
            for i, part in enumerate(parts):
                if i == 0:
                    json_str = part + '}'
                elif i == len(parts) - 1:
                    json_str = '{' + part
                else:
                    json_str = '{' + part + '}'
                
                try:
                    query = json.loads(json_str)
                    queries.append(query)
                except json.JSONDecodeError as e:
                    print(f"Warning: Failed to parse query {i}: {e}")
                    continue
        else:
            # Try to parse as single JSON object
            try:
                query = json.loads(content)
                queries = [query]
            except json.JSONDecodeError as e:
                print(f"Error: Unable to parse file content: {e}")
                print(f"First 500 chars: {content[:500]}")
                return False
        
        print(f"Found {len(queries)} queries")
        
        if len(queries) == 0:
            print("No valid queries found!")
            return False
        
        # Backup original file
        backup_path = filepath + '.bak2'
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Backup saved to: {backup_path}")
        
        # Write queries in correct JSONL format (one per line)
        with open(filepath, 'w', encoding='utf-8') as f:
            for query in queries:
                f.write(json.dumps(query, ensure_ascii=False))
                f.write('\n')
        
        print(f"✅ Fixed JSONL file: {filepath}")
        print(f"   Total queries: {len(queries)}")
        
        # Validate the fix
        print("\nValidating fixed file...")
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            print(f"File now has {len(lines)} lines")
            for i, line in enumerate(lines[:3]):
                try:
                    obj = json.loads(line)
                    print(f"  ✅ Line {i+1}: Valid - Query ID: {obj['query_id']}")
                except Exception as e:
                    print(f"  ❌ Line {i+1}: Invalid - {e}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    filepath = "data/classification/classified_queries.jsonl"
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
    
    fix_jsonl_file(filepath)
