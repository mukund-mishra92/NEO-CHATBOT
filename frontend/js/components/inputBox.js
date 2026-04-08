/**
 * inputBox.js — Input area lifecycle: send/stop toggle, file attach, auto-resize.
 */

import State from '../core/stateManager.js';
import EventBus from '../core/eventBus.js';
import { showToast } from '../utils/helpers.js';
import { extractDocumentText } from '../api/chatApi.js';

/* ── Send / Stop button mode ── */
export function setSendButtonMode(isStopMode) {
    const btn  = document.getElementById('sendBtn');
    const icon = btn?.querySelector('i');
    if (!btn) return;

    if (isStopMode) {
        btn.classList.add('stop-mode');
        btn.title = 'Stop generating';
        if (icon) { icon.className = 'fas fa-stop'; }
    } else {
        btn.classList.remove('stop-mode');
        btn.title = 'Send message (Enter)';
        if (icon) { icon.className = 'fas fa-paper-plane'; }
    }
}

/* ── Response lifecycle ── */
export function startResponseLifecycle() {
    State.set('responseInProgress', true);
    State.set('stopRequested', false);
    setSendButtonMode(true);
    const input = document.getElementById('chatInput');
    if (input) input.disabled = true;
}

export function endResponseLifecycle(runId) {
    // Only clear if this is still the active run
    if (runId !== undefined && State.get('activeResponseRunId') !== runId) return;
    State.set('responseInProgress', false);
    State.set('activeResponseAbortController', null);
    State.set('activeRenderToken', null);
    setSendButtonMode(false);
    const input = document.getElementById('chatInput');
    if (input) { input.disabled = false; input.focus(); }
}

export function stopCurrentResponse() {
    State.set('stopRequested', true);
    const ctrl = State.get('activeResponseAbortController');
    if (ctrl) ctrl.abort();
    endResponseLifecycle();
}

/* ── Handle send-or-stop button ── */
export function handleSendOrStop() {
    if (State.get('responseInProgress')) {
        stopCurrentResponse();
    } else {
        EventBus.emit('send:message');
    }
}

/* ── Keyboard handler for the textarea ── */
export function handleKeyPress(event) {
    if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        handleSendOrStop();
    }
}

/* ── Auto-resize textarea ── */
export function autoResize(el) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 160) + 'px';
}

/* ── File attachment ── */
export async function handleChatFileAttach(event) {
    const file = event?.target?.files?.[0];
    event.target.value = '';  // reset so same file can be selected again
    if (!file) return;

    const banner = document.getElementById('attachedFileBanner');
    const nameEl = document.getElementById('attachedFileName');
    if (banner) banner.style.display = 'flex';
    if (nameEl) nameEl.textContent = '⏳ Extracting text…';

    try {
        const data = await extractDocumentText(file);
        State.set('attachedDocumentText', data.text || data.extracted_text || '');
        State.set('attachedFileName', file.name);
        if (nameEl) nameEl.textContent = file.name;
        showToast(`Attached: ${file.name}`);
    } catch (err) {
        State.set('attachedDocumentText', null);
        State.set('attachedFileName', null);
        if (banner) banner.style.display = 'none';
        showToast('Could not extract text from file.');
        console.error('File attach error:', err);
    }
}

export function removeAttachedFile() {
    State.set('attachedDocumentText', null);
    State.set('attachedFileName', null);
    const banner = document.getElementById('attachedFileBanner');
    if (banner) banner.style.display = 'none';
}
