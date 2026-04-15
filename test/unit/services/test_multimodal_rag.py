"""
Unit Tests — Multimodal RAG Components

Tests for:
  - ImageReference serialisation / deserialisation
  - CompositeBlock combined text generation
  - HierarchicalChunk image fields & serialisation
  - RetrievedChunk image fields
  - ImageDisplayEngine image selection & dedup
  - ImageStore path generation
  - ChatResponse images field
"""

import json
import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "backend"))

from app.ingetion.models import (
    ImageReference,
    CompositeBlock,
    HierarchicalChunk,
    RetrievedChunk,
    ExtractedElement,
)
from app.ingetion.retrieval.image_display_engine import (
    ImageDisplayEngine,
    DisplayImage,
)
from app.models.schemas import ChatResponse, ChatbotType


# ═══════════════════════════════════════════════════════
#  ImageReference
# ═══════════════════════════════════════════════════════
class TestImageReference:

    def test_to_dict_basic(self):
        ref = ImageReference(
            image_path="extracted_images/abc123/p1_0.png",
            page_number=1,
            width=800,
            height=600,
        )
        d = ref.to_dict()
        assert d["image_path"] == "extracted_images/abc123/p1_0.png"
        assert d["page_number"] == 1
        assert d["width"] == 800
        assert d["height"] == 600
        assert d["bbox"] is None

    def test_to_dict_with_bbox(self):
        ref = ImageReference(
            image_path="img.png",
            bbox=(10.0, 20.0, 300.0, 400.0),
        )
        d = ref.to_dict()
        assert d["bbox"] == [10.0, 20.0, 300.0, 400.0]

    def test_from_dict_roundtrip(self):
        original = ImageReference(
            image_path="test/img.png",
            page_number=5,
            bbox=(1.0, 2.0, 3.0, 4.0),
            caption="Flow diagram",
            ocr_text="Step 1 → Step 2",
            description="A flowchart showing…",
            width=640,
            height=480,
        )
        d = original.to_dict()
        restored = ImageReference.from_dict(d)
        assert restored.image_path == original.image_path
        assert restored.page_number == original.page_number
        assert restored.bbox == original.bbox
        assert restored.caption == original.caption
        assert restored.ocr_text == original.ocr_text
        assert restored.description == original.description
        assert restored.width == original.width
        assert restored.height == original.height

    def test_from_dict_missing_fields(self):
        ref = ImageReference.from_dict({"image_path": "x.png"})
        assert ref.image_path == "x.png"
        assert ref.page_number == 0
        assert ref.bbox is None
        assert ref.caption == ""

    def test_get_searchable_text_all_fields(self):
        ref = ImageReference(
            image_path="img.png",
            caption="HHD device",
            ocr_text="Handheld Terminal",
            description="A warehouse handheld scanner",
        )
        text = ref.get_searchable_text()
        assert "HHD device" in text
        assert "Handheld Terminal" in text
        assert "warehouse handheld scanner" in text

    def test_get_searchable_text_empty(self):
        ref = ImageReference(image_path="img.png")
        assert ref.get_searchable_text() == ""


# ═══════════════════════════════════════════════════════
#  CompositeBlock
# ═══════════════════════════════════════════════════════
class TestCompositeBlock:

    def test_has_images(self):
        block = CompositeBlock(text="Hello")
        assert block.has_images is False

        block_with = CompositeBlock(
            text="Hello",
            images=[ImageReference(image_path="a.png")],
        )
        assert block_with.has_images is True

    def test_get_combined_text_no_images(self):
        block = CompositeBlock(text="Pure text block")
        assert block.get_combined_text() == "Pure text block"

    def test_get_combined_text_with_images(self):
        block = CompositeBlock(
            text="Conveyor layout",
            images=[
                ImageReference(image_path="a.png", description="Top view of conveyor"),
                ImageReference(image_path="b.png"),  # no text
            ],
        )
        combined = block.get_combined_text()
        assert "Conveyor layout" in combined
        assert "[Image: Top view of conveyor]" in combined


