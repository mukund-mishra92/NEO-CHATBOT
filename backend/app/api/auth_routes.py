"""
Authentication Routes for NEO Chatbot
Authentication with OTP for users and username/password for admin
"""

from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import logging
from app.services.otp_service import create_otp_for_email, verify_otp

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["Authentication"])

# Admin credentials
ADMIN_USERNAME = "root"
ADMIN_PASSWORD = "0063"

# Domain restriction
ALLOWED_DOMAIN = "@falconautotech.com"


class LoginRequest(BaseModel):
    role: str  # 'admin' or 'user'
    email: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None


class LoginResponse(BaseModel):
    success: bool
    name: Optional[str] = None
    email: Optional[str] = None
    role: Optional[str] = None
    message: Optional[str] = None


class OTPRequest(BaseModel):
    email: str


class OTPResponse(BaseModel):
    success: bool
    message: str
    requires_otp: Optional[bool] = None


class OTPVerifyRequest(BaseModel):
    email: str
    otp: str


class OTPVerifyResponse(BaseModel):
    success: bool
    message: str
    name: Optional[str] = None
    email: Optional[str] = None
    role: Optional[str] = None


def extract_name_from_email(email: str) -> str:
    """
    Extract first name from email address and capitalize it.
    
    Examples:
        arkajyoti.chakraborty@falconautotech.com -> Arkajyoti
        tuhi@falconautotech.com -> Tuhi
        sandeep.pathak@falconautotech.com -> Sandeep
    """
    local_part = email.split('@')[0]
    first_name = local_part.split('.')[0]
    return first_name.capitalize()




@router.post("/send-otp", response_model=OTPResponse)
async def send_otp(request: OTPRequest):
    """
    Send OTP to user's email
    Only sends OTP to @falconautotech.com email addresses
    """
    email = request.email.strip().lower()
    
    # Validate domain
    if not email.endswith(ALLOWED_DOMAIN):
        logger.warning(f"OTP request rejected for non-falcon domain: {email}")
        return OTPResponse(
            success=False,
            message=f"Only {ALLOWED_DOMAIN} email addresses are allowed."
        )
    
    # Generate and send OTP
    success, message, error = create_otp_for_email(email)
    
    if success:
        logger.info(f"OTP sent to {email}")
        return OTPResponse(
            success=True,
            message=message,
            requires_otp=True
        )
    else:
        logger.error(f"Failed to send OTP to {email}: {error}")
        return OTPResponse(
            success=False,
            message=error or "Failed to send OTP. Please try again."
        )


@router.post("/verify-otp", response_model=OTPVerifyResponse)
async def verify_otp_endpoint(request: OTPVerifyRequest):
    """
    Verify OTP and authenticate user
    """
    email = request.email.strip().lower()
    otp = request.otp.strip()
    
    # Validate domain again
    if not email.endswith(ALLOWED_DOMAIN):
        return OTPVerifyResponse(
            success=False,
            message=f"Only {ALLOWED_DOMAIN} email addresses are allowed."
        )
    
    # Verify OTP
    success, message = verify_otp(email, otp)
    
    if success:
        name = extract_name_from_email(email)
        logger.info(f"OTP verified successfully for {email}")
        return OTPVerifyResponse(
            success=True,
            message="Authentication successful",
            name=name,
            email=email,
            role="user"
        )
    else:
        logger.warning(f"OTP verification failed for {email}: {message}")
        return OTPVerifyResponse(
            success=False,
            message=message
        )


@router.post("/login", response_model=LoginResponse)
async def login(request: LoginRequest):
    """
    Handle login for admin role only
    User login now requires OTP verification via /send-otp and /verify-otp endpoints
    """
    
    if request.role == "admin":
        # Admin login with username/password
        if not request.username or not request.password:
            return LoginResponse(
                success=False,
                message="Username and password are required for admin login."
            )
        
        if request.username == ADMIN_USERNAME and request.password == ADMIN_PASSWORD:
            logger.info(f"Admin login successful")
            return LoginResponse(
                success=True,
                name="Admin",
                role="admin"
            )
        else:
            logger.warning(f"Failed admin login attempt for username: {request.username}")
            return LoginResponse(
                success=False,
                message="Invalid username or password."
            )
    
    else:
        return LoginResponse(
            success=False,
            message="Invalid role. User login requires OTP verification."
        )


@router.post("/validate")
async def validate_session():
    """Simple session validation endpoint"""
    return {"valid": True}
