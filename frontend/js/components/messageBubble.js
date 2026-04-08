/**
 * messageBubble.js — Response action buttons (copy, feedback, share, regen).
 */

import { copyText } from '../utils/helpers.js';
import { submitFeedback, submitRLHFFeedback } from '../api/chatApi.js';
import { buildRegenerationPrompt } from '../services/contextFormatter.js';

/**
 * Retrieve the stored context for a message bubble by feedbackId.
 * Context is embedded as data-message-context JSON on the bubble element.
 */
export function getResponseActionContext(feedbackId) {
    const el = document.querySelector(`[data-feedback-id="${feedbackId}"]`);
    if (!el) return {};
    try { return JSON.parse(el.dataset.messageContext || '{}'); } catch { return {}; }
}

export function copyResponseToClipboard(feedbackId) {
    const el = document.querySelector(`[data-feedback-id="${feedbackId}"] .message-content`);
    if (!el) return;
    copyText(el.innerText || el.textContent);
}

export async function submitResponseFeedback(feedbackId, feedbackType) {
    const ctx = getResponseActionContext(feedbackId);
    const icon = document.querySelector(`[data-feedback-id="${feedbackId}"] .action-${feedbackType}`);
    if (icon) {
        icon.classList.add('active');
        icon.style.pointerEvents = 'none';
    }
    try {
        await submitFeedback({
            feedback_type: feedbackType,
            user_message: ctx.userMessage || '',
            assistant_response: ctx.assistantResponse || '',
            chatbot_type: ctx.chatbotType || '',
        });
    } catch (e) {
        console.warn('Feedback submit failed:', e);
    }
}

export function shareResponse(feedbackId) {
    const ctx = getResponseActionContext(feedbackId);
    const text = ctx.assistantResponse || '';
    if (navigator.share) {
        navigator.share({ title: 'NEO Response', text }).catch(() => copyText(text));
    } else {
        copyText(text);
    }
}

export async function regenerateResponse(feedbackId) {
    const ctx = getResponseActionContext(feedbackId);
    if (!ctx.userMessage) return;
    const { showToast } = await import('../utils/helpers.js');
    showToast('Regenerating response…');
    // Import sendMessage from app.js dynamically to avoid circular deps
    const app = await import('../app.js');
    if (app.sendMessageText) {
        app.sendMessageText(buildRegenerationPrompt(ctx.userMessage, ctx.assistantResponse, true));
    }
}

/**
 * Append action icons (copy, like, dislike, share, regenerate) to a message bubble.
 */
export function addResponseActions(messageDiv, data, feedbackId) {
    const container = document.createElement('div');
    container.className = 'response-actions';
    container.innerHTML = `
        <button class="response-action-icon action-copy" title="Copy" onclick="copyResponseToClipboard('${feedbackId}')">
            <i class="fas fa-copy"></i>
        </button>
        <button class="response-action-icon action-thumbs_up" title="Helpful" onclick="submitResponseFeedback('${feedbackId}','thumbs_up')">
            <i class="fas fa-thumbs-up"></i>
        </button>
        <button class="response-action-icon action-thumbs_down" title="Not helpful" onclick="submitResponseFeedback('${feedbackId}','thumbs_down')">
            <i class="fas fa-thumbs-down"></i>
        </button>
        <button class="response-action-icon action-share" title="Share" onclick="shareResponse('${feedbackId}')">
            <i class="fas fa-share"></i>
        </button>
        <button class="response-action-icon action-regen" title="Regenerate" onclick="regenerateResponse('${feedbackId}')">
            <i class="fas fa-redo"></i>
        </button>`;
    messageDiv.appendChild(container);
}