# ═══════════════════════════════════════════════════════
#  HierarchicalChunk — Image Fields
# ═══════════════════════════════════════════════════════
class TestHierarchicalChunkImages:

    def _make_chunk(self, **kwargs):
        defaults = dict(
            chunk_id="test__L2_S0_P0",
            content="Test content",
            level=2,
        )
        defaults.update(kwargs)
        return HierarchicalChunk(**defaults)

    def test_has_images_false(self):
        chunk = self._make_chunk()
        assert chunk.has_images is False

    def test_has_images_true_from_list(self):
        chunk = self._make_chunk(
            images=[ImageReference(image_path="a.png")],
        )
        assert chunk.has_images is True

    def test_has_images_true_from_count(self):
        chunk = self._make_chunk(image_count=2)
        assert chunk.has_images is True

    def test_get_embeddable_content_plain(self):
        chunk = self._make_chunk(content="Plain text")
        assert chunk.get_embeddable_content() == "Plain text"

    def test_get_embeddable_content_combined(self):
        chunk = self._make_chunk(
            content="Main text",
            combined_content="Main text\n[Image: diagram]",
        )
        assert "[Image: diagram]" in chunk.get_embeddable_content()

    def test_serialise_images_json_empty(self):
        chunk = self._make_chunk()
        assert chunk.serialise_images_json() == "[]"

    def test_serialise_images_json_roundtrip(self):
        imgs = [
            ImageReference(image_path="a.png", page_number=1, caption="Fig 1"),
            ImageReference(image_path="b.png", page_number=2, width=640),
        ]
        chunk = self._make_chunk(images=imgs, image_count=2)
        raw = chunk.serialise_images_json()

        # Verify valid JSON
        parsed = json.loads(raw)
        assert len(parsed) == 2
        assert parsed[0]["image_path"] == "a.png"
        assert parsed[1]["width"] == 640

        # Roundtrip
        restored = HierarchicalChunk.deserialise_images_json(raw)
        assert len(restored) == 2
        assert restored[0].caption == "Fig 1"
        assert restored[1].page_number == 2

    def test_deserialise_images_json_empty_string(self):
        assert HierarchicalChunk.deserialise_images_json("") == []
        assert HierarchicalChunk.deserialise_images_json("[]") == []

    def test_deserialise_images_json_invalid(self):
        assert HierarchicalChunk.deserialise_images_json("not json") == []


# ═══════════════════════════════════════════════════════
#  RetrievedChunk — Image Fields
# ═══════════════════════════════════════════════════════
class TestRetrievedChunkImages:

    def test_has_images_default(self):
        chunk = RetrievedChunk(chunk_id="x", content="text", score=0.8)
        assert chunk.has_images is False
        assert chunk.images == []
        assert chunk.image_count == 0

    def test_has_images_with_refs(self):
        chunk = RetrievedChunk(
            chunk_id="x",
            content="text",
            score=0.8,
            images=[ImageReference(image_path="a.png")],
            image_count=1,
        )
        assert chunk.has_images is True


