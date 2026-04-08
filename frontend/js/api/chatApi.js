/**
 * chatApi.js — All fetch calls to the NEO backend.
 *
 * Every function returns parsed JSON or throws on HTTP/network error.
 * No DOM manipulation here — that belongs in services/components.
 */

import { API_BASE } from '../utils/constants.js';
import { getEffectiveUserId } from '../utils/helpers.js';

/* ── Main chat ── */

/**
 * Send a user message to the chatbot API.
 * @param {object} opts
 * @param {string} opts.message
 * @param {string} opts.chatbotType
 * @param {string|null} opts.sessionId
 * @param {AbortSignal} [opts.signal]
 * @param {object|null} [opts.context]   — attached document context
 * @returns {Promise<object>}            — raw API response JSON
 */
export async function sendChatMessage({ message, chatbotType, sessionId, signal, context = null }) {
    const payload = {
        message,
        chatbot_type: chatbotType,
        session_id: sessionId,
        user_id: getEffectiveUserId(),
        conversation_history: [],
    };

    if (context) {
        payload.context = context;
    }

    const resp = await fetch(`${API_BASE}/api/chatbot/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal,
    });

    if (!resp.ok) {
        const errorText = await resp.text();
        throw new Error(`Server returned ${resp.status}: ${errorText}`);
    }

    return resp.json();
}

/* ── Session management ── */

export async function createSession() {
    const resp = await fetch(`${API_BASE}/api/chatbot/session/new`, { method: 'POST' });
    if (!resp.ok) throw new Error('Failed to create session');
    return resp.json();
}

export async function fetchSessionHistory(sessionId) {
    const resp = await fetch(`${API_BASE}/api/chatbot/session/${sessionId}/history`);
    if (!resp.ok) throw new Error('Failed to fetch history');
    return resp.json();
}

export async function deleteSessionById(sessionId) {
    const resp = await fetch(`${API_BASE}/api/chatbot/session/${encodeURIComponent(sessionId)}/delete`, {
        method: 'DELETE',
    });
    if (!resp.ok) throw new Error('Delete failed');
    return resp.json();
}

export async function renameSessionById(sessionId, newName) {
    const userId = getEffectiveUserId();
    const resp = await fetch(
        `${API_BASE}/api/chatbot/user/${encodeURIComponent(userId)}/session/${encodeURIComponent(sessionId)}/rename`,
        {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ session_name: newName }),
        }
    );
    return resp.ok;
}

/* ── User chat history (sidebar) ── */

export async function fetchUserSessions(limit = 30) {
    const userId = getEffectiveUserId();
    const resp = await fetch(`${API_BASE}/api/chatbot/user/${encodeURIComponent(userId)}/sessions?limit=${limit}`);
    if (!resp.ok) throw new Error('Failed to load history');
    return resp.json();
}

export async function fetchSessionMessages(sessionId) {
    const userId = getEffectiveUserId();
    const url = `${API_BASE}/api/chatbot/user/${encodeURIComponent(userId)}/session/${encodeURIComponent(sessionId)}/messages`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error('Failed to load messages');
    return resp.json();
}

/* ── Document extraction ── */

export async function extractDocumentText(file) {
    const formData = new FormData();
    formData.append('file', file);

    const resp = await fetch(`${API_BASE}/api/chatbot/extract-document-text`, {
        method: 'POST',
        body: formData,
    });

    if (!resp.ok) {
        const err = await resp.json();
        throw new Error(err.detail || 'Upload failed');
    }

    return resp.json();
}

/* ── SQL execution ── */

export async function executeSql(sqlQuery) {
    const resp = await fetch(`${API_BASE}/api/sql/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql_query: sqlQuery }),
    });
    if (!resp.ok) throw new Error(`SQL execute failed: ${resp.status}`);
    return resp.json();
}

/* ── Feedback ── */

export async function submitFeedback({ sessionId, chatbotType, feedbackType, question, response }) {
    const resp = await fetch(`${API_BASE}/api/chat/feedback`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            session_id: sessionId,
            chatbot_type: chatbotType,
            user_id: getEffectiveUserId(),
            feedback_type: feedbackType,
            question,
            response,
        }),
    });
    return resp.json();
}

/* ── SOP Diagnostic workflow ── */

export async function sopStart(problemDescription, existingSessionId = null) {
    const body = { problem_description: problemDescription };
    if (existingSessionId) body.session_id = existingSessionId;

    const resp = await fetch(`${API_BASE}/api/diagnostic-support/sop/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error('SOP start failed');
    return resp.json();
}

export async function sopSelectProblem(sopSessionId, sNo) {
    const resp = await fetch(`${API_BASE}/api/diagnostic-support/sop/select`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sopSessionId, s_no: sNo }),
    });
    if (!resp.ok) throw new Error('SOP select failed');
    return resp.json();
}

export async function sopSubmitStepInput(sopSessionId, userInput) {
    const resp = await fetch(`${API_BASE}/api/diagnostic-support/sop/step-input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sopSessionId, user_input: userInput }),
    });
    if (!resp.ok) throw new Error('SOP step-input failed');
    return resp.json();
}

export async function sopMarkResolved(sopSessionId) {
    const resp = await fetch(`${API_BASE}/api/diagnostic-support/sop/resolved`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sopSessionId }),
    });
    if (!resp.ok) throw new Error('SOP resolved failed');
    return resp.json();
}

export async function sopMarkNotResolved(sopSessionId) {
    const resp = await fetch(`${API_BASE}/api/diagnostic-support/sop/not-resolved`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sopSessionId }),
    });
    if (!resp.ok) throw new Error('SOP not-resolved failed');
    return resp.json();
}

/* ── System info (legacy tools) ── */

export async function fetchSystemHealth() {
    const resp = await fetch(`${API_BASE}/api/chatbot/system-health`);
    if (!resp.ok) throw new Error('Health check failed');
    return resp.json();
}

export async function fetchStatistics() {
    const resp = await fetch(`${API_BASE}/api/chatbot/statistics`);
    if (!resp.ok) throw new Error('Statistics fetch failed');
    return resp.json();
}
