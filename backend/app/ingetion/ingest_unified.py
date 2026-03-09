"""
Unified Document & Code Ingestion System
- Handles all document types (PDF, DOCX, TXT, etc.)
- Processes code repositories (Python, C#, JavaScript, etc.)
- Gracefully handles missing files/folders without errors
- Intelligently skips already ingested items
- Provides comprehensive progress tracking
"""

import sys
from pathlib import Path
from typing import Dict, List, Set, Any
import logging

# Add project root to path
sys.path.append(str(Path(__file__).parent))

from app.ingetion.loaders.ingest_documents import DocumentProcessor
from app.ingetion.loaders.ingest_code import CodeProcessor
from app.services.knowledge_base.vector_store_service import VectorStoreService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class UnifiedIngestionSystem:
    """Unified system for ingesting all types of documents and code"""
    
    def __init__(self):
        self.doc_processor = DocumentProcessor()
        self.code_processor = CodeProcessor()
        self.vector_store = VectorStoreService()
        
        # Statistics tracking
        self.stats = {
            'documents': {'found': 0, 'new': 0, 'skipped': 0, 'failed': 0},
            'code': {'found': 0, 'new': 0, 'skipped': 0, 'failed': 0},
            'failed_items': []
        }
        
        # Get existing files to avoid re-ingestion
        self.existing_files = self._get_existing_files()
        
        logger.info("✅ Unified Ingestion System initialized")
    
    def _get_existing_files(self) -> Set[str]:
        """Get set of already ingested filenames"""
        existing = set()
        try:
            for doc in self.vector_store.documents:
                filename = doc.get('metadata', {}).get('filename', '')
                if filename:
                    existing.add(filename)
            logger.info(f"📊 Found {len(existing)} files already ingested")
        except Exception as e:
            logger.warning(f"⚠️ Could not check existing files: {e}")
        
        return existing
    
    def _safe_glob(self, path: Path, pattern: str, recursive: bool = False) -> List[Path]:
        """Safely find files matching pattern, returns empty list if path doesn't exist"""
        try:
            if not path.exists():
                return []
            
            if recursive:
                return list(path.glob(f"**/{pattern}"))
            else:
                return list(path.glob(pattern))
        except Exception as e:
            logger.warning(f"⚠️ Error scanning {path} for {pattern}: {e}")
            return []
    
    def ingest_documents(self, config: Dict[str, Any]) -> Dict[str, int]:
        """
        Ingest documents based on configuration
        
        Args:
            config: Dictionary with document folder configurations
                {
                    "base_path": "app/modules/neo_chatbot/data/documents",
                    "categories": {
                        "proposals/type-1": "proposals_sorting_conveyor",
                        "proposals/type-2": "proposals_warehouse_automation",
                        "support": "technical_support"
                    }
                }
        """
        logger.info("\n" + "="*80)
        logger.info("📄 DOCUMENT INGESTION")
        logger.info("="*80)
        
        base_path = Path(config.get('base_path', 'app/modules/neo_chatbot/data/documents'))
        categories = config.get('categories', {})
        
        if not base_path.exists():
            logger.warning(f"⚠️ Base path not found: {base_path}")
            logger.info("   Creating directory...")
            try:
                base_path.mkdir(parents=True, exist_ok=True)
                logger.info(f"   ✅ Created: {base_path}")
            except Exception as e:
                logger.error(f"   ❌ Could not create directory: {e}")
                return self.stats['documents']
        
        # Process each category
        for folder, category in categories.items():
            folder_path = base_path / folder if folder != "." else base_path
            
            logger.info(f"\n{'─'*80}")
            logger.info(f"📁 Category: {category}")
            logger.info(f"   Path: {folder_path}")
            
            if not folder_path.exists():
                logger.warning(f"   ⚠️ Folder not found - skipping")
                continue
            
            # Find all document types
            file_patterns = ['*.pdf', '*.PDF', '*.docx', '*.DOCX', '*.txt', '*.TXT', '*.pptx', '*.PPTX', '*.ppt', '*.PPT']
            all_files = []
            
            for pattern in file_patterns:
                all_files.extend(self._safe_glob(folder_path, pattern, recursive=False))
            
            if not all_files:
                logger.info("   ℹ️ No documents found")
                continue
            
            logger.info(f"   Found: {len(all_files)} documents")
            
            # Process each file
            for i, file_path in enumerate(all_files, 1):
                self.stats['documents']['found'] += 1
                
                # Progress indicator
                if len(all_files) > 10:
                    progress = f"[{i}/{len(all_files)}]"
                else:
                    progress = f"[{i}/{len(all_files)}]"
                
                logger.info(f"   {progress} {file_path.name[:60]}")
                
                # Check if already ingested
                if file_path.name in self.existing_files:
                    logger.info(f"      ⏭️ Already ingested")
                    self.stats['documents']['skipped'] += 1
                    continue
                
                # Ingest the document
                try:
                    # Process based on file type
                    if file_path.suffix.lower() == '.pdf':
                        result = self.doc_processor.ingest_pdf(str(file_path), category)
                    elif file_path.suffix.lower() in ['.pptx', '.ppt']:
                        result = self.doc_processor.ingest_pptx(str(file_path), category)
                    else:
                        logger.info(f"      ⚠️ Unsupported format: {file_path.suffix}")
                        self.stats['documents']['skipped'] += 1
                        continue
                    
                    if result.get('status') == 'success':
                        chunks = result.get('chunks', 0)
                        chars = result.get('total_characters', 0)
                        logger.info(f"      ✅ Success: {chunks} chunks ({chars:,} chars)")
                        self.stats['documents']['new'] += 1
                        self.existing_files.add(file_path.name)
                    else:
                        error_msg = result.get('message', 'Unknown error')
                        logger.warning(f"      ❌ Failed: {error_msg[:100]}")
                        self.stats['documents']['failed'] += 1
                        self.stats['failed_items'].append({
                            'type': 'document',
                            'file': file_path.name,
                            'error': error_msg,
                            'path': str(file_path)
                        })
                
                except Exception as e:
                    error_str = str(e)[:200]
                    logger.warning(f"      ❌ Error: {error_str}")
                    self.stats['documents']['failed'] += 1
                    self.stats['failed_items'].append({
                        'type': 'document',
                        'file': file_path.name,
                        'error': error_str,
                        'path': str(file_path)
                    })
        
        return self.stats['documents']
    
    def ingest_code(self, config: Dict[str, Any]) -> Dict[str, int]:
        """
        Ingest code repositories
        
        Args:
            config: Dictionary with code repository configurations
                {
                    "repositories": [
                        {
                            "path": "C:\\path\\to\\codebase",
                            "category": "neo-fleet-manager-code",
                            "enabled": True
                        }
                    ]
                }
        """
        logger.info("\n" + "="*80)
        logger.info("💻 CODE INGESTION")
        logger.info("="*80)
        
        repositories = config.get('repositories', [])
        
        if not repositories:
            logger.info("\n   ℹ️ No code repositories configured")
            return self.stats['code']
        
        # Get existing code files
        existing_code_files = set()
        try:
            for doc in self.vector_store.documents:
                metadata = doc.get('metadata', {})
                if metadata.get('type') == 'code':
                    filename = metadata.get('filename', '')
                    if filename:
                        existing_code_files.add(filename)
            logger.info(f"\n📊 Already ingested code files: {len(existing_code_files)}")
        except Exception as e:
            logger.warning(f"⚠️ Could not check existing code files: {e}")
        
        # Process each repository
        for repo_config in repositories:
            if not repo_config.get('enabled', True):
                logger.info(f"\n⏭️ Skipping disabled repository: {repo_config.get('path', 'Unknown')}")
                continue
            
            repo_path = Path(repo_config.get('path', ''))
            category = repo_config.get('category', 'code')
            
            logger.info(f"\n{'─'*80}")
            logger.info(f"📂 Repository: {repo_path.name if repo_path.exists() else 'Unknown'}")
            logger.info(f"   Path: {repo_path}")
            logger.info(f"   Category: {category}")
            
            if not repo_path.exists():
                logger.warning(f"   ⚠️ Path not found - skipping")
                continue
            
            # Find all code files
            code_files = []
            for ext in self.code_processor.CODE_EXTENSIONS.keys():
                found_files = self._safe_glob(repo_path, f"*{ext}", recursive=True)
                # Filter out files that should be skipped
                code_files.extend([f for f in found_files if not self.code_processor.should_skip(f)])
            
            self.stats['code']['found'] += len(code_files)
            
            if not code_files:
                logger.info("   ℹ️ No code files found")
                continue
            
            # Filter new files
            new_code_files = [f for f in code_files if f.name not in existing_code_files]
            
            logger.info(f"   Total files: {len(code_files)}")
            logger.info(f"   New files: {len(new_code_files)}")
            logger.info(f"   Already ingested: {len(code_files) - len(new_code_files)}")
            
            if not new_code_files:
                logger.info("   ⏭️ All files already ingested")
                self.stats['code']['skipped'] += len(code_files)
                continue
            
            # Ingest new files
            logger.info(f"\n   Processing {len(new_code_files)} new files...")
            
            for i, code_file in enumerate(new_code_files, 1):
                # Progress update every 10 files for large repos
                if i % 10 == 0 or len(new_code_files) <= 10:
                    logger.info(f"      [{i}/{len(new_code_files)}] {code_file.name}")
                
                try:
                    result = self.code_processor.ingest_code_file(str(code_file), category)
                    
                    if result.get('status') == 'success':
                        self.stats['code']['new'] += 1
                        existing_code_files.add(code_file.name)
                    elif result.get('status') == 'skipped':
                        self.stats['code']['skipped'] += 1
                    else:
                        self.stats['code']['failed'] += 1
                        self.stats['failed_items'].append({
                            'type': 'code',
                            'file': code_file.name,
                            'error': result.get('message', 'Unknown error'),
                            'path': str(code_file)
                        })
                
                except Exception as e:
                    logger.warning(f"      ❌ Error: {code_file.name}: {str(e)[:100]}")
                    self.stats['code']['failed'] += 1
                    self.stats['failed_items'].append({
                        'type': 'code',
                        'file': code_file.name,
                        'error': str(e),
                        'path': str(code_file)
                    })
            
            logger.info(f"\n   ✅ Repository complete:")
            logger.info(f"      New: {self.stats['code']['new']}")
            logger.info(f"      Failed: {self.stats['code']['failed']}")
        
        return self.stats['code']
    
    def print_summary(self):
        """Print comprehensive ingestion summary"""
        logger.info("\n" + "="*80)
        logger.info("📊 INGESTION SUMMARY")
        logger.info("="*80)
        
        # Documents summary
        doc_stats = self.stats['documents']
        logger.info(f"\n📄 DOCUMENTS:")
        logger.info(f"   Found: {doc_stats['found']}")
        logger.info(f"   ✅ Newly ingested: {doc_stats['new']}")
        logger.info(f"   ⏭️ Skipped: {doc_stats['skipped']}")
        logger.info(f"   ❌ Failed: {doc_stats['failed']}")
        
        # Code summary
        code_stats = self.stats['code']
        logger.info(f"\n💻 CODE FILES:")
        logger.info(f"   Found: {code_stats['found']}")
        logger.info(f"   ✅ Newly ingested: {code_stats['new']}")
        logger.info(f"   ⏭️ Skipped: {code_stats['skipped']}")
        logger.info(f"   ❌ Failed: {code_stats['failed']}")
        
        # Overall summary
        total_found = doc_stats['found'] + code_stats['found']
        total_new = doc_stats['new'] + code_stats['new']
        total_skipped = doc_stats['skipped'] + code_stats['skipped']
        total_failed = doc_stats['failed'] + code_stats['failed']
        
        logger.info(f"\n📊 OVERALL:")
        logger.info(f"   Total items: {total_found}")
        logger.info(f"   ✅ Newly ingested: {total_new}")
        logger.info(f"   ⏭️ Skipped: {total_skipped}")
        logger.info(f"   ❌ Failed: {total_failed}")
        
        # Failed items details
        if self.stats['failed_items']:
            logger.info(f"\n⚠️ FAILED ITEMS ({len(self.stats['failed_items'])}):")
            for i, item in enumerate(self.stats['failed_items'][:10], 1):
                logger.info(f"\n   {i}. [{item['type']}] {item['file']}")
                logger.info(f"      Error: {item['error'][:150]}")
                logger.info(f"      Path: {item['path']}")
            
            if len(self.stats['failed_items']) > 10:
                logger.info(f"\n   ... and {len(self.stats['failed_items']) - 10} more")
        
        # Vector store statistics
        logger.info(f"\n{'='*80}")
        logger.info("📊 VECTOR STORE STATISTICS")
        logger.info("="*80)
        
        try:
            vs_stats = self.vector_store.get_statistics()
            logger.info(f"\nTotal chunks: {vs_stats.get('total_documents', 0)}")
            logger.info(f"Unique files: {len(self.existing_files)}")
            
            logger.info(f"\nBy category:")
            for cat, count in sorted(vs_stats.get('categories', {}).items()):
                logger.info(f"   {cat}: {count}")
        except Exception as e:
            logger.warning(f"⚠️ Could not retrieve vector store stats: {e}")
        
        logger.info("\n" + "="*80)
        
        # Success message
        if total_new > 0:
            logger.info("\n✅ Ingestion complete!")
            logger.info("\n💡 You can now query the chatbot about:")
            if doc_stats['new'] > 0:
                logger.info("   📄 Documents: Technical proposals, support docs, manuals")
            if code_stats['new'] > 0:
                logger.info("   💻 Code: Implementation details, functions, classes")
        else:
            logger.info("\n✅ All items already ingested - nothing new to add")
        
        if total_failed > 0:
            logger.info(f"\n⚠️ Note: {total_failed} items failed - check errors above")
        
        logger.info("\n" + "="*80 + "\n")


