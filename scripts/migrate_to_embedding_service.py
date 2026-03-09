"""
Migration script to update existing code to use the embedding-based classification service

This script:
1. Shows what files need to be updated
2. Provides before/after code examples
3. Can optionally perform automatic migration (with backup)
"""

import sys
from pathlib import Path
import re
import shutil

# Colors for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


def print_section(title: str):
    """Print a section header"""
    print(f"\n{Colors.HEADER}{'=' * 80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{title}{Colors.ENDC}")
    print(f"{Colors.HEADER}{'=' * 80}{Colors.ENDC}\n")


def print_success(msg: str):
    """Print success message"""
    print(f"{Colors.OKGREEN}✅ {msg}{Colors.ENDC}")


def print_warning(msg: str):
    """Print warning message"""
    print(f"{Colors.WARNING}⚠️  {msg}{Colors.ENDC}")


def print_info(msg: str):
    """Print info message"""
    print(f"{Colors.OKCYAN}ℹ️  {msg}{Colors.ENDC}")


def print_error(msg: str):
    """Print error message"""
    print(f"{Colors.FAIL}❌ {msg}{Colors.ENDC}")


def find_files_using_classification_service(root_path: Path):
    """Find all Python files that import the classification service"""
    print_section("SCANNING FOR FILES USING CLASSIFICATION SERVICE")
    
    files_to_update = []
    
    # Search patterns
    import_patterns = [
        r'from\s+app\.services\.query_classification_service\s+import',
        r'import\s+app\.services\.query_classification_service',
        r'QueryClassificationService',
    ]
    
    # Search all Python files
    for py_file in root_path.rglob("*.py"):
        if "venv" in str(py_file) or "__pycache__" in str(py_file):
            continue
        
        try:
            content = py_file.read_text(encoding="utf-8")
            
            # Check if file uses the classification service
            matches = []
            for pattern in import_patterns:
                if re.search(pattern, content):
                    matches.append(pattern)
            
            if matches:
                files_to_update.append(py_file)
                print_info(f"Found: {py_file.relative_to(root_path)}")
                
        except Exception as e:
            print_warning(f"Could not read {py_file}: {e}")
    
    print(f"\n{Colors.BOLD}Found {len(files_to_update)} files using QueryClassificationService{Colors.ENDC}")
    
    return files_to_update


def show_migration_examples():
    """Show before/after code examples"""
    print_section("MIGRATION EXAMPLES")
    
    examples = [
        {
            "title": "Import Statement",
            "before": "from app.services.query_classification_service import QueryClassificationService",
            "after": "from app.services.query_classification_service_embedding import QueryClassificationServiceEmbedding as QueryClassificationService",
            "note": "Alias keeps existing code working without changes"
        },
        {
            "title": "Service Initialization",
            "before": """service = QueryClassificationService(
    storage_path=Path("data/classification")
)""",
            "after": """service = QueryClassificationServiceEmbedding(
    storage_path=Path("data/classification")
)""",
            "note": "If using alias in import, no changes needed"
        },
        {
            "title": "Similarity Matching (No Changes)",
            "before": """match = service.find_similar_classified_query(
    user_query="How many bots are active?",
    similarity_threshold=0.85
)""",
            "after": """# Same code - API is identical!
match = service.find_similar_classified_query(
    user_query="How many bots are active?",
    similarity_threshold=0.85
)""",
            "note": "API is 100% backward compatible"
        },
    ]
    
    for i, example in enumerate(examples, 1):
        print(f"{Colors.BOLD}{i}. {example['title']}{Colors.ENDC}")
        print(f"\n{Colors.FAIL}BEFORE:{Colors.ENDC}")
        print(f"```python\n{example['before']}\n```")
        print(f"\n{Colors.OKGREEN}AFTER:{Colors.ENDC}")
        print(f"```python\n{example['after']}\n```")
        print(f"\n{Colors.OKCYAN}Note: {example['note']}{Colors.ENDC}\n")
        print("-" * 80)


