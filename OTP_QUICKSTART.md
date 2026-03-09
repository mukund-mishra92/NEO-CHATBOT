# Quick Start: OTP Login Integration

## What's New? 🎉

User login now requires **OTP (One-Time Password) verification** via email for enhanced security!

- ✅ Domain validation: Only `@falconautotech.com` emails allowed
- ✅ Secure 6-digit OTP sent to email
- ✅ OTP expires after 10 minutes
- ✅ Rate limiting to prevent abuse
- ✅ Maximum 5 verification attempts per OTP

---

## Quick Test

### 1. Start the Backend Server

```powershell
cd backend
python -m uvicorn app.main:app --reload
```

### 2. Test OTP Service (Optional)

```powershell
python test_otp_service.py
```

This will:
- Verify SMTP configuration
- Test domain validation
- Send a real OTP to your email
- Test OTP verification

### 3. Open Login Page

Navigate to: `http://localhost:8000/login`

### 4. Login Flow

**Step 1: Enter Email**
```
1. Click "User" tab (default)
2. Enter: yourname@falconautotech.com
3. Click "Send OTP"
```

**Step 2: Verify OTP**
```
1. Check your email inbox (and spam folder)
2. Find email from "NEO Chatbot"
3. Enter the 6-digit OTP code
4. Click "Verify & Sign In"
```

**Success!** You'll be redirected to the chatbot.

---

## Features

### ✅ Domain Validation
- Only emails ending with `@falconautotech.com` are accepted
- Validation happens before OTP is sent
- Clear error message for invalid domains

### ⏱️ OTP Expiration
- OTPs are valid for **10 minutes**
- Expired OTPs are automatically cleaned up
- User sees clear "expired" message

### 🔒 Security Features
- OTPs are hashed before storage (SHA-256)
- **Rate limiting**: 30-second cooldown between OTP requests
- **Attempt limiting**: Maximum 5 verification attempts
- **No plain text storage**: OTPs never stored unencrypted

### 🔄 Resend OTP
- "Resend OTP" button appears after first OTP sent
- Respects 30-second cooldown
- Previous OTP is invalidated when new one sent

### 📊 User Feedback
- Loading spinners during API calls
- Clear success/error messages
- Remaining attempts display
- Cooldown timer messages

---

## Admin Login

Admin login remains **unchanged**:
- Username: `root`
- Password: `0063`
- No OTP required

---

## Configuration

All settings in `backend/.env`:

```env
# SMTP Configuration (already configured)
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USERNAME=a29a46001@smtp-brevo.com
SMTP_PASSWORD=DZwOPCRr3NfIsEtF
SMTP_FROM_EMAIL=arkajyotichakraborty.it.2019@gmail.com
SMTP_FROM_NAME=NEO Chatbot
```

---

## Troubleshooting

### Problem: OTP Email Not Received
**Solutions:**
1. Check spam/junk folder
2. Wait 1-2 minutes (email may be delayed)
3. Click "Resend OTP" (wait 30 seconds first)
4. Verify SMTP config in `backend/.env`

### Problem: "Please wait X seconds before requesting a new OTP"
**Solution:**
- This is rate limiting working correctly
- Wait the specified time before trying again

### Problem: "Too many failed attempts"
**Solution:**
- Click "Resend OTP" to get a new code
- You'll get 5 fresh attempts with the new OTP

### Problem: "OTP has expired"
**Solution:**
- Click "Resend OTP" to get a new code
- OTPs expire after 10 minutes

### Problem: "Only @falconautotech.com email addresses are allowed"
**Solution:**
- Use your Falcon Autotech company email
- Personal emails (gmail, yahoo, etc.) are not allowed

---

## API Endpoints

### Send OTP
```http
POST /api/auth/send-otp
Content-Type: application/json

{
  "email": "user@falconautotech.com"
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP sent successfully. Please check your email.",
  "requires_otp": true
}
```

### Verify OTP
```http
POST /api/auth/verify-otp
Content-Type: application/json

{
  "email": "user@falconautotech.com",
  "otp": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Authentication successful",
  "name": "Arkajyoti",
  "email": "arkajyoti.chakraborty@falconautotech.com",
  "role": "user"
}
```

---

## Testing Checklist

- [ ] SMTP configuration is valid (`python test_otp_service.py`)
- [ ] Backend server is running
- [ ] Can access login page
- [ ] Invalid domain is rejected (e.g., @gmail.com)
- [ ] Valid domain sends OTP
- [ ] OTP email is received
- [ ] Correct OTP verifies successfully
- [ ] Incorrect OTP shows error with remaining attempts
- [ ] Resend OTP works (after 30s cooldown)
- [ ] OTP expires after 10 minutes
- [ ] Admin login still works

---

## Files Modified/Created

### Created:
- `backend/app/services/otp_service.py` - OTP service logic
- `docs/OTP_LOGIN_INTEGRATION.md` - Detailed documentation
- `test_otp_service.py` - Test script

### Modified:
- `backend/app/api/auth_routes.py` - Added OTP endpoints
- `frontend/login.html` - Two-step OTP authentication UI

---

## Need Help?

1. Check backend logs for errors
2. Run test script: `python test_otp_service.py`
3. Verify SMTP configuration in `backend/.env`
4. See detailed docs: `docs/OTP_LOGIN_INTEGRATION.md`

---

**Ready to test?** Run the backend and visit http://localhost:8000/login 🚀