# ═══════════════════════════════════════════════════════
#  ImageDisplayEngine
# ═══════════════════════════════════════════════════════
class TestImageDisplayEngine:

    def _make_chunk(self, score=0.8, images=None):
        return RetrievedChunk(
            chunk_id="c1",
            content="text",
            score=score,
            source_path="/docs/manual.pdf",
            metadata={"filename": "manual.pdf"},
            images=images or [],
            image_count=len(images or []),
        )

    def test_empty_chunks(self):
        engine = ImageDisplayEngine()
        result = engine.select_images([])
        assert result == []

    def test_chunks_without_images(self):
        engine = ImageDisplayEngine()
        chunk = self._make_chunk(score=0.9)
        assert engine.select_images([chunk]) == []

    def test_basic_image_selection(self):
        engine = ImageDisplayEngine()
        imgs = [
            ImageReference(image_path="img/p1_0.png", page_number=1, width=200, height=200, description="Conveyor diagram"),
        ]
        chunk = self._make_chunk(score=0.85, images=imgs)
        result = engine.select_images([chunk])
        assert len(result) == 1
        assert result[0].image_path == "img/p1_0.png"
        assert result[0].relevance_score == 0.85
        assert result[0].source_document == "manual.pdf"
        assert result[0].caption == "Conveyor diagram"

    def test_deduplication(self):
        engine = ImageDisplayEngine()
        img = ImageReference(image_path="img/same.png", width=200, height=200)
        chunk1 = self._make_chunk(score=0.9, images=[img])
        chunk2 = self._make_chunk(score=0.7, images=[img])
        chunk2.chunk_id = "c2"
        result = engine.select_images([chunk1, chunk2])
        assert len(result) == 1  # deduped by path

    def test_low_score_filtered(self):
        engine = ImageDisplayEngine(min_chunk_score=0.5)
        imgs = [ImageReference(image_path="img/low.png", width=200, height=200)]
        chunk = self._make_chunk(score=0.2, images=imgs)
        result = engine.select_images([chunk])
        assert len(result) == 0

    def test_tiny_image_filtered(self):
        engine = ImageDisplayEngine(min_image_size=100)
        imgs = [ImageReference(image_path="img/tiny.png", width=50, height=50)]
        chunk = self._make_chunk(score=0.9, images=imgs)
        result = engine.select_images([chunk])
        assert len(result) == 0

    def test_max_images_cap(self):
        engine = ImageDisplayEngine(max_images=2)
        imgs = [
            ImageReference(image_path=f"img/p{i}.png", width=200, height=200)
            for i in range(5)
        ]
        chunk = self._make_chunk(score=0.8, images=imgs)
        result = engine.select_images([chunk])
        assert len(result) == 2

    def test_sorted_by_relevance(self):
        engine = ImageDisplayEngine()
        img_a = ImageReference(image_path="img/a.png", width=200, height=200)
        img_b = ImageReference(image_path="img/b.png", width=200, height=200)
        chunk_high = self._make_chunk(score=0.95, images=[img_a])
        chunk_low = self._make_chunk(score=0.6, images=[img_b])
        chunk_low.chunk_id = "c2"
        result = engine.select_images([chunk_low, chunk_high])
        assert result[0].image_path == "img/a.png"
        assert result[1].image_path == "img/b.png"

    def test_display_image_to_dict(self):
        di = DisplayImage(
            image_path="img/p1_0.png",
            page_number=3,
            caption="A diagram",
            source_document="doc.pdf",
            relevance_score=0.8765,
            width=640,
            height=480,
        )
        d = di.to_dict()
        assert d["image_path"] == "img/p1_0.png"
        assert d["relevance_score"] == 0.876  # rounded to 3 dp

    def test_caption_dedup_same_page(self):
        """Images from the same page with near-identical captions should be deduped."""
        engine = ImageDisplayEngine(max_images=5)
        imgs = [
            ImageReference(
                image_path=f"img/p33_{i}.png", page_number=33,
                width=200 + i * 50, height=200,
                caption="Cross Belt Sorter – Regular: Single Belt"
            )
            for i in range(3)
        ]
        chunk = self._make_chunk(score=0.9, images=imgs)
        chunk.metadata["filename"] = "sorters.pptx"
        result = engine.select_images([chunk])
        # Should keep only the largest image (width=300)
        assert len(result) == 1
        assert result[0].width == 300

    def test_caption_dedup_different_captions_kept(self):
        """Images from the same page with DIFFERENT captions should be kept."""
        engine = ImageDisplayEngine(max_images=5)
        imgs = [
            ImageReference(image_path="img/p5_0.png", page_number=5, width=200, height=200,
                           caption="Carrier belt design details"),
            ImageReference(image_path="img/p5_1.png", page_number=5, width=200, height=200,
                           caption="Chute configuration overview"),
        ]
        chunk = self._make_chunk(score=0.9, images=imgs)
        chunk.metadata["filename"] = "manual.pdf"
        result = engine.select_images([chunk])
        assert len(result) == 2

    def test_diversity_across_documents(self):
        """Images from different documents should be preferred over all from one doc."""
        engine = ImageDisplayEngine(max_images=3)
        # 3 images from doc A, 1 from doc B
        chunk_a = self._make_chunk(score=0.95, images=[
            ImageReference(image_path=f"img/a_p{i}.png", page_number=i, width=200, height=200,
                           caption=f"Diagram A{i}")
            for i in range(3)
        ])
        chunk_a.metadata["filename"] = "docA.pptx"
        chunk_b = self._make_chunk(score=0.80, images=[
            ImageReference(image_path="img/b_p1.png", page_number=1, width=200, height=200,
                           caption="Diagram B1"),
        ])
        chunk_b.chunk_id = "c2"
        chunk_b.metadata["filename"] = "docB.pdf"
        result = engine.select_images([chunk_a, chunk_b])
        assert len(result) == 3
        # At least one image from docB should appear
        doc_names = [r.source_document for r in result]
        assert "docB.pdf" in doc_names

    def test_caption_similarity_scores(self):
        """Verify _caption_similarity returns expected values."""
        assert ImageDisplayEngine._caption_similarity("", "") == 0.0
        assert ImageDisplayEngine._caption_similarity("Hello World", "Hello World") == 1.0
        sim = ImageDisplayEngine._caption_similarity(
            "Cross Belt Sorter Regular Single Belt",
            "Cross Belt Sorter Regular Single Belt extra"
        )
        assert sim > 0.80  # high overlap despite one extra word


