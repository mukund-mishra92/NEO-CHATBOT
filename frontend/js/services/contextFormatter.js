/**
 * contextFormatter.js — Builds outgoing API payloads and regeneration prompts.
 */

/**
 * Build the payload for `chatApi.sendChat`.
 */
export function buildPayload(message, chatbotType, sessionId, userId, attachedDocumentText, attachedFileName) {
    const payload = {
        message: message.trim(),
        chatbot_type: chatbotType,
        session_id: sessionId || undefined,
        user_id: userId,
    };

    if (attachedDocumentText) {
        payload.context = `[Attached Document: ${attachedFileName || 'document'}]\n\n${attachedDocumentText}\n\n---\n\nUser question: ${message.trim()}`;
    }

    return payload;
}

/**
 * Returns true if a response looks like a limitation / "I cannot help" reply.
 */
export function looksLikeLimitationResponse(text) {
    if (!text) return false;
    return /\b(I cannot|I can't|I am not able|unable to|I'm not able|beyond my|do not have access|no data available|outside my|I don't have)\b/i.test(text);
}

/**
 * Normalize text for comparison (lowercase, collapse whitespace, strip punctuation).
 */
export function normalizeForComparison(text) {
    return (text || '').toLowerCase().replace(/[^a-z0-9\s]/g, '').replace(/\s+/g, ' ').trim();
}

/**
 * Build a regeneration prompt appended to the original user message.
 * @param {string}  userMessage       — original user question
 * @param {string}  previousResponse  — the response that was unsatisfactory
 * @param {boolean} stronger          — whether to request a markedly different response
 */
export function buildRegenerationPrompt(userMessage, previousResponse, stronger = false) {
    if (stronger) {
        return `${userMessage}\n\n[SYSTEM NOTE: The previous response was unsatisfactory. Please provide a completely different, more comprehensive answer with more detail and examples. Previous response summary: "${(previousResponse || '').substring(0, 200)}..."]`;
    }
    return `${userMessage}\n\n[SYSTEM NOTE: Please regenerate your response. Previous response: "${(previousResponse || '').substring(0, 200)}..."]`;
}