def perform_migration(files: list, root_path: Path, dry_run: bool = True):
    """Perform automatic migration with backup"""
    print_section("AUTOMATIC MIGRATION")
    
    if dry_run:
        print_warning("DRY RUN MODE - No files will be modified")
        print_info("Run with --apply to perform actual migration\n")
    else:
        print_warning("APPLYING CHANGES - Files will be modified!")
        response = input("Continue? (yes/no): ")
        if response.lower() != "yes":
            print_error("Migration cancelled")
            return
        print()
    
    # Migration rules
    replacements = [
        (
            r'from\s+app\.services\.query_classification_service\s+import\s+QueryClassificationService',
            'from app.services.query_classification_service_embedding import QueryClassificationServiceEmbedding as QueryClassificationService',
            "Import with alias"
        ),
    ]
    
    updated_files = []
    
    for file_path in files:
        try:
            content = file_path.read_text(encoding="utf-8")
            original_content = content
            
            changes = []
            
            for pattern, replacement, description in replacements:
                if re.search(pattern, content):
                    content = re.sub(pattern, replacement, content)
                    changes.append(description)
            
            if changes:
                if not dry_run:
                    # Create backup
                    backup_path = file_path.with_suffix(file_path.suffix + ".backup")
                    shutil.copy2(file_path, backup_path)
                    print_success(f"Backed up: {backup_path.name}")
                    
                    # Write updated content
                    file_path.write_text(content, encoding="utf-8")
                    print_success(f"Updated: {file_path.relative_to(root_path)}")
                else:
                    print_info(f"Would update: {file_path.relative_to(root_path)}")
                
                for change in changes:
                    print(f"  - {change}")
                
                updated_files.append(file_path)
            
        except Exception as e:
            print_error(f"Error processing {file_path}: {e}")
    
    print(f"\n{Colors.BOLD}{len(updated_files)} files {'would be' if dry_run else ''} updated{Colors.ENDC}")


def check_dependencies():
    """Check if required dependencies are installed"""
    print_section("CHECKING DEPENDENCIES")
    
    dependencies = {
        "sentence_transformers": "sentence-transformers",
        "numpy": "numpy",
        "sklearn": "scikit-learn",
    }
    
    all_installed = True
    
    for module, package in dependencies.items():
        try:
            __import__(module)
            print_success(f"{package} is installed")
        except ImportError:
            print_error(f"{package} is NOT installed")
            all_installed = False
    
    if not all_installed:
        print(f"\n{Colors.WARNING}Install missing dependencies:{Colors.ENDC}")
        print("pip install sentence-transformers numpy scikit-learn")
    else:
        print_success("\nAll dependencies are installed!")
    
    return all_installed


def show_summary():
    """Show migration summary"""
    print_section("MIGRATION SUMMARY")
    
    print(f"{Colors.BOLD}What has changed:{Colors.ENDC}")
    print("✅ Embedding-based semantic similarity (replaces character-based SequenceMatcher)")
    print("✅ User review tracking (user_reviewed field added)")
    print("✅ Only correct & reviewed queries used for similarity matching")
    print("✅ Vectorized search (10-100x faster)")
    print("✅ Automatic data migration (backward compatible)")
    
    print(f"\n{Colors.BOLD}What stays the same:{Colors.ENDC}")
    print("✅ API is 100% backward compatible")
    print("✅ File structure unchanged (classified_queries.jsonl)")
    print("✅ All existing methods work identically")
    
    print(f"\n{Colors.BOLD}Next steps:{Colors.ENDC}")
    print("1. Review files that need updating (shown above)")
    print("2. Run with --apply to perform migration")
    print("3. Test with: python scripts/test_embedding_classification.py")
    print("4. Review existing unclassified queries and classify them")
    print("5. Monitor logs for 'Embedding ready: True' on startup")
    
    print(f"\n{Colors.BOLD}Rollback:{Colors.ENDC}")
    print("If issues occur, restore from .backup files:")
    print("  for file in backend/**/*.backup; do mv $file ${file%.backup}; done")


def main():
    """Main migration script"""
    print(f"{Colors.HEADER}")
    print("=" * 80)
    print("QUERY CLASSIFICATION SERVICE - MIGRATION TO EMBEDDING EDITION")
    print("=" * 80)
    print(f"{Colors.ENDC}")
    
    # Parse arguments
    dry_run = "--apply" not in sys.argv
    
    # Get project root
    root_path = Path(__file__).parent.parent
    
    # Check dependencies
    deps_ok = check_dependencies()
    if not deps_ok:
        print_error("\nPlease install missing dependencies before proceeding")
        return 1
    
    # Find files
    files = find_files_using_classification_service(root_path)
    
    # Show examples
    show_migration_examples()
    
    # Perform migration
    if files:
        perform_migration(files, root_path, dry_run=dry_run)
    else:
        print_warning("No files found that need migration")
    
    # Show summary
    show_summary()
    
    if dry_run:
        print(f"\n{Colors.WARNING}DRY RUN COMPLETE - No files were modified{Colors.ENDC}")
        print(f"{Colors.OKCYAN}Run with --apply to perform actual migration{Colors.ENDC}")
    else:
        print(f"\n{Colors.OKGREEN}MIGRATION COMPLETE!{Colors.ENDC}")
        print(f"{Colors.OKCYAN}Test with: python scripts/test_embedding_classification.py{Colors.ENDC}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
