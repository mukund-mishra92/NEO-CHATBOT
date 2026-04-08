/**
 * sidebar.js — Sidebar toggle, resize, session history management.
 */

import State from '../core/stateManager.js';
import { getEffectiveUserId, showToast } from '../utils/helpers.js';
import { getUserSessions, createSession, renameSession as apiRenameSession, deleteSession as apiDeleteSession } from '../api/chatApi.js';
import { SIDEBAR_MIN_WIDTH, SIDEBAR_MAX_WIDTH } from '../utils/constants.js';

/* ── Sidebar open/close ── */
export function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;
    const isCollapsed = sidebar.classList.toggle('collapsed');
    const btn = document.getElementById('sidebarToggleBtn');
    if (btn) {
        btn.querySelector('i')?.classList.toggle('fa-chevron-left', !isCollapsed);
        btn.querySelector('i')?.classList.toggle('fa-chevron-right', isCollapsed);
    }
    localStorage.setItem('neo_sidebar_collapsed', isCollapsed ? '1' : '0');
}

/* ── Restore sidebar state from localStorage ── */
export function restoreSidebarState() {
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;
    const savedWidth = localStorage.getItem('neo_sidebar_width');
    if (savedWidth) applySidebarWidth(parseInt(savedWidth, 10));
    if (localStorage.getItem('neo_sidebar_collapsed') === '1') sidebar.classList.add('collapsed');
}

/* ── Apply explicit width ── */
export function applySidebarWidth(width) {
    const clamped = Math.min(SIDEBAR_MAX_WIDTH, Math.max(SIDEBAR_MIN_WIDTH, width));
    const sidebar  = document.getElementById('sidebar');
    if (sidebar) sidebar.style.width = `${clamped}px`;
}

/* ── Drag-to-resize sidebar ── */
export function initSidebarResizer() {
    const resizer = document.getElementById('sidebarResizer');
    if (!resizer) return;
    let startX, startWidth;

    const onMouseMove = (e) => {
        const newWidth = startWidth + (e.clientX - startX);
        applySidebarWidth(newWidth);
    };
    const onMouseUp = () => {
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
        const sidebar = document.getElementById('sidebar');
        if (sidebar) localStorage.setItem('neo_sidebar_width', sidebar.offsetWidth);
    };

    resizer.addEventListener('mousedown', (e) => {
        startX = e.clientX;
        startWidth = document.getElementById('sidebar')?.offsetWidth || SIDEBAR_MIN_WIDTH;
        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
        e.preventDefault();
    });
}

/* ── Load user chat history ── */
export async function loadUserChatHistory() {
    const userId = getEffectiveUserId();
    if (!userId) return;
    try {
        const sessions = await getUserSessions(userId, 30);
        renderSidebarHistory(sessions);
    } catch (e) {
        console.warn('Could not load chat history:', e);
    }
}

/* ── Render session list ── */
export function renderSidebarHistory(sessions) {
    const list = document.getElementById('sidebarHistoryList');
    if (!list) return;

    if (!sessions?.length) {
        list.innerHTML = '<li class="sidebar-empty">No previous chats</li>';
        return;
    }

    list.innerHTML = sessions.map(session => {
        const name    = session.name || session.session_name || `Chat ${session.session_id?.slice(0, 8) || ''}`;
        const msgCount = session.message_count || 0;
        const created  = session.created_at ? new Date(session.created_at).toLocaleDateString() : '';
        const sessionId = session.session_id;
        const encodedName = encodeURIComponent(name);

        return `<li class="sidebar-history-item" data-session-id="${sessionId}" title="${name}">
            <div class="sidebar-history-item-inner" onclick="expandPastSession('${sessionId}')">
                <i class="fas fa-comment-alt sidebar-history-icon"></i>
                <div class="sidebar-history-info">
                    <span class="sidebar-history-name">${name}</span>
                    <span class="sidebar-history-meta">${created}${msgCount ? ` · ${msgCount} msgs` : ''}</span>
                </div>
            </div>
            <div class="sidebar-history-actions">
                <button class="history-rename" title="Rename" onclick="startRenameSession(event,'${sessionId}','${encodedName}')"><i class="fas fa-pen"></i></button>
                <button class="history-delete" title="Delete" onclick="showDeleteConfirm('${sessionId}')"><i class="fas fa-trash"></i></button>
            </div>
        </li>`;
    }).join('');
}

/* ── Create new session ── */
export async function createNewSession() {
    try {
        const data = await createSession();
        const newId = data.session_id || data.id;
        if (!newId) return;
        State.set('sessionId', newId);
        const span = document.getElementById('currentSessionId');
        if (span) span.textContent = newId;

        // Clear chat
        const { clearChat } = await import('./chatWindow.js');
        clearChat();
        await loadUserChatHistory();
    } catch (e) {
        showToast('Could not create new session.');
        console.error(e);
    }
}

/* ── View all sessions modal shortcut ── */
export function viewSessionHistory() {
    const sidebar = document.getElementById('sidebar');
    if (sidebar) sidebar.classList.remove('collapsed');
}

/* ── Delete session ── */
export function showDeleteConfirm(sessionId) {
    const overlay = document.getElementById('deleteConfirmOverlay');
    if (overlay) {
        overlay.style.display = 'flex';
        overlay.dataset.pendingDeleteId = sessionId;
    }
}

export async function confirmDeleteSession() {
    const overlay = document.getElementById('deleteConfirmOverlay');
    const sessionId = overlay?.dataset.pendingDeleteId;
    if (!sessionId) return;
    overlay.style.display = 'none';

    try {
        await apiDeleteSession(sessionId);
        // If we deleted the current session, clear chat
        if (State.get('sessionId') === sessionId) {
            const { clearChat } = await import('./chatWindow.js');
            clearChat();
            State.set('sessionId', null);
        }
        await loadUserChatHistory();
        showToast('Session deleted.');
    } catch (e) {
        showToast('Could not delete session.');
    }
}

export function cancelDeleteSession() {
    const overlay = document.getElementById('deleteConfirmOverlay');
    if (overlay) overlay.style.display = 'none';
}

/* ── Rename session ── */
export function startRenameSession(event, sessionId, encodedName) {
    if (event) event.stopPropagation();
    const currentName = decodeURIComponent(encodedName);
    const newName = prompt('Rename session:', currentName);
    if (newName && newName.trim() && newName.trim() !== currentName) {
        renameSession(sessionId, newName.trim());
    }
}

export async function renameSession(sessionId, newName) {
    const userId = getEffectiveUserId();
    try {
        await apiRenameSession(userId, sessionId, newName);
        await loadUserChatHistory();
    } catch (e) {
        showToast('Could not rename session.');
    }
}
