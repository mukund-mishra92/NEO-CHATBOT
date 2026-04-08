/**
 * chatWindow.js — Chat message area, streaming, typing indicator and scroll logic.
 */

import State from '../core/stateManager.js';
import { formatMessage } from '../services/responseParser.js';
import { $ } from '../utils/domUtils.js';
import { addResponseActions } from './messageBubble.js';

const STREAMING_CONFIG = { enabled: true, wordsPerSecond: 15, minDelay: 20, maxDelay: 60 };

/* ── Utilities ── */
function getChatMessages() {
    return document.getElementById('chatMessages');
}

export function isUserNearBottom(container) {
    if (!container) return true;
    const threshold = 150;
    return (container.scrollHeight - container.scrollTop - container.clientHeight) < threshold;
}

export function _showScrollBtn() {
    const btn = document.getElementById('scrollBottomBtn');
    if (btn) btn.classList.remove('scroll-btn-hidden');
}

export function _hideScrollBtn() {
    const btn = document.getElementById('scrollBottomBtn');
    if (btn) btn.classList.add('scroll-btn-hidden');
}

export function scrollChatToBottom() {
    const container = getChatMessages();
    if (!container) return;
    container.scrollTop = container.scrollHeight;
    _hideScrollBtn();
    State.set('_userNearBottom', true);
}

export function smartScroll(container) {
    if (!container) return;
    if (State.get('_userNearBottom') !== false) {
        container.scrollTop = container.scrollHeight;
        _hideScrollBtn();
    } else {
        _showScrollBtn();
    }
}

/* ── Typing indicator ── */
export function showTypingIndicator(chatbotType) {
    hideTypingIndicator();
    const container = getChatMessages();
    if (!container) return;

    const labelMap = {
        knowledge_base: 'NEO Knowledge Base',
        sql_assistant: 'NEO SQL Assistant',
        semi_auto_diagnostic: 'NEO Diagnostic',
        diagnostic: 'NEO Diagnostic',
    };
    const label = labelMap[chatbotType] || 'NEO AI';

    const indicator = document.createElement('div');
    indicator.className = 'message assistant';
    indicator.id = 'typingIndicator';
    indicator.innerHTML = `
        <div class="message-avatar" aria-label="NEO">N</div>
        <div class="message-content" style="display:flex;align-items:center;gap:8px;min-height:32px;">
            <div class="typing-indicator">
                <span class="typing-dot"></span>
                <span class="typing-dot"></span>
                <span class="typing-dot"></span>
            </div>
            <span style="font-size:0.8em;color:var(--text-muted);font-style:italic;">${label} is thinking…</span>
        </div>`;
    container.appendChild(indicator);
    smartScroll(container);
}

export function hideTypingIndicator() {
    const indicator = document.getElementById('typingIndicator');
    if (indicator) indicator.remove();
}

/* ── Streaming text ── */
async function streamText(contentEl, html, speed, renderToken) {
    const words = html.split(' ');
    const delay = Math.min(STREAMING_CONFIG.maxDelay, Math.max(STREAMING_CONFIG.minDelay, Math.round(1000 / speed)));
    const container = getChatMessages();
    let accumulated = '';

    for (const word of words) {
        if (!State.get('responseInProgress') || State.get('activeRenderToken') !== renderToken) break;
        accumulated += (accumulated ? ' ' : '') + word;
        contentEl.innerHTML = accumulated;
        smartScroll(container);
        await new Promise(r => setTimeout(r, delay));
    }
    if (State.get('activeRenderToken') === renderToken && !State.get('stopRequested')) {
        contentEl.innerHTML = html;
        smartScroll(container);
    }
}

async function streamNode(sourceNode, targetNode, speed, renderToken) {
    const clone = sourceNode.cloneNode(true);
    const children = Array.from(clone.childNodes);
    const delay = Math.min(STREAMING_CONFIG.maxDelay, Math.max(STREAMING_CONFIG.minDelay, Math.round(1000 / speed)));
    const container = getChatMessages();

    for (const child of children) {
        if (!State.get('responseInProgress') || State.get('activeRenderToken') !== renderToken) break;
        targetNode.appendChild(child.cloneNode(true));
        smartScroll(container);
        await new Promise(r => setTimeout(r, delay));
    }
}

