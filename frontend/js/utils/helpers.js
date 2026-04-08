/**
 * helpers.js — Auth helpers, session utils, clipboard, toast
 */

/* ── Session / Auth ── */

export function getNeoSession() {
    try {
        const raw = localStorage.getItem('neo_session');
        return raw ? JSON.parse(raw) : null;
    } catch {
        return null;
    }
}

export function getEffectiveUserId() {
    const session = getNeoSession();
    if (session?.user_id) return session.user_id;

    // Guest: generate a stable per-browser ID
    let guestId = localStorage.getItem('neo_guest_id');
    if (!guestId) {
        guestId = 'guest_' + Math.random().toString(36).substr(2, 9);
        localStorage.setItem('neo_guest_id', guestId);
    }
    return guestId;
}

export function getGreeting() {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
}

/**
 * Enforce authentication: redirect to login if no session.
 * Returns the session object (or null for guests).
 */
export function enforceAuth() {
    const session = getNeoSession();
    if (!session) {
        window.location.href = '/login.html';
        return null;
    }
    return session;
}

/* ── DOM / string utils ── */

export function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
}

/* ── Clipboard ── */

export function fallbackCopyToClipboard(text) {
    try {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.setAttribute('readonly', '');
        ta.style.position = 'fixed';
        ta.style.top = '-9999px';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        const ok = document.execCommand('copy');
        document.body.removeChild(ta);
        return ok;
    } catch {
        return false;
    }
}

export async function copyText(text) {
    if (!text) return false;

    if (navigator.clipboard && window.isSecureContext) {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch { /* fall through */ }
    }

    return fallbackCopyToClipboard(text);
}

/* ── Toast notification ── */

export function showToast(message) {
    const toast = document.createElement('div');
    toast.style.cssText = `
        position:fixed; top:20px; right:20px;
        background:#333; color:white;
        padding:15px 20px; border-radius:8px;
        box-shadow:0 4px 6px rgba(0,0,0,0.3);
        z-index:10000; animation:toastSlideIn 0.3s ease;
        font-family:inherit; font-size:14px;
    `;
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => {
        toast.style.animation = 'toastSlideOut 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

/* ── SQL helpers ── */

export function extractTablesFromSQL(sql) {
    if (!sql) return [];
    const tables = [];

    const fromMatches = sql.match(/FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi);
    if (fromMatches) tables.push(...fromMatches.map(m => m.replace(/FROM\s+/i, '').trim()));

    const joinMatches = sql.match(/JOIN\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi);
    if (joinMatches) tables.push(...joinMatches.map(m => m.replace(/JOIN\s+/i, '').trim()));

    return [...new Set(tables)];
}

export function normalizeForComparison(text) {
    return (text || '').replace(/\s+/g, ' ').trim().toLowerCase();
}

export function looksLikeLimitationResponse(text) {
    const t = normalizeForComparison(text);
    if (!t) return true;

    const limitationPhrases = [
        'limitations of my response',
        "i don't have the capability",
        'i do not have the capability',
        'based on existing documentation',
        'i can suggest checking the user manual',
        'could you please let me know what specific aspects',
        'if you have any specific questions',
    ];

    return limitationPhrases.some(p => t.includes(p));
}

export function buildRegenerationPrompt(userMessage, previousResponse, stronger = false) {
    const baseInstruction = stronger
        ? 'Please provide a significantly more detailed and practical explanation with architecture flow, key modules, and a concrete example scenario. Keep it factual, structured, and directly answer the question.'
        : 'Please answer this in more depth with clear step-by-step explanation, important components, and practical examples. Keep it concise but informative.';
    return `${userMessage}\n\n${baseInstruction}`;
}
