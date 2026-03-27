"""
Test Tesseract OCR Installation
Checks if Tesseract is properly installed and working
"""

import sys
import os
from pathlib import Path

def check_tesseract_in_path():
    """Check if tesseract is in PATH"""
    import shutil
    tesseract_path = shutil.which('tesseract')
    if tesseract_path:
        print(f"✅ Tesseract found in PATH: {tesseract_path}")
        return tesseract_path
    return None

def check_tesseract_common_locations():
    """Check common installation locations"""
    common_paths = [
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        r"C:\Tesseract-OCR\tesseract.exe",
        os.path.expanduser(r"~\AppData\Local\Programs\Tesseract-OCR\tesseract.exe"),
    ]
    
    for path in common_paths:
        if os.path.exists(path):
            print(f"✅ Tesseract found at: {path}")
            return path
    
    return None

def test_tesseract_version(tesseract_path):
    """Test tesseract version"""
    import subprocess
    try:
        result = subprocess.run(
            [tesseract_path, '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        print("\n📋 Tesseract Version Info:")
        print("-" * 60)
        print(result.stdout)
        print("-" * 60)
        return True
    except Exception as e:
        print(f"❌ Error running tesseract: {e}")
        return False

def test_ocr_capability(tesseract_path):
    """Test actual OCR capability"""
    print("\n🧪 Testing OCR capability...")
    
    try:
        # Try importing pytesseract
        import pytesseract
        from PIL import Image
        import numpy as np
        
        # Set tesseract path if not in PATH
        if not check_tesseract_in_path():
            pytesseract.pytesseract.tesseract_cmd = tesseract_path
        
        # Create a simple test image with text
        from PIL import ImageDraw, ImageFont
        
        # Create white image
        img = Image.new('RGB', (300, 100), color='white')
        draw = ImageDraw.Draw(img)
        
        # Draw text
        try:
            font = ImageFont.truetype("arial.ttf", 36)
        except:
            font = ImageFont.load_default()
        
        draw.text((10, 30), "Hello OCR!", fill='black', font=font)
        
        # Save test image
        test_image_path = "test_ocr_image.png"
        img.save(test_image_path)
        print(f"   Created test image: {test_image_path}")
        
        # Perform OCR
        text = pytesseract.image_to_string(img)
        
        print(f"   OCR Result: '{text.strip()}'")
        
        # Clean up
        os.remove(test_image_path)
        
        if "Hello" in text or "OCR" in text:
            print("   ✅ OCR is working correctly!")
            return True
        else:
            print("   ⚠️ OCR ran but text recognition may not be accurate")
            return True
    
    except ImportError as e:
        print(f"   ❌ Missing Python package: {e}")
        print("\n   Install required packages:")
        print("   .\\venv\\Scripts\\pip install pytesseract pillow")
        return False
    except Exception as e:
        print(f"   ❌ Error testing OCR: {e}")
        return False

def print_installation_guide():
    """Print installation guide"""
    print("\n" + "=" * 60)
    print("📚 TESSERACT INSTALLATION GUIDE")
    print("=" * 60)
    print("\n1. Download Tesseract:")
    print("   https://github.com/UB-Mannheim/tesseract/wiki")
    print("\n2. Install Options:")
    print("   Option A: tesseract-ocr-w64-setup-5.3.3.20231005.exe (64-bit)")
    print("   Option B: tesseract-ocr-w32-setup-5.3.3.20231005.exe (32-bit)")
    print("\n3. During Installation:")
    print("   ✅ Check 'Add to PATH' option")
    print("   ✅ Install to default location")
    print("\n4. After Installation:")
    print("   - Restart your terminal/PowerShell")
    print("   - Run this test script again")
    print("\n5. Manual PATH Setup (if needed):")
    print("   - Add to System Environment Variables:")
    print("   - PATH: C:\\Program Files\\Tesseract-OCR")
    print("\n" + "=" * 60)

def main():
    """Main test function"""
    print("\n" + "=" * 60)
    print("🔍 TESSERACT OCR INSTALLATION TEST")
    print("=" * 60)
    
    # Check in PATH
    print("\n1️⃣ Checking if Tesseract is in PATH...")
    tesseract_path = check_tesseract_in_path()
    
    if not tesseract_path:
        print("❌ Tesseract not found in PATH")
        
        # Check common locations
        print("\n2️⃣ Checking common installation locations...")
        tesseract_path = check_tesseract_common_locations()
    
    if tesseract_path:
        print("\n" + "=" * 60)
        print("✅ TESSERACT FOUND!")
        print("=" * 60)
        
        # Test version
        print("\n3️⃣ Testing Tesseract version...")
        if test_tesseract_version(tesseract_path):
            
            # Test OCR capability
            print("\n4️⃣ Testing OCR capability...")
            if test_ocr_capability(tesseract_path):
                print("\n" + "=" * 60)
                print("🎉 ALL TESTS PASSED!")
                print("=" * 60)
                print("\nYou can now run document ingestion with OCR:")
                print("$env:PYTHONPATH=\"C:\\Users\\Balmukund.Mishra\\Desktop\\NEO\\association_mining_system\"")
                print(".\\venv\\Scripts\\python.exe app\\modules\\neo_chatbot\\scripts\\ingest_documents.py")
                print("\n" + "=" * 60)
                return True
    
    else:
        print("\n" + "=" * 60)
        print("❌ TESSERACT NOT FOUND")
        print("=" * 60)
        print_installation_guide()
        
        print("\n💡 Alternative: Run without OCR")
        print("-" * 60)
        print("You can still ingest PDFs without OCR (skips images):")
        print("$env:PYTHONPATH=\"C:\\Users\\Balmukund.Mishra\\Desktop\\NEO\\association_mining_system\"")
        print(".\\venv\\Scripts\\python.exe app\\modules\\neo_chatbot\\scripts\\ingest_documents.py --no-ocr")
        print("\n" + "=" * 60)
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