def main():
    """Main ingestion entry point"""
    
    print("\n" + "="*80)
    print("🚀 UNIFIED INGESTION SYSTEM")
    print("   Smart ingestion of all documents and code")
    print("="*80 + "\n")
    
    # Load configuration
    try:
        from ingestion_config import (
            DOCUMENTS_BASE_PATH,
            DOCUMENT_CATEGORIES,
            ENABLE_CODE_INGESTION,
            CODE_REPOSITORIES
        )
        logger.info("✅ Loaded configuration from ingestion_config.py")
    except ImportError:
        logger.warning("⚠️ Configuration file not found, using defaults")
        # Default configuration
        DOCUMENTS_BASE_PATH = 'app/modules/neo_chatbot/data/documents'
        DOCUMENT_CATEGORIES = {
            'proposals/type-1': 'proposals_sorting_conveyor',
            'proposals/type-2': 'proposals_warehouse_automation',
            'proposals/type-3': 'proposals_specialized_systems',
            'support': 'technical_support',
            '.': 'general_documentation'
        }
        ENABLE_CODE_INGESTION = True
        CODE_REPOSITORIES = [
            {
                'path': r'C:\Users\Balmukund.Mishra\Desktop\neo-fleet-manager-noon-min-2.0',
                'category': 'neo-fleet-manager-code',
                'enabled': True
            }
        ]
    
    # Initialize system
    system = UnifiedIngestionSystem()
    
    # ========================================================================
    # EXECUTE INGESTION
    # ========================================================================
    
    # Document configuration
    document_config = {
        'base_path': DOCUMENTS_BASE_PATH,
        'categories': DOCUMENT_CATEGORIES
    }
    
    # Code configuration
    code_config = {
        'repositories': CODE_REPOSITORIES if ENABLE_CODE_INGESTION else []
    }
    
    # Ingest documents
    system.ingest_documents(document_config)
    
    # Ingest code
    if ENABLE_CODE_INGESTION:
        system.ingest_code(code_config)
    else:
        logger.info("\n⏭️ Code ingestion disabled in configuration")
    
    # Print summary
    system.print_summary()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️ Ingestion interrupted by user")
        print("✅ Partial ingestion completed successfully")
        print("   You can re-run to continue from where it stopped\n")
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        print("\n💡 Check the error above and try again\n")