# ═══════════════════════════════════════════════════════
#  ChatResponse — images field
# ═══════════════════════════════════════════════════════
class TestChatResponseImages:

    def test_default_images_empty(self):
        resp = ChatResponse(
            response="Test",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
        )
        assert resp.images == []

    def test_images_field_populated(self):
        img_data = [
            {"image_path": "img/p1.png", "page_number": 1, "caption": "Diagram"},
        ]
        resp = ChatResponse(
            response="Test",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            images=img_data,
        )
        assert len(resp.images) == 1
        assert resp.images[0]["image_path"] == "img/p1.png"

    def test_images_serializes_to_json(self):
        img_data = [{"image_path": "img/a.png", "caption": "Fig 1"}]
        resp = ChatResponse(
            response="Test",
            chatbot_type=ChatbotType.KNOWLEDGE_BASE,
            images=img_data,
        )
        serialized = resp.model_dump()
        assert "images" in serialized
        assert len(serialized["images"]) == 1


# ═══════════════════════════════════════════════════════
#  Phase 1 — Content Streams & Embedding Fix
# ═══════════════════════════════════════════════════════
class TestContentStreams:
    """Tests for the new embedding_text / display_text / image_text fields."""

    def test_build_content_streams_no_images(self):
        """Chunk without images should have embedding_text == content."""
        chunk = HierarchicalChunk(
            chunk_id="test_cs_001",
            content="Plain paragraph about warehouse operations.",
            level=2,
        )
        chunk.build_content_streams()
        assert chunk.display_text == chunk.content
        assert chunk.image_text == ""
        assert chunk.embedding_text == chunk.content
        assert chunk.combined_content == chunk.content

    def test_build_content_streams_with_images(self):
        """Chunk with images should include image text in embedding_text."""
        img = ImageReference(
            image_path="img/p1.png",
            caption="Conveyor layout diagram",
            ocr_text="Belt A → Belt B",
            description="Schematic of conveyor flow",
        )
        chunk = HierarchicalChunk(
            chunk_id="test_cs_002",
            content="The conveyor system routes packages.",
            level=2,
            images=[img],
            image_count=1,
        )
        chunk.build_content_streams()
        assert chunk.display_text == "The conveyor system routes packages."
        assert "Conveyor layout diagram" in chunk.image_text
        assert "Belt A" in chunk.image_text
        assert "[Image context:" in chunk.embedding_text
        assert "Conveyor layout diagram" in chunk.embedding_text
        # combined_content should match embedding_text
        assert chunk.combined_content == chunk.embedding_text

    def test_get_embeddable_content_priority(self):
        """get_embeddable_content() should prefer embedding_text > combined_content > content."""
        chunk = HierarchicalChunk(
            chunk_id="test_cs_003",
            content="fallback",
            level=2,
        )
        assert chunk.get_embeddable_content() == "fallback"

        chunk.combined_content = "combined"
        assert chunk.get_embeddable_content() == "combined"

        chunk.embedding_text = "embedding"
        assert chunk.get_embeddable_content() == "embedding"

    def test_get_display_content_priority(self):
        """get_display_content() should prefer display_text > content."""
        chunk = HierarchicalChunk(
            chunk_id="test_cs_004",
            content="raw content",
            level=2,
        )
        assert chunk.get_display_content() == "raw content"

        chunk.display_text = "clean display"
        assert chunk.get_display_content() == "clean display"

    def test_get_image_text_from_images(self):
        """get_image_text() should concatenate text from all image references."""
        img1 = ImageReference(image_path="a.png", caption="First image caption")
        img2 = ImageReference(image_path="b.png", caption="Second image caption", ocr_text="OCR text")
        chunk = HierarchicalChunk(
            chunk_id="test_cs_005",
            content="Text",
            level=2,
            images=[img1, img2],
        )
        text = chunk.get_image_text()
        assert "First image caption" in text
        assert "Second image caption" in text
        assert "OCR text" in text

    def test_build_content_streams_multiple_images(self):
        """Multiple images should all contribute to image_text and embedding_text."""
        imgs = [
            ImageReference(image_path="a.png", caption="Diagram A"),
            ImageReference(image_path="b.png", caption="Diagram B", ocr_text="Step 1"),
            ImageReference(image_path="c.png", description="Overview chart"),
        ]
        chunk = HierarchicalChunk(
            chunk_id="test_cs_006",
            content="Warehouse overview section.",
            level=2,
            images=imgs,
            image_count=3,
        )
        chunk.build_content_streams()
        assert "Diagram A" in chunk.image_text
        assert "Diagram B" in chunk.image_text
        assert "Step 1" in chunk.image_text
        assert "Overview chart" in chunk.image_text
        assert "Warehouse overview section." in chunk.embedding_text
        assert "[Image context:" in chunk.embedding_text

    def test_retrieved_chunk_has_new_fields(self):
        """RetrievedChunk should have embedding_text, display_text, image_text fields."""
        rc = RetrievedChunk(
            chunk_id="rc_001",
            content="Display text",
            score=0.9,
            embedding_text="enriched text with images",
            display_text="Display text",
            image_text="caption from image",
        )
        assert rc.embedding_text == "enriched text with images"
        assert rc.display_text == "Display text"
        assert rc.image_text == "caption from image"


