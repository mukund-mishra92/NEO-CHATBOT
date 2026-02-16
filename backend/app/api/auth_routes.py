"""
Authentication Routes for NEO Chatbot
Simple authentication for admin and user roles
"""

from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["Authentication"])

# Admin credentials
ADMIN_USERNAME = "root"
ADMIN_PASSWORD = "0063"


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


@router.post("/login", response_model=LoginResponse)
async def login(request: LoginRequest):
    """Handle login for both admin and user roles"""
    
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
    
    elif request.role == "user":
        # User login with @falconautotech.com email only
        if not request.email:
            return LoginResponse(
                success=False,
                message="Email address is required."
            )
        
        email = request.email.strip().lower()
        
        if not email.endswith("@falconautotech.com"):
            return LoginResponse(
                success=False,
                message="Only @falconautotech.com email addresses are allowed."
            )
        
        name = extract_name_from_email(email)
        logger.info(f"User login successful: {name} ({email})")
        
        return LoginResponse(
            success=True,
            name=name,
            email=email,
            role="user"
        )
    
    else:
        return LoginResponse(
            success=False,
            message="Invalid role specified."
        )


@router.post("/validate")
async def validate_session():
    """Simple session validation endpoint"""
    return {"valid": True}
