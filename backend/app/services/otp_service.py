"""
OTP Email Service for NEO Chatbot
Handles OTP generation, sending, and verification for email authentication
"""

import os
import time
import secrets
import hashlib
import smtplib
import ssl
from email.message import EmailMessage
from typing import Dict, Optional
from dotenv import load_dotenv
import logging

logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Configuration
OTP_TTL_SECONDS = 10 * 60  # 10 minutes
MAX_VERIFY_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 30

# In-memory OTP storage (consider using Redis for production)
otp_store: Dict[str, dict] = {}


def get_smtp_config() -> dict:
    """Get SMTP configuration from environment variables"""
    return {
        "host": os.getenv("SMTP_HOST"),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "username": os.getenv("SMTP_USERNAME"),
        "password": os.getenv("SMTP_PASSWORD"),
        "from_email": os.getenv("SMTP_FROM_EMAIL"),
        "from_name": os.getenv("SMTP_FROM_NAME", "NEO Chatbot"),
    }


def validate_smtp_config() -> tuple[bool, Optional[str]]:
    """Validate that all required SMTP configuration is present"""
    cfg = get_smtp_config()
    required_fields = ["host", "username", "password", "from_email"]
    
    for field in required_fields:
        if not cfg.get(field):
            return False, f"Missing SMTP configuration: {field.upper()}"
    
    return True, None


def send_otp_email(to_email: str, otp: str) -> tuple[bool, Optional[str]]:
    """
    Send OTP to the specified email address
    
    Args:
        to_email: Recipient email address
        otp: The OTP code to send
        
    Returns:
        Tuple of (success: bool, error_message: Optional[str])
    """
    try:
        cfg = get_smtp_config()

        msg = EmailMessage()
        msg["Subject"] = "Your NEO Login OTP"
        msg["From"] = f'{cfg["from_name"]} <{cfg["from_email"]}>'
        msg["To"] = to_email
        msg.set_content(
            f"Your OTP for NEO login is: {otp}\n\n"
            f"This OTP is valid for {OTP_TTL_SECONDS // 60} minutes.\n\n"
            "If you did not request this, please ignore this email.\n\n"
            "Best regards,\n"
            "NEO Chatbot Team"
        )

        context = ssl.create_default_context()
        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=20) as server:
            server.ehlo()
            server.starttls(context=context)
            server.ehlo()
            server.login(cfg["username"], cfg["password"])
            server.send_message(msg)
        
        logger.info(f"OTP email sent successfully to {to_email}")
        return True, None
        
    except Exception as e:
        error_msg = f"Failed to send OTP email: {str(e)}"
        logger.error(error_msg)
        return False, error_msg


def hash_otp(otp: str, salt: str) -> str:
    """Hash OTP with salt for secure storage"""
    return hashlib.sha256((salt + otp).encode("utf-8")).hexdigest()


def generate_otp() -> str:
    """Generate a 6-digit OTP"""
    return f"{secrets.randbelow(10**6):06d}"


def create_otp_for_email(email: str) -> tuple[bool, Optional[str], Optional[str]]:
    """
    Create and send OTP for the given email
    
    Args:
        email: Email address to send OTP to
        
    Returns:
        Tuple of (success: bool, message: Optional[str], error: Optional[str])
    """
    # Validate SMTP configuration first
    valid, error = validate_smtp_config()
    if not valid:
        return False, None, error
    
    email = email.lower().strip()
    
    # Check if OTP was recently sent
    if email in otp_store:
        last_sent = otp_store[email].get("last_sent_at", 0)
        if time.time() - last_sent < RESEND_COOLDOWN_SECONDS:
            remaining = int(RESEND_COOLDOWN_SECONDS - (time.time() - last_sent))
            return False, None, f"Please wait {remaining} seconds before requesting a new OTP."
    
    # Generate OTP
    otp = generate_otp()
    salt = secrets.token_hex(16)
    otp_hash = hash_otp(otp, salt)
    
    # Send OTP email
    success, error = send_otp_email(email, otp)
    if not success:
        return False, None, error
    
    # Store OTP data
    otp_store[email] = {
        "otp_hash": otp_hash,
        "salt": salt,
        "issued_at": time.time(),
        "last_sent_at": time.time(),
        "attempts": 0,
    }
    
    logger.info(f"OTP created for {email}")
    return True, "OTP sent successfully. Please check your email.", None


def verify_otp(email: str, otp_input: str) -> tuple[bool, Optional[str]]:
    """
    Verify the OTP for the given email
    
    Args:
        email: Email address
        otp_input: OTP entered by user
        
    Returns:
        Tuple of (success: bool, message: str)
    """
    email = email.lower().strip()
    otp_input = otp_input.strip()
    
    # Check if OTP exists for email
    if email not in otp_store:
        return False, "No OTP found. Please request a new OTP."
    
    otp_data = otp_store[email]
    
    # Check if too many attempts
    if otp_data["attempts"] >= MAX_VERIFY_ATTEMPTS:
        # Clean up
        del otp_store[email]
        return False, "Too many failed attempts. Please request a new OTP."
    
    # Check if OTP expired
    if time.time() - otp_data["issued_at"] > OTP_TTL_SECONDS:
        # Clean up
        del otp_store[email]
        return False, "OTP has expired. Please request a new OTP."
    
    # Validate OTP format
    if len(otp_input) != 6 or not otp_input.isdigit():
        otp_data["attempts"] += 1
        remaining = MAX_VERIFY_ATTEMPTS - otp_data["attempts"]
        return False, f"Invalid OTP format. Attempts remaining: {remaining}"
    
    # Verify OTP
    otp_data["attempts"] += 1
    
    if hash_otp(otp_input, otp_data["salt"]) == otp_data["otp_hash"]:
        # Success - clean up OTP data
        del otp_store[email]
        logger.info(f"OTP verified successfully for {email}")
        return True, "OTP verified successfully."
    else:
        remaining = MAX_VERIFY_ATTEMPTS - otp_data["attempts"]
        if remaining <= 0:
            del otp_store[email]
            return False, "Invalid OTP. Maximum attempts exceeded. Please request a new OTP."
        return False, f"Invalid OTP. Attempts remaining: {remaining}"


def cleanup_expired_otps():
    """Clean up expired OTPs from storage (call periodically)"""
    now = time.time()
    expired_emails = [
        email for email, data in otp_store.items()
        if now - data["issued_at"] > OTP_TTL_SECONDS
    ]
    
    for email in expired_emails:
        del otp_store[email]
    
    if expired_emails:
        logger.info(f"Cleaned up {len(expired_emails)} expired OTPs")
