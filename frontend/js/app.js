/**
 * app.js — Main application orchestrator.
 * Bootstraps all modules, wires events and exposes window globals
 * needed by dynamically-generated HTML (onclick attributes).
 */

/* ── Core ── */
import State from './core/stateManager.js';
import EventBus from './core/eventBus.js';

/* ── Utils ── */
import { enforceAuth, getEffectiveUserId, showToast, copyText } from './utils/helpers.js';
import { CHATBOT_TYPES } from './utils/constants.js';

/* ── API ── */
import * as chatApi from './api/chatApi.js';

/* ── Services ── */
import { buildPayload, buildRegenerationPrompt } from './services/contextFormatter.js';

/* ── Components ── */
import {
    appendMessage, showTypingIndicator, hideTypingIndicator,
    smartScroll, scrollChatToBottom, clearChat, expandPastSession,
    _showScrollBtn, _hideScrollBtn, isUserNearBottom,
} from './components/chatWindow.js';

import { addResponseActions, copyResponseToClipboard, submitResponseFeedback, shareResponse, regenerateResponse } from './components/messageBubble.js';

import {
    setSendButtonMode, startResponseLifecycle, endResponseLifecycle,
    stopCurrentResponse, handleSendOrStop, handleKeyPress, autoResize,
    handleChatFileAttach, removeAttachedFile,
} from './components/inputBox.js';

import {
    toggleSidebar, initSidebarResizer, restoreSidebarState,
    loadUserChatHistory, renderSidebarHistory, createNewSession,
    viewSessionHistory, showDeleteConfirm, confirmDeleteSession, cancelDeleteSession,
    startRenameSession, renameSession,
} from './components/sidebar.js';

import { updateSuggestions, onSuggestionClick } from './components/suggestionChips.js';

import {
    copySqlFromExpander, toggleSqlPanel, toggleSqlEdit, executeSqlFromCard,
    exportTableToCSV, renderKpiChart, switchKpiChart, toggleKpiViz,
} from './components/sqlCard.js';

import { paginateTable, buildPageNumbers } from './services/markdownRenderer.js';

import {
    handleSemiAutoDiagnostic, startSOPWorkflow,
    selectSOPProblem, confirmSOPSelection, submitSOPObservation, submitSOPStepInput,
    markSOPResolved, markSOPNotResolved,
} from './components/sopWorkflow.js';

/* ══════════════════════════════════════════════════════════════════
   1.  SEND MESSAGE — main orchestrator
═══════════════════════════════════════════════════════════════════ */

/** Entry point called from EventBus or public API */
export async function sendMessage(overrideText) {
    if (State.get('responseInProgress')) return;

    const input = document.getElementById('chatInput');
    const message = (overrideText ?? input?.value ?? '').trim();
    if (!message) return;

    if (input) { input.value = ''; autoResize(input); }

    const chatbotType = State.get('currentChatbotType') || 'knowledge_base';
    const sessionId   = State.get('sessionId');
    const userId      = getEffectiveUserId();

    // Show user bubble
    appendMessage('user', message, {}, false, null);

    // ── Semi-auto diagnostic shortcut ──
    if (chatbotType === 'semi_auto_diagnostic') {
        State.set('attachedDocumentText', null);
        State.set('attachedFileName', null);
        removeAttachedFile();
        startSOPWorkflow(message);
        return;
    }

    // ── Normal flow ──
    const runId       = (State.get('activeResponseRunId') || 0) + 1;
    const renderToken = Symbol('renderToken');
    State.set('activeResponseRunId', runId);
    State.set('activeRenderToken', renderToken);

    const ctrl = new AbortController();
    State.set('activeResponseAbortController', ctrl);

    startResponseLifecycle();
    showTypingIndicator(chatbotType);

    const attachedDocumentText = State.get('attachedDocumentText');
    const attachedFileName     = State.get('attachedFileName');
    const payload              = buildPayload(message, chatbotType, sessionId, userId, attachedDocumentText, attachedFileName);

    // Clear attached doc after sending
    State.set('attachedDocumentText', null);
    State.set('attachedFileName', null);
    removeAttachedFile();

    try {
        const data = await chatApi.sendChat({ ...payload, signal: ctrl.signal });

        if (runId !== State.get('activeResponseRunId')) return; // stale run

        hideTypingIndicator();

        // Update session ID if backend returns a new one
        if (data.session_id && !State.get('sessionId')) {
            State.set('sessionId', data.session_id);
            const span = document.getElementById('currentSessionId');
            if (span) span.textContent = data.session_id;
            loadUserChatHistory();
        }

        const responseText = data.response || data.message || data.answer || '';
        data._userMessage  = message;
        appendMessage('assistant', responseText, data, false, renderToken);

    } catch (err) {
        if (err.name === 'AbortError') {
            // user stopped — already handled
        } else {
            hideTypingIndicator();
            appendMessage('system', `<em>Error: ${err.message || 'Could not reach the server.'}</em>`, {}, false, null);
        }
    } finally {
        endResponseLifecycle(runId);
    }
}

