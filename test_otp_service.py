"""
Quick Test Script for OTP Email Service
Run this to verify OTP functionality is working correctly
"""

import sys
import os
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).parent / 'backend'
sys.path.insert(0, str(backend_dir))

from dotenv import load_dotenv

# Load environment variables
env_path = backend_dir / '.env'
load_dotenv(env_path)

from app.services.otp_service import (
    validate_smtp_config,
    create_otp_for_email,
    verify_otp,
    otp_store,
    ALLOWED_DOMAIN
)


def print_header(text):
    print(f"\n{'=' * 60}")
    print(f"  {text}")
    print('=' * 60)


def test_smtp_config():
    print_header("Testing SMTP Configuration")
    valid, error = validate_smtp_config()
    
    if valid:
        print("✅ SMTP configuration is valid")
        return True
    else:
        print(f"❌ SMTP configuration error: {error}")
        return False


def test_domain_validation():
    print_header("Testing Domain Validation")
    
    test_cases = [
        ("test@falconautotech.com", True),
        ("user.name@falconautotech.com", True),
        ("test@gmail.com", False),
        ("test@yahoo.com", False),
        ("noatsign.com", False),
    ]
    
    for email, should_pass in test_cases:
        is_valid = email.lower().strip().endswith(ALLOWED_DOMAIN)
        status = "✅" if is_valid == should_pass else "❌"
        print(f"{status} {email} - Expected: {should_pass}, Got: {is_valid}")


def test_otp_generation():
    print_header("Testing OTP Generation & Sending")
    
    test_email = input("\nEnter a test @falconautotech.com email to receive OTP: ").strip()
    
    if not test_email.endswith("@falconautotech.com"):
        print("❌ Invalid domain. Must end with @falconautotech.com")
        return None
    
    print(f"\n📧 Sending OTP to {test_email}...")
    success, message, error = create_otp_for_email(test_email)
    
    if success:
        print(f"✅ {message}")
        print("📬 Check your email inbox (and spam folder)")
        return test_email
    else:
        print(f"❌ Failed: {error}")
        return None


def test_otp_verification(email):
    if not email:
        print("\n⚠️  Skipping OTP verification (no email)")
        return
    
    print_header("Testing OTP Verification")
    print(f"Email: {email}")
    print(f"OTP in store: {'Yes' if email in otp_store else 'No'}")
    
    if email in otp_store:
        print(f"Attempts used: {otp_store[email]['attempts']}/5")
    
    otp_input = input("\nEnter the OTP you received: ").strip()
    
    success, message = verify_otp(email, otp_input)
    
    if success:
        print(f"✅ {message}")
        print("🎉 Authentication successful!")
    else:
        print(f"❌ {message}")


def test_rate_limiting(email):
    if not email:
        print("\n⚠️  Skipping rate limit test (no email)")
        return
    
    print_header("Testing Rate Limiting")
    print("Attempting to send OTP again immediately (should be rate limited)...\n")
    
    success, message, error = create_otp_for_email(email)
    
    if not success and "wait" in (error or "").lower():
        print(f"✅ Rate limiting working: {error}")
    else:
        print(f"⚠️  Rate limiting may not be working as expected")


def main():
    print("\n" + "=" * 60)
    print("  NEO CHATBOT - OTP SERVICE TEST")
    print("=" * 60)
    
    # Test 1: SMTP Configuration
    if not test_smtp_config():
        print("\n❌ Cannot proceed without valid SMTP configuration")
        print("Please check your backend/.env file")
        return
    
    # Test 2: Domain Validation
    test_domain_validation()
    
    # Test 3: OTP Generation
    test_email = test_otp_generation()
    
    if test_email:
        # Test 4: Rate Limiting
        test_rate_limiting(test_email)
        
        # Test 5: OTP Verification
        test_otp_verification(test_email)
    
    print_header("Test Complete")
    print("\n✅ All tests completed!")
    print("\nNOTE: For production, consider:")
    print("  - Using Redis for OTP storage")
    print("  - Implementing IP-based rate limiting")
    print("  - Adding CAPTCHA protection")
    print("  - Enabling HTTPS")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
    except Exception as e:
        print(f"\n❌ Error during test: {e}")
        import traceback
        traceback.print_exc()
