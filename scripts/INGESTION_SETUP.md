# Document Ingestion Setup Guide

## 📦 Required Packages

Install these Python packages for full PDF processing with OCR support:

```powershell
# Basic PDF text extraction
.\venv\Scripts\pip install PyPDF2

# Advanced PDF handling with images
.\venv\Scripts\pip install PyMuPDF

# OCR (Optical Character Recognition) for images
.\venv\Scripts\pip install pytesseract pillow
```

## 🔧 Tesseract OCR Installation (Required for Images)

### Windows Installation:

1. **Download Tesseract Installer:**
   - Go to: https://github.com/UB-Mannheim/tesseract/wiki
   - Download: `tesseract-ocr-w64-setup-5.3.3.20231005.exe` (or latest version)
   - Or direct link: https://digi.bib.uni-mannheim.de/tesseract/

2. **Install Tesseract:**
   - Run the installer
   - **Important:** During installation, note the installation path
   - Default path: `C:\Program Files\Tesseract-OCR`
   - Make sure to check "Add to PATH" during installation

3. **Configure Python to Find Tesseract:**
   
   **Option A: Add to System PATH** (Recommended)
   - Open System Environment Variables
   - Add `C:\Program Files\Tesseract-OCR` to PATH
   - Restart your terminal

   **Option B: Set in Code** (Alternative)
   - The script will auto-detect if Tesseract is in PATH
   - If not found, you can manually set the path in the script

4. **Verify Installation:**
   ```powershell
   tesseract --version
   ```
   Should show: `tesseract v5.3.3` or similar

## 🚀 Quick Start Commands

### Option 1: Full Installation (Text + Images with OCR)
```powershell
# Install all packages
.\venv\Scripts\pip install PyPDF2 PyMuPDF pytesseract pillow

# Install Tesseract OCR (follow steps above)

# Run ingestion with OCR
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py
```

### Option 2: Basic Installation (Text Only, No OCR)
```powershell
# Install basic packages only
.\venv\Scripts\pip install PyPDF2 PyMuPDF

# Run ingestion without OCR (skip images)
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py --no-ocr
```

## 📋 Usage Examples

### Ingest all documents from default folder (with OCR):
```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py
```

### Ingest without OCR (faster, but skips image text):
```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py --no-ocr
```

### Ingest a single file:
```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py --file "path/to/document.pdf"
```

### Ingest from custom folder:
```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py --folder "path/to/documents"
```

### Set custom category:
```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\ingest_documents.py --category "training_manual"
```

## 📊 What Gets Extracted

### From Regular PDF Text:
- All selectable/copyable text
- Headers, paragraphs, tables (as text)
- Bullet points and numbered lists

### From Images (with OCR enabled):
- Text embedded in images
- Scanned document text
- Screenshots with text
- Diagrams with labels
- Text from photos

### Metadata Stored:
- Filename
- Document type (PDF)
- Category
- Chunk index
- Total chunks
- Page numbers (for images)

## 🎯 Expected Output

```
================================================================================
NEO DOCUMENT INGESTION
================================================================================

📁 Processing documents from: app/modules/neo_chatbot/data/documents
================================================================================
Found 2 PDF files

📥 Ingesting document: Dashboard Manual.pdf
📄 Extracting text from: Dashboard Manual.pdf
   Extracting regular text...
   Found 15 pages
   ✅ Extracted 12500 characters from regular text
🖼️ Extracting text from images using OCR...
   ✅ Extracted text from 8 images (3200 characters)
   ✅ Total text: 15700 characters (including OCR)
✂️ Splitting into chunks...
   Created 18 chunks
💾 Adding to vector store...
✅ Successfully ingested Dashboard Manual.pdf (18 chunks)

📥 Ingesting document: SOP Document NEO ASRS.pdf
📄 Extracting text from: SOP Document NEO ASRS.pdf
   Extracting regular text...
   Found 23 pages
   ✅ Extracted 18900 characters from regular text
🖼️ Extracting text from images using OCR...
   ✅ Extracted text from 12 images (4800 characters)
   ✅ Total text: 23700 characters (including OCR)
✂️ Splitting into chunks...
   Created 26 chunks
💾 Adding to vector store...
✅ Successfully ingested SOP Document NEO ASRS.pdf (26 chunks)

================================================================================
📊 INGESTION SUMMARY
================================================================================
✅ Successful: 2
❌ Failed: 0
📦 Total chunks created: 44

================================================================================
✅ INGESTION COMPLETE
================================================================================
```

## 🔍 Testing the Knowledge Base

After ingestion, test with:

```powershell
$env:PYTHONPATH="C:\Users\Balmukund.Mishra\Desktop\NEO\association_mining_system"
.\venv\Scripts\python.exe app\modules\neo_chatbot\scripts\test_knowledge_base.py
```

## ⚠️ Troubleshooting

### "Tesseract not found" error:
- Make sure Tesseract is installed
- Check if `C:\Program Files\Tesseract-OCR` exists
- Verify Tesseract is in PATH: `tesseract --version`
- Or run with `--no-ocr` flag to skip OCR

### "Module not found" errors:
- Make sure all packages are installed in venv
- Verify PYTHONPATH is set correctly

### OCR is slow:
- OCR can take 2-5 seconds per image
- For faster ingestion, use `--no-ocr` flag
- Or upgrade Tesseract to GPU version

### Poor OCR quality:
- Ensure images are high resolution
- Check if images are rotated correctly
- Some handwritten text may not be recognized

## 🎓 OCR Tips for Best Results

1. **Image Quality:** Higher resolution = better OCR accuracy
2. **Language:** Tesseract defaults to English (eng)
3. **Preprocessing:** Clear, high-contrast images work best
4. **File Size:** Large files with many images will take longer
5. **Skip OCR for Speed:** Use `--no-ocr` for testing/development

## 📝 Categories

Choose appropriate category for your documents:
- `documentation` - User manuals, guides, SOPs
- `code` - Code examples, API docs, technical specs
- `proposal` - Business proposals, RFPs, solutions
- `support` - Support tickets, FAQs, troubleshooting
- `training` - Training materials, tutorials
- `maintenance` - Maintenance procedures, checklists