/** Called by regenerateResponse from messageBubble */
export function sendMessageText(text) {
    sendMessage(text);
}

/**
 * Handle KPI disambiguation selection.
 * Called when the user clicks one of the three options
 * (KPI 1, KPI 2, or "None of these").
 */
export async function handleKpiSelection(disambigId, kpiId, originalQuestion) {
    const container = document.getElementById(disambigId);
    if (!container) return;

    // Disable all buttons to prevent double-click
    container.querySelectorAll('.kpi-disambig-btn').forEach(btn => {
        btn.disabled = true;
        btn.style.opacity = '0.5';
        btn.style.pointerEvents = 'none';
    });

    // Highlight the selected button
    const selectedBtn = event?.target?.closest?.('.kpi-disambig-btn');
    if (selectedBtn) {
        selectedBtn.style.opacity = '1';
        selectedBtn.classList.add('selected');
    }

    // Show loading indicator
    const loadingEl = document.getElementById(`${disambigId}_loading`);
    if (loadingEl) loadingEl.style.display = 'flex';

    const sessionId = State.get('sessionId');
    const userId = getEffectiveUserId();

    try {
        showTypingIndicator('sql_assistant');

        const data = await chatApi.selectKpi({
            kpiId,
            originalQuestion,
            sessionId,
            userId,
        });

        hideTypingIndicator();

        if (loadingEl) loadingEl.style.display = 'none';

        const responseText = data.response || data.message || '';
        data._userMessage = originalQuestion;
        appendMessage('assistant', responseText, data, false, null);

    } catch (err) {
        hideTypingIndicator();
        if (loadingEl) loadingEl.style.display = 'none';
        appendMessage('system', `<em>Error: ${err.message || 'KPI selection failed.'}</em>`, {}, false, null);
    }
}

/* ══════════════════════════════════════════════════════════════════
   2.  MISC ACTIONS
═══════════════════════════════════════════════════════════════════ */

export function executeSuggestedAction(action) {
    sendMessage(action);
}

export async function viewSystemHealth() {
    showToast('Loading system health…');
    try {
        const data = await chatApi.getSystemHealth?.() || {};
        appendMessage('system', `<pre>${JSON.stringify(data, null, 2)}</pre>`, {}, false, null);
    } catch (e) { showToast('System health unavailable.'); }
}

export async function viewStatistics() {
    showToast('Loading statistics…');
    try {
        const data = await chatApi.getStatistics?.() || {};
        appendMessage('system', `<pre>${JSON.stringify(data, null, 2)}</pre>`, {}, false, null);
    } catch (e) { showToast('Statistics unavailable.'); }
}

export function toggleToolsMenu() {
    const menu = document.getElementById('toolsMenu');
    if (menu) menu.classList.toggle('active');
}

export async function handleFileUpload(event) {
    const file = event?.target?.files?.[0];
    if (!file) return;
    showToast(`Uploading "${file.name}"…`);
    const formData = new FormData();
    formData.append('file', file);
    try {
        const res  = await fetch('/api/chatbot/upload-document', { method: 'POST', body: formData });
        const data = await res.json();
        showToast(data.message || 'Document uploaded!');
    } catch (e) {
        showToast('Upload failed.');
    }
}

/* ══════════════════════════════════════════════════════════════════
   3.  CHATBOT TYPE SWITCHING
═══════════════════════════════════════════════════════════════════ */

function switchChatbotType(type) {
    if (!CHATBOT_TYPES[type]) return;
    State.set('currentChatbotType', type);

    document.querySelectorAll('.chatbot-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.type === type);
    });

    updateSuggestions(type);

    const placeholder = document.getElementById('chatInput');
    const hints = {
        knowledge_base:      'Ask NEO a question about your knowledge base…',
        sql_assistant:       'Ask NEO to query your data…',
        diagnostic:          'Describe your issue for guided diagnosis…',
        semi_auto_diagnostic:'Describe a machine problem to start the diagnostic workflow…',
    };
    if (placeholder) placeholder.placeholder = hints[type] || 'Type a message…';
}