/* ── Clean up stale SQL result artefacts ── */
export function cleanupSqlResultArtifacts(scopeEl) {
    if (!scopeEl) return;
    scopeEl.querySelectorAll('.sql-result-block, .sql-exec-block, .sql-run-block').forEach(el => el.remove());
    scopeEl.querySelectorAll('pre code').forEach(pre => {
        if (pre.textContent.match(/^\s*(SELECT|INSERT|UPDATE|DELETE|WITH)\b/i)) pre.closest('pre')?.remove();
    });
}

/* ── Clear chat area ── */
export function clearChat() {
    const container = getChatMessages();
    if (!container) return;
    container.innerHTML = '';
    const emptyState = document.getElementById('emptyState');
    if (emptyState) emptyState.style.display = 'flex';
    State.set('messageCount', 0);
}

/* ── Append a message ── */
export function appendMessage(type, content, data = {}, streaming = false, renderToken = null) {
    const container = getChatMessages();
    if (!container) return null;

    // Hide empty state
    const emptyState = document.getElementById('emptyState');
    if (emptyState) emptyState.style.display = 'none';

    const div = document.createElement('div');
    div.className = `message ${type}`;
    div.dataset.renderToken = renderToken || '';

    let msgHtml = '';
    if (type === 'user') {
        msgHtml = `
            <div class="message-content user-bubble">${content}</div>
            <div class="message-avatar user-avatar" aria-label="You">You</div>`;
    } else if (type === 'assistant' || type === 'system') {
        const formattedContent = formatMessage(content, data, type);
        msgHtml = `
            <div class="message-avatar" aria-label="NEO">N</div>
            <div class="message-content" id="msgcontent_${renderToken || Date.now()}">${formattedContent}</div>`;
    } else {
        msgHtml = `<div class="message-content">${content}</div>`;
    }

    div.innerHTML = msgHtml;
    container.appendChild(div);

    // Add response action buttons to assistant messages
    if (type === 'assistant' && data && Object.keys(data).length > 0) {
        const feedbackId = 'msg_' + (Date.now());
        div.dataset.feedbackId = feedbackId;
        div.dataset.messageContext = JSON.stringify({
            userMessage: data._userMessage || '',
            assistantResponse: content,
            chatbotType: data.chatbot_type || '',
        });
        addResponseActions(div, data, feedbackId);
    }

    // Stopped-response note
    if (type === 'assistant' && State.get('stopRequested')) {
        const note = document.createElement('div');
        note.className = 'generation-stopped-note';
        note.innerHTML = '<i class="fas fa-stop-circle"></i> Generation stopped by user';
        div.appendChild(note);
    }

    State.set('messageCount', (State.get('messageCount') || 0) + 1);
    smartScroll(container);

    return div;
}

/* ── Expand a past session ── */
export async function expandPastSession(pastSessionId) {
    const { getUserSessions, getSessionMessages } = await import('../api/chatApi.js');
    const { getEffectiveUserId } = await import('../utils/helpers.js');
    const userId = getEffectiveUserId();

    clearChat();
    State.set('sessionId', pastSessionId);
    const span = document.getElementById('currentSessionId');
    if (span) span.textContent = pastSessionId;

    try {
        const data = await getSessionMessages(userId, pastSessionId);
        const messages = data.messages || data || [];
        messages.forEach(msg => {
            const role    = msg.role === 'user' ? 'user' : 'assistant';
            const content = msg.content || msg.message || '';
            appendMessage(role, content, { chatbot_type: msg.metadata?.chatbot_type }, false, null);
        });
    } catch (err) {
        appendMessage('system', `<em>Could not load session history: ${err.message}</em>`, {}, false, null);
    }
}
