"""
RAG Pipeline Orchestrator — End-to-end ingestion + retrieval pipeline.

Ingestion flow:
  1. Walk document directories → detect file types
  2. Extract content (PDF/DOCX/PPTX) with multi-modal extractors
  3. Chunk hierarchically (document → section → paragraph)
  4. Generate embeddings via LLMService
  5. Store in ChromaDB (typed collections)

Retrieval flow:
  1. Embed query
  2. Hybrid retrieval (vector + BM25 + RRF)
  3. Rerank
  4. Assemble context with citations
  5. Synthesize answer
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .extractors.pdf_extractor import PDFExtractor
from .extractors.docx_extractor import DOCXExtractor
from .extractors.ppt_extractor import PPTExtractor
from .extractors.image_describer import ImageDescriber
from .extractors.image_store import ImageStore
from .chunkers.hierarchical_chunker import HierarchicalChunker
from .store.chroma_store import ChromaStore
from .retrieval.hybrid_retriever import HybridRetriever
from .retrieval.reranker import Reranker
from .retrieval.context_assembler import ContextAssembler
from .retrieval.answer_synthesizer import AnswerSynthesizer
from .retrieval.image_display_engine import ImageDisplayEngine
from .models import ExtractedDocument, HierarchicalChunk, SynthesizedAnswer

logger = logging.getLogger(__name__)


class RAGPipeline:
    """
    Unified RAG pipeline for ingestion and retrieval.

    Usage (ingestion):
        pipeline = RAGPipeline()
        stats = pipeline.ingest_directory("data/documents")

    Usage (retrieval):
        pipeline = RAGPipeline()
        answer = pipeline.query("What is the NEO ASRS system?")
    """

    def __init__(
        self,
        *,
        chroma_persist_dir: Optional[str] = None,
        enable_images: bool = True,
        enable_ocr: bool = True,
        section_max_chars: int = 3000,
        paragraph_max_chars: int = 1200,
        overlap_chars: int = 150,
        use_cross_encoder: bool = False,
        llm_service=None,
        max_display_images: int = 5,
        enable_vision_descriptions: bool = False,
    ):
        # ── LLM service ──
        self._llm = llm_service

        # ── Image describer (only when images + vision descriptions are enabled) ──
        self.image_describer = ImageDescriber() if (enable_images and enable_vision_descriptions) else None

        # ── Image store (save extracted images to disk) ──
        self.image_store = ImageStore() if enable_images else None

        # ── Feature flag state ──
        self._enable_images = enable_images
        self._max_display_images = max_display_images

        # ── Extractors ──
        self.pdf_extractor = PDFExtractor(
            enable_ocr=enable_ocr,
            enable_images=enable_images,
            image_describer=self.image_describer,
            image_store=self.image_store,
        )
        self.docx_extractor = DOCXExtractor(image_describer=self.image_describer)
        self.ppt_extractor = PPTExtractor(
            image_describer=self.image_describer,
            image_store=self.image_store,
        )

        # ── Chunker ──
        self.chunker = HierarchicalChunker(
            section_max_chars=section_max_chars,
            paragraph_max_chars=paragraph_max_chars,
            overlap_chars=overlap_chars,
        )

        # ── Store ──
        self.store = ChromaStore(persist_directory=chroma_persist_dir)

        # ── Retrieval chain ──
        self.retriever = HybridRetriever(self.store)
        self.reranker = Reranker(use_cross_encoder=use_cross_encoder)
        self.context_assembler = ContextAssembler()
        self.answer_synthesizer = AnswerSynthesizer(llm_service=self._llm)
        self.image_display_engine = ImageDisplayEngine(max_images=max_display_images) if enable_images else None

    def close(self):
        """Release ChromaDB file handles."""
        if self.store:
            self.store.close()

    @property
    def llm(self):
        if self._llm is None:
            from app.services.llm_service import LLMService
            self._llm = LLMService()
        return self._llm

    # ════════════════════════════════════════════════════
    #  INGESTION
    # ════════════════════════════════════════════════════

    def ingest_directory(
        self,
        directory: str,
        *,
        category: str = "",
        file_extensions: Optional[List[str]] = None,
        skip_existing: bool = True,
        recursive: bool = True,
        exclude_files: Optional[set] = None,
    ) -> Dict[str, Any]:
        """
        Ingest all documents from a directory.

        Args:
            directory: Path to the document directory.
            category: Category label for all documents in this directory.
            file_extensions: Restrict to these extensions (e.g., [".pdf", ".docx"]).
            skip_existing: Skip files already in the store.
            recursive: If True, recurse into subdirectories. If False, root files only.
            exclude_files: Set of absolute paths to skip (for cross-category dedup).

        Returns:
            Dict with stats: files_processed, chunks_created, errors, etc.
        """
        stats = {
            "directory": directory,
            "files_found": 0,
            "files_processed": 0,
            "files_skipped": 0,
            "files_duplicate_skipped": 0,
            "chunks_created": 0,
            "errors": [],
            "time_seconds": 0.0,
            "ingested_paths": set(),
        }

        start = time.time()
        dir_path = Path(directory)
        if not dir_path.exists():
            stats["errors"].append(f"Directory not found: {directory}")
            logger.error(f"Directory not found: {directory}")
            return stats

        # Collect files — recursive or root-only
        extensions = set(file_extensions or [".pdf", ".docx", ".pptx", ".txt", ".md"])
        if recursive:
            files = [
                f for f in dir_path.rglob("*")
                if f.is_file() and f.suffix.lower() in extensions
            ]
        else:
            # Root-level files only (no subdirectory traversal)
            files = [
                f for f in dir_path.iterdir()
                if f.is_file() and f.suffix.lower() in extensions
            ]

        # Exclude already-ingested files (cross-category dedup)
        exclude = exclude_files or set()
        if exclude:
            before = len(files)
            files = [f for f in files if str(f.resolve()) not in exclude]
            stats["files_duplicate_skipped"] = before - len(files)

        stats["files_found"] = len(files)
        logger.info(f"📂 Found {len(files)} files in {directory}")
        print(f"      Found {len(files)} files{'  (non-recursive)' if not recursive else ''}")

        for file_idx, file_path in enumerate(files, 1):
            file_start = time.time()
            try:
                print(f"        [{file_idx}/{len(files)}] {file_path.name}...", end=" ", flush=True)
                result = self.ingest_file(
                    str(file_path),
                    category=category,
                    skip_existing=skip_existing,
                )
                file_elapsed = round(time.time() - file_start, 1)
                if result.get("skipped"):
                    stats["files_skipped"] += 1
                    print(f"SKIP ({result.get('reason', 'unknown')})")
                else:
                    stats["files_processed"] += 1
                    stats["chunks_created"] += result.get("chunks_created", 0)
                    stats["ingested_paths"].add(str(file_path.resolve()))
                    print(f"OK {result.get('chunks_created',0)} chunks ({file_elapsed}s)")
            except KeyboardInterrupt:
                print("INTERRUPTED")
                logger.warning("⚠️ Ingestion interrupted by user")
                break  # Stop processing remaining files but don't crash
            except BaseException as exc:
                error_msg = f"{file_path.name}: {exc}"
                stats["errors"].append(error_msg)
                print(f"ERROR: {exc}")
                logger.error(f"❌ Failed to ingest {file_path.name}: {exc}", exc_info=True)

        stats["time_seconds"] = round(time.time() - start, 2)
        logger.info(
            f"✅ Ingestion complete: {stats['files_processed']}/{stats['files_found']} files, "
            f"{stats['chunks_created']} chunks in {stats['time_seconds']}s"
        )
        return stats

    def ingest_file(
        self,
        file_path: str,
        *,
        category: str = "",
        skip_existing: bool = True,
    ) -> Dict[str, Any]:
        """
        Ingest a single file.

        Returns:
            Dict with: chunks_created, skipped, file_type, etc.
        """
        path = Path(file_path)
        suffix = path.suffix.lower()

        # ── 1. Extract ──
        logger.debug(f"Extracting {path.name} ({suffix})...")
        doc: Optional[ExtractedDocument] = None
        try:
            if suffix == ".pdf":
                doc = self.pdf_extractor.extract(file_path)
            elif suffix in (".docx", ".doc"):
                doc = self.docx_extractor.extract(file_path)
            elif suffix in (".pptx", ".ppt"):
                doc = self.ppt_extractor.extract(file_path)
            elif suffix in (".txt", ".md", ".markdown"):
                doc = self._extract_text_file(file_path)
            else:
                logger.warning(f"Unsupported file type: {suffix}")
                return {"skipped": True, "reason": f"unsupported type: {suffix}"}
        except KeyboardInterrupt:
            raise  # Let Ctrl+C propagate
        except BaseException as exc:
            logger.error(f"Extraction failed for {path.name}: {exc}", exc_info=True)
            return {"skipped": True, "reason": f"extraction error: {exc}"}

        if doc is None or not doc.pages:
            return {"skipped": True, "reason": "no content extracted"}

        logger.debug(f"Extracted {len(doc.pages)} pages from {path.name}")

        # Inject category
        if category:
            doc.metadata["category"] = category

        # ── 2. Chunk ──
        chunks = self.chunker.chunk(doc)
        if not chunks:
            return {"skipped": True, "reason": "no chunks produced"}
        logger.debug(f"Chunked {path.name} → {len(chunks)} chunks")

        # ── 3. Embed ──
        embeddings = self._generate_embeddings(chunks)

        # ── 4. Route to correct collection ──
        # Separate table chunks and image chunks
        doc_chunks = []
        doc_embs = []
        table_chunks = []
        table_embs = []
        image_chunks = []
        image_embs = []
        slide_chunks = []
        slide_embs = []

        for chunk, emb in zip(chunks, embeddings):
            types = set(chunk.element_types)
            if doc.file_type == "pptx":
                slide_chunks.append(chunk)
                slide_embs.append(emb)
            elif "table" in types and len(types) == 1:
                table_chunks.append(chunk)
                table_embs.append(emb)
            elif "image" in types and len(types) == 1:
                image_chunks.append(chunk)
                image_embs.append(emb)
            else:
                doc_chunks.append(chunk)
                doc_embs.append(emb)

        # ── 5. Store ──
        total = 0
        if doc_chunks:
            total += self.store.add_chunks(doc_chunks, doc_embs, "documents")
        if table_chunks:
            total += self.store.add_chunks(table_chunks, table_embs, "tables")
        if image_chunks:
            total += self.store.add_chunks(image_chunks, image_embs, "images")
        if slide_chunks:
            total += self.store.add_chunks(slide_chunks, slide_embs, "slides")

        # Persist
        self.store.persist()

        # Invalidate BM25 index (new data added)
        self.retriever.invalidate_bm25_index()

        logger.info(f"📄 Ingested {path.name}: {total} chunks")
        return {
            "skipped": False,
            "file_type": doc.file_type,
            "pages": len(doc.pages),
            "chunks_created": total,
            "collections": {
                "documents": len(doc_chunks),
                "tables": len(table_chunks),
                "images": len(image_chunks),
                "slides": len(slide_chunks),
            },
        }

    def ingest_all(self, config: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Ingest all documents using the ingestion config.

        Args:
            config: Optional override config. If None, reads from ingestion_config.py.

        Returns:
            Aggregated stats across all categories.
        """
        from .ingestion_config import (
            DOCUMENTS_BASE_PATH,
            DOCUMENT_CATEGORIES,
            SKIP_EXISTING,
        )

        base_path = config.get("base_path", DOCUMENTS_BASE_PATH) if config else DOCUMENTS_BASE_PATH
        categories = config.get("categories", DOCUMENT_CATEGORIES) if config else DOCUMENT_CATEGORIES
        skip = config.get("skip_existing", SKIP_EXISTING) if config else SKIP_EXISTING

        # Resolve base path relative to backend/
        if not os.path.isabs(base_path):
            project_root = Path(__file__).resolve().parents[3]  # backend/app/ingetion -> root
            # Try multiple base paths
            candidates = [
                project_root / base_path,
                project_root / "data" / "documents",
                project_root / "data" / "documents",
            ]
            for candidate in candidates:
                if candidate.exists():
                    base_path = str(candidate)
                    break
            else:
                base_path = str(candidates[1])  # default to data/documents

        print(f"\n  📍 Resolved base path: {base_path}")
        print(f"  📋 Categories to process: {len(categories)}")

        total_stats: Dict[str, Any] = {
            "categories_processed": 0,
            "total_files": 0,
            "total_chunks": 0,
            "total_errors": [],
            "category_stats": {},
        }

        # Track already-ingested files to avoid cross-category duplicates
        ingested_files: set = set()

        cat_index = 0
        cat_total = len(categories)
        for folder, category in categories.items():
            cat_index += 1

            # Handle "ROOT" special key: root-level files only (NOT recursive)
            is_root_only = (folder == "ROOT" or folder == ".")
            if is_root_only:
                dir_path = Path(base_path)
            else:
                dir_path = Path(base_path) / folder

            if not dir_path.exists():
                logger.warning(f"Category directory not found: {dir_path}")
                print(f"  ⚠️  [{cat_index}/{cat_total}] SKIP {category} — directory not found: {dir_path}")
                continue

            print(f"\n  📁 [{cat_index}/{cat_total}] Category: {category}")
            print(f"      Path: {dir_path} {'(root files only)' if is_root_only else ''}")
            logger.info(f"📁 Ingesting category: {category} from {dir_path}")
            stats = self.ingest_directory(
                str(dir_path),
                category=category,
                skip_existing=skip,
                recursive=not is_root_only,
                exclude_files=ingested_files,
            )

            # Track successfully ingested files
            ingested_files.update(stats.get("ingested_paths", set()))

            total_stats["categories_processed"] += 1
            total_stats["total_files"] += stats["files_processed"]
            total_stats["total_chunks"] += stats["chunks_created"]
            total_stats["total_errors"].extend(stats["errors"])
            total_stats["category_stats"][category] = stats
            dupes = stats.get('files_duplicate_skipped', 0)
            dupe_str = f", {dupes} dupes skipped" if dupes else ""
            print(f"      ✅ {stats['files_processed']}/{stats['files_found']} files → {stats['chunks_created']} chunks ({stats['time_seconds']}s{dupe_str})")

        logger.info(
            f"🎉 Full ingestion complete: {total_stats['total_files']} files, "
            f"{total_stats['total_chunks']} chunks across {total_stats['categories_processed']} categories"
        )
        return total_stats

    # ════════════════════════════════════════════════════
    #  RETRIEVAL
    # ════════════════════════════════════════════════════

    def query(
        self,
        question: str,
        *,
        top_k: int = 8,
        collections: Optional[List[str]] = None,
    ) -> SynthesizedAnswer:
        """
        Answer a question using the RAG pipeline.

        Args:
            question: The user's question.
            top_k: Number of chunks to use for context.
            collections: Which collections to search (default: all).

        Returns:
            SynthesizedAnswer with text, confidence, citations.
        """
        # 1. Embed query
        query_embedding = self.llm.generate_embedding(question)

        # 2. Hybrid retrieval
        retrieved = self.retriever.retrieve(
            query=question,
            query_embedding=query_embedding,
            collections=collections,
        )

        # 3. Rerank
        reranked = self.reranker.rerank(question, retrieved, top_k=top_k)

        # 4. Assemble context
        context, sources = self.context_assembler.assemble(reranked)

        # 5. Synthesize answer
        answer = self.answer_synthesizer.synthesize(
            query=question,
            context=context,
            sources=sources,
            retrieved_chunks=reranked,
        )

        return answer

    def retrieve_context(
        self,
        question: str,
        *,
        top_k: int = 8,
        collections: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Retrieve relevant context WITHOUT synthesizing an answer.

        Use this when the caller (e.g., KnowledgeBaseService) wants to handle
        LLM generation itself but needs ChromaDB-backed hybrid retrieval.

        Returns:
            Dict with:
                context: str — assembled context text
                sources: List[Source] — citations
                retrieved_chunks: List[RetrievedChunk] — raw reranked chunks
                confidence: float — retrieval confidence estimate
        """
        # 1. Embed query
        query_embedding = self.llm.generate_embedding(question)

        # 2. Hybrid retrieval (vector + BM25 + RRF)
        retrieved = self.retriever.retrieve(
            query=question,
            query_embedding=query_embedding,
            collections=collections,
        )

        # 3. Rerank
        reranked = self.reranker.rerank(question, retrieved, top_k=top_k)

        # 4. Assemble context with citations
        context, sources = self.context_assembler.assemble(reranked)

        # 5. Estimate retrieval confidence
        if reranked:
            scores = [c.score for c in reranked]
            confidence = round(min(scores[0] * 0.6 + (sum(scores[:3]) / max(len(scores[:3]), 1)) * 0.4, 1.0), 2)
        else:
            confidence = 0.0

        # 6. Select images for display (if enabled)
        display_images = []
        if self.image_display_engine:
            display_images = self.image_display_engine.select_images(reranked, question)

        return {
            "context": context,
            "sources": sources,
            "retrieved_chunks": reranked,
            "confidence": confidence,
            "images": [img.to_dict() for img in display_images],
        }

    # ════════════════════════════════════════════════════
    #  HELPERS
    # ════════════════════════════════════════════════════

    def _generate_embeddings(
        self, chunks: List[HierarchicalChunk]
    ) -> List[List[float]]:
        """
        Generate embeddings for chunks using batch API when possible.
        
        OpenAI embeddings.create() accepts a list of inputs (up to 2048),
        which is ~50x faster than one-at-a-time calls.
        """
        from .ingestion_config import EMBEDDING_BATCH_SIZE
        batch_size = EMBEDDING_BATCH_SIZE if hasattr(EMBEDDING_BATCH_SIZE, '__int__') else 64
        try:
            batch_size = int(EMBEDDING_BATCH_SIZE)
        except Exception:
            batch_size = 64

        total = len(chunks)
        if total == 0:
            return []

        # Prepare texts (truncate to 8000 chars for API limits)
        texts = [c.content[:8000] for c in chunks]

        # Try batch embedding via OpenAI first (MUCH faster).
        # Guard: only use batch if openai_client is a real OpenAI object, not a mock.
        try:
            client = getattr(self.llm, 'openai_client', None)
            if client is not None and type(client).__module__.startswith('openai'):
                embeddings = self._batch_embed_openai(texts, batch_size, total)
                # Validate: if all embeddings are zero-vectors, the batch failed
                if any(any(v != 0.0 for v in e[:5]) for e in embeddings):
                    return embeddings
                logger.warning("Batch embed returned all zero vectors, falling back to sequential")
        except Exception as exc:
            logger.warning(f"Batch embed attempt failed: {exc}")

        # Fallback: one-at-a-time via LLMService (works with any provider incl. mocks)
        return self._sequential_embed(texts, chunks, total)

    def _batch_embed_openai(
        self, texts: List[str], batch_size: int, total: int
    ) -> List[List[float]]:
        """Batch embed using OpenAI API (up to 2048 inputs per call)."""
        embeddings: List[List[float]] = []
        model = self.llm.embedding_model
        client = self.llm.openai_client
        failed = 0

        for i in range(0, total, batch_size):
            batch_texts = texts[i : i + batch_size]
            batch_end = min(i + batch_size, total)
            try:
                response = client.embeddings.create(
                    model=model,
                    input=batch_texts,
                )
                # Response data comes sorted by index
                batch_embs = [d.embedding for d in sorted(response.data, key=lambda x: x.index)]
                embeddings.extend(batch_embs)
                if total > 20:
                    print(f"[emb {batch_end}/{total}]", end=" ", flush=True)
            except Exception as exc:
                # Fallback: generate zero vectors for this batch
                failed += len(batch_texts)
                logger.warning(f"Batch embedding failed (batch {i}-{batch_end}): {exc}")
                if failed <= batch_size:  # Only print first failure
                    print(f"\n        ⚠️ Batch embed failed: {str(exc)[:100]}")
                embeddings.extend([[0.0] * 384] * len(batch_texts))

        if failed:
            print(f"\n        ⚠️ {failed}/{total} embeddings used zero-vector fallback")
        return embeddings

    def _sequential_embed(
        self, texts: List[str], chunks: List[HierarchicalChunk], total: int
    ) -> List[List[float]]:
        """Fallback: embed one-at-a-time via LLMService (HuggingFace/mock)."""
        embeddings: List[List[float]] = []
        failed = 0
        for idx, text in enumerate(texts, 1):
            try:
                emb = self.llm.generate_embedding(text)
                embeddings.append(emb)
            except Exception as exc:
                failed += 1
                logger.warning(f"Embedding failed for chunk {chunks[idx-1].chunk_id}: {exc}")
                if failed <= 3:
                    print(f"\n        ⚠️ Embedding failed ({failed}): {str(exc)[:80]}")
                embeddings.append([0.0] * 384)
            if total > 20 and idx % 25 == 0:
                print(f"[emb {idx}/{total}]", end=" ", flush=True)
        if failed:
            print(f"\n        ⚠️ {failed}/{total} embeddings used zero-vector fallback")
        return embeddings

    def _extract_text_file(self, file_path: str) -> ExtractedDocument:
        """Simple text file extraction."""
        from .models import ExtractedPage, ExtractedElement

        path = Path(file_path)
        doc = ExtractedDocument(
            source_path=str(path),
            file_type="txt",
            title=path.stem,
            metadata={"filename": path.name},
        )
        try:
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
            if text.strip():
                doc.pages = [
                    ExtractedPage(
                        page_number=1,
                        raw_text=text,
                        composite_text=text,
                        elements=[
                            ExtractedElement(
                                content=text,
                                element_type="text",
                                page_number=1,
                            )
                        ],
                    )
                ]
        except Exception as exc:
            logger.error(f"Text file read failed: {exc}")

        return doc

    def get_status(self) -> Dict[str, Any]:
        """Get pipeline status and collection counts."""
        counts = self.store.get_collection_counts()
        return {
            "collections": counts,
            "total_chunks": sum(counts.values()),
            "image_describer_available": (
                self.image_describer.is_available if self.image_describer else False
            ),
            "persist_directory": self.store.persist_dir,
        }
