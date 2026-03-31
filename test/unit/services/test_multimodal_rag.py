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