# ═══════════════════════════════════════════════════════
#  Phase 2 — Image Distribution / Correlation
# ═══════════════════════════════════════════════════════
from app.ingetion.chunkers.hierarchical_chunker import HierarchicalChunker


class TestImageDistribution:
    """Tests for _distribute_images_to_leaves (Phase 2 upgrade)."""

    def test_single_leaf_gets_all_images(self):
        """With only one leaf, all images should go to index 0."""
        imgs = [
            ImageReference(image_path="a.png", caption="Conveyor layout"),
            ImageReference(image_path="b.png", caption="Pick station"),
        ]
        result = HierarchicalChunker._distribute_images_to_leaves(imgs, ["text"], 1)
        assert len(result[0]) == 2

    def test_empty_images(self):
        """No images should produce empty result."""
        result = HierarchicalChunker._distribute_images_to_leaves([], ["text1", "text2"], 2)
        assert result == {}

    def test_empty_leaves(self):
        """No leaves should produce empty result."""
        imgs = [ImageReference(image_path="a.png", caption="test")]
        result = HierarchicalChunker._distribute_images_to_leaves(imgs, [], 0)
        assert result == {}

    def test_image_assigned_to_matching_leaf(self):
        """Image with caption matching leaf text should go to that leaf."""
        imgs = [
            ImageReference(
                image_path="conveyor.png",
                caption="conveyor belt layout with sorting",
            ),
        ]
        leaves = [
            "The warehouse has many storage racks and bins arranged in rows.",
            "The conveyor belt system handles sorting and routing of packages.",
        ]
        result = HierarchicalChunker._distribute_images_to_leaves(imgs, leaves, 2)
        # Image caption matches "conveyor" and "sorting" in leaf 1 (index 1)
        assert 1 in result
        assert len(result[1]) == 1
        assert result[1][0].image_path == "conveyor.png"

    def test_multiple_images_different_leaves(self):
        """Different images should be assigned to their best-matching leaves."""
        imgs = [
            ImageReference(image_path="robot.png", caption="robot arm picking items"),
            ImageReference(image_path="rack.png", caption="storage rack configuration"),
        ]
        leaves = [
            "The robotic arm picks items from bins and places them on conveyor.",
            "Storage racks are configured in a grid pattern for optimal space.",
        ]
        result = HierarchicalChunker._distribute_images_to_leaves(imgs, leaves, 2)
        # robot image → leaf 0 (robot, picking, items)
        # rack image → leaf 1 (storage, rack, configuration)
        assert 0 in result
        assert any(img.image_path == "robot.png" for img in result.get(0, []))
        assert 1 in result
        assert any(img.image_path == "rack.png" for img in result.get(1, []))

    def test_no_text_image_falls_back_to_first_leaf(self):
        """Image with no searchable text should default to first leaf."""
        imgs = [ImageReference(image_path="mystery.png")]
        leaves = ["First leaf text.", "Second leaf text."]
        result = HierarchicalChunker._distribute_images_to_leaves(imgs, leaves, 2)
        assert 0 in result
        assert len(result[0]) == 1


# ════════════════════════════════════════════════════════════
#  Phase 7 — Answer Planner tests
# ════════════════════════════════════════════════════════════