/* ══════════════════════════════════════════════════════════════════
   4.  DOM CONTENT LOADED
═══════════════════════════════════════════════════════════════════ */

document.addEventListener('DOMContentLoaded', () => {
    /* Auth */
    enforceAuth();

    /* Sidebar */
    initSidebarResizer();
    restoreSidebarState();
    loadUserChatHistory();

    /* Suggestions */
    onSuggestionClick(text => sendMessage(text));
    updateSuggestions(State.get('currentChatbotType') || 'knowledge_base');

    /* Chatbot type buttons */
    document.querySelectorAll('.chatbot-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const type = btn.dataset.type;
            if (type) switchChatbotType(type);
        });
    });

    /* Scroll listener */
    const chatMessages = document.getElementById('chatMessages');
    if (chatMessages) {
        chatMessages.addEventListener('scroll', () => {
            State.set('_userNearBottom', isUserNearBottom(chatMessages));
            if (State.get('_userNearBottom')) _hideScrollBtn();
            else if (!State.get('responseInProgress')) _showScrollBtn();
        });
    }

    /* EventBus: send message */
    EventBus.on('send:message', () => sendMessage());

    /* Close tools menu on outside click */
    document.addEventListener('click', (e) => {
        const menu = document.getElementById('toolsMenu');
        const btn  = document.getElementById('toolsMenuBtn');
        if (menu && !menu.contains(e) && e.target !== btn) {
            menu.classList.remove('active');
        }
    });

    /* Restore session ID from DOM if present */
    const span = document.getElementById('currentSessionId');
    if (span?.textContent?.trim()) {
        State.set('sessionId', span.textContent.trim());
    }
});

/* ══════════════════════════════════════════════════════════════════
   5.  WINDOW GLOBALS  (called from dynamically generated HTML)
═══════════════════════════════════════════════════════════════════ */

// Input
window.handleSendOrStop      = handleSendOrStop;
window.handleKeyPress        = handleKeyPress;
window.autoResize            = autoResize;
window.handleChatFileAttach  = handleChatFileAttach;
window.removeAttachedFile    = removeAttachedFile;

// Scroll / chat
window.scrollChatToBottom    = scrollChatToBottom;
window.clearChat             = clearChat;
window.expandPastSession     = expandPastSession;
window.executeSuggestedAction = executeSuggestedAction;

// SQL card
window.copySqlFromExpander   = copySqlFromExpander;
window.toggleSqlPanel        = toggleSqlPanel;
window.toggleSqlEdit         = toggleSqlEdit;
window.executeSqlFromCard    = executeSqlFromCard;
window.exportTableToCSV      = exportTableToCSV;
window.renderKpiChart        = renderKpiChart;
window.switchKpiChart        = switchKpiChart;
window.toggleKpiViz          = toggleKpiViz;
window.handleKpiSelection    = handleKpiSelection;

// Pagination (also set in markdownRenderer but set again for safety)
window.paginateTable         = paginateTable;
window.buildPageNumbers      = buildPageNumbers;

// SOP Workflow
window.selectSOPProblem      = selectSOPProblem;
window.confirmSOPSelection   = confirmSOPSelection;
window.submitSOPObservation  = submitSOPObservation;
window.submitSOPStepInput    = submitSOPStepInput;
window.markSOPResolved       = markSOPResolved;
window.markSOPNotResolved    = markSOPNotResolved;

// Sidebar / session
window.toggleSidebar         = toggleSidebar;
window.createNewSession      = createNewSession;
window.viewSessionHistory    = viewSessionHistory;
window.showDeleteConfirm     = showDeleteConfirm;
window.confirmDeleteSession  = confirmDeleteSession;
window.cancelDeleteSession   = cancelDeleteSession;
window.startRenameSession    = startRenameSession;
window.renameSession         = renameSession;
window.expandPastSession     = expandPastSession;

// Response actions
window.copyResponseToClipboard = copyResponseToClipboard;
window.submitResponseFeedback  = submitResponseFeedback;
window.shareResponse           = shareResponse;
window.regenerateResponse      = regenerateResponse;

// Tools menu / misc
window.toggleToolsMenu       = toggleToolsMenu;
window.handleFileUpload      = handleFileUpload;
window.viewSystemHealth      = viewSystemHealth;
window.viewStatistics        = viewStatistics;
