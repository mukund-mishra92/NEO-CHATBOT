"""
Code Ingestion Script for NEO Fleet Manager C# Codebase
Embeds C# code files with intelligent chunking and metadata extraction
"""

import sys
import os
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

import logging
from typing import List, Dict, Any, Optional
from app.modules.neo_chatbot.services.vector_store_service import VectorStoreService
from app.modules.neo_chatbot.services.llm_service import LLMService
import uuid
import re
import hashlib

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class CodeProcessor:
    """Process and ingest code files into vector store with intelligent chunking"""
    
    # Supported file extensions
    CODE_EXTENSIONS = {
        '.cs': 'csharp',
        '.py': 'python',
        '.js': 'javascript',
        '.ts': 'typescript',
        '.java': 'java',
        '.cpp': 'cpp',
        '.c': 'c',
        '.sql': 'sql',
        '.html': 'html',
        '.css': 'css',
        '.xml': 'xml',
        '.json': 'json',
        '.yaml': 'yaml',
        '.yml': 'yaml'
    }
    
    # Files/folders to skip
    SKIP_PATTERNS = [
        'bin', 'obj', 'node_modules', '__pycache__', '.git', '.vs',
        'packages', 'Debug', 'Release', 'dist', 'build',
        '.min.js', '.min.css', 'AssemblyInfo.cs'
    ]
    
    def __init__(self):
        self.vector_store = VectorStoreService()
        self.llm_service = LLMService()
        logger.info("✅ Code Processor initialized")
    
    def should_skip(self, path: Path) -> bool:
        """Check if file/folder should be skipped"""
        path_str = str(path).lower()
        return any(pattern.lower() in path_str for pattern in self.SKIP_PATTERNS)
    
    def extract_code_metadata(self, code: str, language: str, filename: str) -> Dict[str, Any]:
        """Extract metadata from code file"""
        metadata = {
            'type': 'code',
            'language': language,
            'filename': filename,
            'classes': [],
            'functions': [],
            'interfaces': [],
            'namespaces': [],
            'using_statements': []
        }
        
        if language == 'csharp':
            # Extract namespaces
            namespace_pattern = r'namespace\s+([\w\.]+)'
            metadata['namespaces'] = re.findall(namespace_pattern, code)
            
            # Extract classes
            class_pattern = r'(?:public|private|protected|internal)?\s*(?:static|abstract|sealed)?\s*class\s+(\w+)'
            metadata['classes'] = re.findall(class_pattern, code)
            
            # Extract interfaces
            interface_pattern = r'(?:public|private|protected|internal)?\s*interface\s+(\w+)'
            metadata['interfaces'] = re.findall(interface_pattern, code)
            
            # Extract methods/functions
            method_pattern = r'(?:public|private|protected|internal)?\s*(?:static|virtual|override|async)?\s*[\w<>]+\s+(\w+)\s*\('
            metadata['functions'] = re.findall(method_pattern, code)
            
            # Extract using statements
            using_pattern = r'using\s+([\w\.]+);'
            metadata['using_statements'] = re.findall(using_pattern, code)
        
        elif language == 'python':
            # Extract classes
            class_pattern = r'class\s+(\w+)'
            metadata['classes'] = re.findall(class_pattern, code)
            
            # Extract functions
            function_pattern = r'def\s+(\w+)\s*\('
            metadata['functions'] = re.findall(function_pattern, code)
            
            # Extract imports
            import_pattern = r'(?:from\s+[\w\.]+\s+)?import\s+([\w\.,\s]+)'
            metadata['using_statements'] = re.findall(import_pattern, code)
        
        return metadata
    
    def chunk_code_intelligently(self, code: str, language: str, max_chunk_size: int = 1500) -> List[Dict[str, Any]]:
        """
        Chunk code intelligently based on code structure
        Preserves classes, methods, and logical units
        """
        chunks = []
        lines = code.split('\n')
        
        if language == 'csharp':
            chunks = self._chunk_csharp_code(lines, max_chunk_size)
        elif language == 'python':
            chunks = self._chunk_python_code(lines, max_chunk_size)
        else:
            # Default: chunk by line count
            chunks = self._chunk_by_lines(lines, max_chunk_size)
        
        return chunks
    
    def _chunk_csharp_code(self, lines: List[str], max_chunk_size: int) -> List[Dict[str, Any]]:
        """Chunk C# code by classes, methods, and logical units"""
        chunks = []
        current_chunk = []
        current_size = 0
        brace_depth = 0
        in_class = False
        in_method = False
        current_context = {'class': None, 'method': None}
        
        for line in lines:
            stripped = line.strip()
            
            # Track context
            if 'class ' in stripped:
                match = re.search(r'class\s+(\w+)', stripped)
                if match:
                    current_context['class'] = match.group(1)
                    in_class = True
            
            if re.search(r'\w+\s+\w+\s*\(', stripped):
                match = re.search(r'(\w+)\s*\(', stripped)
                if match:
                    current_context['method'] = match.group(1)
                    in_method = True
            
            # Track braces
            brace_depth += stripped.count('{') - stripped.count('}')
            
            # Add line to current chunk
            current_chunk.append(line)
            current_size += len(line)
            
            # Check if we should split
            should_split = (
                (brace_depth == 0 and in_method and len(current_chunk) > 5) or
                (current_size > max_chunk_size and brace_depth == 0) or
                (current_size > max_chunk_size * 1.5)  # Hard limit
            )
            
            if should_split and current_chunk:
                chunk_text = '\n'.join(current_chunk)
                if len(chunk_text.strip()) > 50:
                    chunks.append({
                        'text': chunk_text,
                        'class': current_context['class'],
                        'method': current_context['method']
                    })
                current_chunk = []
                current_size = 0
                if brace_depth == 0:
                    in_method = False
        
        # Add remaining chunk
        if current_chunk:
            chunk_text = '\n'.join(current_chunk)
            if len(chunk_text.strip()) > 50:
                chunks.append({
                    'text': chunk_text,
                    'class': current_context['class'],
                    'method': current_context['method']
                })
        
        return chunks
    
    def _chunk_python_code(self, lines: List[str], max_chunk_size: int) -> List[Dict[str, Any]]:
        """Chunk Python code by classes and functions"""
        chunks = []
        current_chunk = []
        current_size = 0
        current_indent = 0
        base_indent = None
        current_context = {'class': None, 'function': None}
        
        for line in lines:
            stripped = line.strip()
            
            # Track context
            if stripped.startswith('class '):
                match = re.search(r'class\s+(\w+)', stripped)
                if match:
                    current_context['class'] = match.group(1)
                    base_indent = len(line) - len(line.lstrip())
            
            if stripped.startswith('def '):
                match = re.search(r'def\s+(\w+)', stripped)
                if match:
                    current_context['function'] = match.group(1)
            
            # Get indentation
            indent = len(line) - len(line.lstrip())
            
            # Add line to current chunk
            current_chunk.append(line)
            current_size += len(line)
            
            # Check if we should split (at function/class boundaries)
            should_split = (
                (stripped.startswith('def ') or stripped.startswith('class ')) and
                len(current_chunk) > 5 and
                current_size > max_chunk_size / 2
            ) or current_size > max_chunk_size * 1.5
            
            if should_split and current_chunk:
                chunk_text = '\n'.join(current_chunk)
                if len(chunk_text.strip()) > 50:
                    chunks.append({
                        'text': chunk_text,
                        'class': current_context['class'],
                        'function': current_context['function']
                    })
                current_chunk = []
                current_size = 0
        
        # Add remaining chunk
        if current_chunk:
            chunk_text = '\n'.join(current_chunk)
            if len(chunk_text.strip()) > 50:
                chunks.append({
                    'text': chunk_text,
                    'class': current_context['class'],
                    'function': current_context['function']
                })
        
        return chunks
    
    def _chunk_by_lines(self, lines: List[str], max_chunk_size: int) -> List[Dict[str, Any]]:
        """Simple line-based chunking for generic files"""
        chunks = []
        current_chunk = []
        current_size = 0
        
        for line in lines:
            current_chunk.append(line)
            current_size += len(line)
            
            if current_size > max_chunk_size:
                chunk_text = '\n'.join(current_chunk)
                if len(chunk_text.strip()) > 50:
                    chunks.append({'text': chunk_text})
                current_chunk = []
                current_size = 0
        
        if current_chunk:
            chunk_text = '\n'.join(current_chunk)
            if len(chunk_text.strip()) > 50:
                chunks.append({'text': chunk_text})
        
        return chunks
    
    def generate_code_summary(self, code: str, metadata: Dict, max_length: int = 500) -> str:
        """Generate a human-readable summary of the code"""
        summary_parts = []
        
        # File info
        summary_parts.append(f"File: {metadata['filename']}")
        summary_parts.append(f"Language: {metadata['language']}")
        
        # Key components
        if metadata.get('namespaces'):
            summary_parts.append(f"Namespaces: {', '.join(metadata['namespaces'][:3])}")
        
        if metadata.get('classes'):
            summary_parts.append(f"Classes: {', '.join(metadata['classes'][:5])}")
        
        if metadata.get('interfaces'):
            summary_parts.append(f"Interfaces: {', '.join(metadata['interfaces'][:5])}")
        
        if metadata.get('functions'):
            func_count = len(metadata['functions'])
            func_sample = ', '.join(metadata['functions'][:5])
            summary_parts.append(f"Functions ({func_count}): {func_sample}...")
        
        # Add a snippet of the actual code
        code_lines = code.split('\n')[:10]
        code_snippet = '\n'.join(code_lines)
        summary_parts.append(f"\nCode Preview:\n{code_snippet}")
        
        summary = '\n'.join(summary_parts)
        return summary[:max_length] if len(summary) > max_length else summary
    
    def ingest_code_file(self, file_path: str, category: str = "code") -> Dict[str, Any]:
        """Ingest a code file into vector store"""
        try:
            file_path_obj = Path(file_path)
            logger.info(f"📥 Ingesting code file: {file_path_obj.name}")
            
            # Check file extension
            extension = file_path_obj.suffix.lower()
            if extension not in self.CODE_EXTENSIONS:
                return {
                    "status": "skipped",
                    "message": f"Unsupported file type: {extension}"
                }
            
            language = self.CODE_EXTENSIONS[extension]
            
            # Read code file
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    code = f.read()
            except UnicodeDecodeError:
                # Try with different encoding
                with open(file_path, 'r', encoding='latin-1') as f:
                    code = f.read()
            
            if not code.strip():
                return {
                    "status": "skipped",
                    "message": "Empty file"
                }
            
            # Extract metadata
            metadata = self.extract_code_metadata(code, language, file_path_obj.name)
            metadata['category'] = category
            metadata['file_path'] = str(file_path_obj)
            metadata['file_size'] = len(code)
            
            # Chunk code intelligently
            chunks = self.chunk_code_intelligently(code, language)
            
            logger.info(f"   📦 Created {len(chunks)} chunks")
            
            # Ingest each chunk
            chunk_count = 0
            for idx, chunk_data in enumerate(chunks):
                chunk_text = chunk_data['text']
                
                # Create enhanced metadata for this chunk
                chunk_metadata = metadata.copy()
                chunk_metadata['chunk_index'] = idx
                chunk_metadata['total_chunks'] = len(chunks)
                chunk_metadata['chunk_context'] = {
                    'class': chunk_data.get('class'),
                    'method': chunk_data.get('method'),
                    'function': chunk_data.get('function')
                }
                
                # Generate embedding
                try:
                    embedding = self.llm_service.generate_embedding(chunk_text)
                except Exception as e:
                    logger.warning(f"⚠️ Error generating embedding: {e}")
                    embedding = self._generate_fallback_embedding(chunk_text)
                
                # Generate summary for better searchability
                summary = self.generate_code_summary(chunk_text, chunk_metadata)
                
                # Combine summary + code for better semantic search
                searchable_text = f"{summary}\n\n{chunk_text}"
                
                # Store in vector store
                doc_id = str(uuid.uuid4())
                document = {
                    "id": doc_id,
                    "text": chunk_text,  # Original code
                    "searchable_text": searchable_text,  # For display
                    "embedding": embedding,
                    "metadata": chunk_metadata
                }
                
                self.vector_store.documents.append(document)
                chunk_count += 1
            
            # Save vector store
            self.vector_store.save_store()
            
            logger.info(f"✅ Ingested {chunk_count} chunks from {file_path_obj.name}")
            
            return {
                "status": "success",
                "filename": file_path_obj.name,
                "language": language,
                "chunks": chunk_count,
                "classes": len(metadata['classes']),
                "functions": len(metadata['functions'])
            }
            
        except Exception as e:
            logger.error(f"❌ Error ingesting {file_path}: {e}")
            return {
                "status": "error",
                "filename": Path(file_path).name,
                "error": str(e)
            }
    
    def _generate_fallback_embedding(self, text: str) -> List[float]:
        """Generate fallback embedding if LLM fails"""
        import hashlib
        text_hash = hashlib.sha256(text.encode()).hexdigest()
        embedding = []
        
        for i in range(0, len(text_hash), 2):
            byte_val = int(text_hash[i:i+2], 16)
            embedding.append(float(byte_val) / 255.0)
        
        # Pad to 1536 dimensions (matches OpenAI)
        while len(embedding) < 1536:
            embedding.append(0.0)
        
        return embedding[:1536]
    
    def ingest_directory(self, directory_path: str, category: str = "code", recursive: bool = True) -> Dict[str, Any]:
        """Ingest all code files from a directory"""
        directory = Path(directory_path)
        
        if not directory.exists():
            logger.error(f"❌ Directory not found: {directory}")
            return {
                "status": "error",
                "message": f"Directory not found: {directory}"
            }
        
        logger.info(f"\n{'='*80}")
        logger.info(f"📂 Ingesting code from: {directory}")
        logger.info(f"{'='*80}\n")
        
        results = {
            "total_files": 0,
            "successful": 0,
            "skipped": 0,
            "failed": 0,
            "total_chunks": 0,
            "by_language": {},
            "files": []
        }
        
        # Find all code files
        pattern = '**/*' if recursive else '*'
        for ext in self.CODE_EXTENSIONS.keys():
            files = list(directory.glob(f"{pattern}{ext}"))
            
            for file_path in files:
                # Skip if in skip patterns
                if self.should_skip(file_path):
                    logger.debug(f"⏭️ Skipping: {file_path}")
                    continue
                
                results["total_files"] += 1
                
                # Ingest file
                result = self.ingest_code_file(str(file_path), category)
                
                if result["status"] == "success":
                    results["successful"] += 1
                    results["total_chunks"] += result["chunks"]
                    
                    # Track by language
                    lang = result["language"]
                    if lang not in results["by_language"]:
                        results["by_language"][lang] = 0
                    results["by_language"][lang] += 1
                    
                elif result["status"] == "skipped":
                    results["skipped"] += 1
                else:
                    results["failed"] += 1
                
                results["files"].append(result)
        
        # Summary
        logger.info(f"\n{'='*80}")
        logger.info(f"📊 INGESTION SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total files processed: {results['total_files']}")
        logger.info(f"✅ Successful: {results['successful']}")
        logger.info(f"⏭️ Skipped: {results['skipped']}")
        logger.info(f"❌ Failed: {results['failed']}")
        logger.info(f"📦 Total chunks created: {results['total_chunks']}")
        logger.info(f"\n📚 By Language:")
        for lang, count in results["by_language"].items():
            logger.info(f"   {lang}: {count} files")
        logger.info(f"{'='*80}\n")
        
        return results


def main():
    """Main entry point for code ingestion"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Ingest code files into NEO Chatbot knowledge base")
    parser.add_argument("path", help="Path to code file or directory")
    parser.add_argument("--category", default="code", help="Category for the code (default: code)")
    parser.add_argument("--no-recursive", action="store_true", help="Don't process subdirectories")
    
    args = parser.parse_args()
    
    processor = CodeProcessor()
    path = Path(args.path)
    
    if path.is_file():
        result = processor.ingest_code_file(str(path), args.category)
        if result["status"] == "success":
            logger.info(f"\n✅ Successfully ingested code file!")
        else:
            logger.error(f"\n❌ Failed to ingest: {result.get('message', result.get('error'))}")
    
    elif path.is_dir():
        results = processor.ingest_directory(str(path), args.category, not args.no_recursive)
        if results["successful"] > 0:
            logger.info(f"\n✅ Successfully ingested {results['successful']} code files!")
        else:
            logger.warning(f"\n⚠️ No files were successfully ingested")
    
    else:
        logger.error(f"\n❌ Path not found: {path}")


if __name__ == "__main__":
    main()