class TestAnswerPlanner:
    """Tests for AnswerPlanner query classification and plan building."""

    @pytest.fixture(autouse=True)
    def setup(self):
        from app.services.answer_planner import AnswerPlanner
        self.planner = AnswerPlanner()

    def _make_chunk(self, cid="c1", content="some content", source="doc.pdf", score=0.9):
        return RetrievedChunk(
            chunk_id=cid,
            content=content,
            source_path=source,
            score=score,
            section_path=["Doc", "Section"],
        )

    def test_classify_factual(self):
        assert self.planner._classify("what is the neo system?") == "factual"
        assert self.planner._classify("how many warehouses are supported?") == "factual"

    def test_classify_procedural(self):
        assert self.planner._classify("how to configure the robot arm?") == "procedural"
        assert self.planner._classify("steps to setup the database") == "procedural"

    def test_classify_comparison(self):
        assert self.planner._classify("compare fifo and lifo strategies") == "comparison"
        assert self.planner._classify("difference between a and b") == "comparison"

    def test_classify_exploratory(self):
        assert self.planner._classify("explain the architecture of neo") == "exploratory"

    def test_classify_default_exploratory(self):
        assert self.planner._classify("tell me everything") == "exploratory"

    def test_plan_factual_sections(self):
        chunks = [self._make_chunk(f"c{i}") for i in range(5)]
        plan = self.planner.plan("What is NEO?", chunks)
        assert plan.query_type == "factual"
        assert len(plan.sections) >= 1
        assert plan.sections[0].heading == "Answer"

    def test_plan_procedural_sections(self):
        chunks = [self._make_chunk(f"c{i}") for i in range(8)]
        plan = self.planner.plan("How to configure the system?", chunks)
        assert plan.query_type == "procedural"
        headings = [s.heading for s in plan.sections]
        assert "Steps" in headings

    def test_plan_with_images(self):
        chunks = [self._make_chunk()]
        images = [{"image_path": "img1.png", "caption": "Test image"}]
        plan = self.planner.plan("What is this?", chunks, images=images)
        assert plan.total_figures >= 1

    def test_to_prompt_context(self):
        chunks = [self._make_chunk()]
        plan = self.planner.plan("What is NEO?", chunks)
        ctx = plan.to_prompt_context()
        assert "ANSWER BRIEF" in ctx
        assert "SECTION 1" in ctx


# ════════════════════════════════════════════════════════════
#  Phase 8 — Response Structurer tests
# ════════════════════════════════════════════════════════════

class TestResponseStructurer:
    """Tests for ResponseStructurer parsing."""

    @pytest.fixture(autouse=True)
    def setup(self):
        from app.services.response_structurer import ResponseStructurer
        self.structurer = ResponseStructurer()

    def test_empty_response(self):
        result = self.structurer.structure("")
        assert result.summary == ""
        assert result.sections == []

    def test_single_paragraph(self):
        result = self.structurer.structure("NEO is a warehouse management system.")
        assert len(result.sections) == 1
        assert "NEO" in result.summary

    def test_heading_split(self):
        text = "## Overview\nNEO manages warehouses.\n\n## Features\nRobotic automation and more."
        result = self.structurer.structure(text)
        assert len(result.sections) == 2
        assert result.sections[0].heading == "Overview"
        assert result.sections[1].heading == "Features"

    def test_figure_references(self):
        text = "## Details\nSee Figure 1 and Figure 2 for the architecture."
        images = [
            {"image_path": "arch.png", "caption": "Architecture"},
            {"image_path": "flow.png", "caption": "Flow"},
        ]
        result = self.structurer.structure(text, images=images)
        assert result.sections[0].figures == [1, 2]
        assert len(result.figures) == 2
        assert result.figures[0]["figure_number"] == 1

    def test_citations_from_sources(self):
        from app.models.schemas import SourceDocument
        sources = [
            SourceDocument(document_name="guide.pdf", content_snippet="WMS overview", relevance_score=0.9, document_type="pdf"),
            SourceDocument(document_name="spec.docx", content_snippet="API spec", relevance_score=0.8, page_number=5, document_type="docx"),
        ]
        result = self.structurer.structure("Some answer text.", source_documents=sources)
        assert len(result.citations) == 2
        assert result.citations[0]["document"] == "guide.pdf"
        assert result.citations[1]["page"] == "5"

    def test_bold_heading_split(self):
        text = "First para.\n\n**Key Features**\nFeature list here."
        result = self.structurer.structure(text)
        assert any(s.heading == "Key Features" for s in result.sections)

    def test_summary_truncation(self):
        long_text = "A" * 500 + ". Next sentence."
        result = self.structurer.structure(long_text)
        assert len(result.summary) <= 401  # 400 + "..."
