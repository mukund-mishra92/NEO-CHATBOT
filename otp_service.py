import os
import time
import secrets
import hashlib
import smtplib
import ssl
import streamlit as st
from email.message import EmailMessage
from dotenv import load_dotenv

# Load .env once at startup
load_dotenv()

st.set_page_config(page_title="NEO OTP Login", page_icon="🔐", layout="centered")

OTP_TTL_SECONDS = 10 * 60
MAX_VERIFY_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 30

def env_required(key: str) -> str:
    v = os.getenv(key)
    if not v:
        st.error(f"Missing environment variable: {key}")
        st.stop()
    return v

def get_smtp_config():
    return {
        "host": env_required("SMTP_HOST"),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "username": env_required("SMTP_USERNAME"),
        "password": env_required("SMTP_PASSWORD"),
        "from_email": env_required("SMTP_FROM_EMAIL"),
        "from_name": os.getenv("SMTP_FROM_NAME", "NEO Chatbot"),
    }

def send_otp_email(to_email: str, otp: str):
    cfg = get_smtp_config()

    msg = EmailMessage()
    msg["Subject"] = "Your NEO OTP"
    msg["From"] = f'{cfg["from_name"]} <{cfg["from_email"]}>'
    msg["To"] = to_email
    msg.set_content(
        f"Your OTP for NEO login is: {otp}\n\n"
        f"This OTP is valid for {OTP_TTL_SECONDS // 60} minutes.\n"
        "If you did not request this, please ignore this email."
    )

    context = ssl.create_default_context()
    with smtplib.SMTP(cfg["host"], cfg["port"], timeout=20) as server:
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
        server.login(cfg["username"], cfg["password"])
        server.send_message(msg)

def hash_otp(otp: str, salt: str) -> str:
    return hashlib.sha256((salt + otp).encode("utf-8")).hexdigest()

st.title("NEO Email OTP Authentication")

if "otp_state" not in st.session_state:
    st.session_state.otp_state = {
        "email": None,
        "otp_hash": None,
        "salt": None,
        "issued_at": None,
        "attempts": 0,
        "last_sent_at": 0.0,
        "verified": False,
    }

state = st.session_state.otp_state
email = st.text_input("Email ID", value=state["email"] or "", placeholder="name@company.com")

c1, c2 = st.columns([1, 1])
send_clicked = c1.button("Send OTP", use_container_width=True)
reset_clicked = c2.button("Reset", use_container_width=True)

if reset_clicked:
    st.session_state.otp_state = {
        "email": None,
        "otp_hash": None,
        "salt": None,
        "issued_at": None,
        "attempts": 0,
        "last_sent_at": 0.0,
        "verified": False,
    }
    st.rerun()

if send_clicked:
    email = (email or "").strip()
    if not email or "@" not in email:
        st.error("Enter a valid email address.")
    else:
        now = time.time()
        if now - state["last_sent_at"] < RESEND_COOLDOWN_SECONDS:
            st.warning(f"Please wait {RESEND_COOLDOWN_SECONDS} seconds before resending.")
        else:
            otp = f"{secrets.randbelow(10**6):06d}"
            salt = secrets.token_hex(16)
            otp_hash = hash_otp(otp, salt)

            try:
                send_otp_email(email, otp)
            except Exception as e:
                st.error(f"Failed to send OTP. SMTP error: {e}")
            else:
                state["email"] = email
                state["salt"] = salt
                state["otp_hash"] = otp_hash
                state["issued_at"] = now
                state["attempts"] = 0
                state["last_sent_at"] = now
                state["verified"] = False
                st.success("OTP sent. Check inbox/spam.")

if state["otp_hash"] and state["email"]:
    st.divider()
    st.subheader("Verify OTP")

    otp_in = st.text_input("Enter OTP", max_chars=6, placeholder="6-digit OTP", type="password")
    verify_clicked = st.button("Verify", use_container_width=True)

    if verify_clicked:
        now = time.time()
        if state["verified"]:
            st.success("Already verified.")
        elif state["attempts"] >= MAX_VERIFY_ATTEMPTS:
            st.error("Too many failed attempts. Please resend OTP.")
        elif now - (state["issued_at"] or 0) > OTP_TTL_SECONDS:
            st.error("OTP expired. Please resend OTP.")
        else:
            state["attempts"] += 1
            otp_in = (otp_in or "").strip()

            if len(otp_in) != 6 or not otp_in.isdigit():
                st.error("Enter a valid 6-digit OTP.")
            else:
                if hash_otp(otp_in, state["salt"]) == state["otp_hash"]:
                    state["verified"] = True
                    st.success("Authentication successful ✅")
                else:
                    remaining = MAX_VERIFY_ATTEMPTS - state["attempts"]
                    st.error(f"Invalid OTP. Attempts left: {remaining}")

if state.get("verified"):
    st.info("Now you can unlock the NEO chatbot section (set a session flag / token here).")
