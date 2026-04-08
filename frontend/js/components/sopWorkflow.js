/**
 * sopWorkflow.js — Semi-Automated Diagnostic (SOP) workflow UI.
 * All public functions are exposed on window in app.js so they can
 * be called from dynamically-generated HTML strings.
 */

import State from '../core/stateManager.js';
import { showToast } from '../utils/helpers.js';
import { sopStart, sopSelect, sopStepInput, sopResolved as apiSopResolved, sopNotResolved as apiSopNotResolved } from '../api/chatApi.js';
import { appendMessage } from './chatWindow.js';

/* ── Add a message with the SOP avatar style ── */
function addSOPMessage(content, type = 'assistant') {
    appendMessage(type, content, {}, false, null);
}

/* ── Input area HTML for SOP step ── */
export function getSOPInputAreaHTML(stepNum) {
    return `
        <div class="sop-input-area" id="sopInputArea_${stepNum}">
            <textarea id="sopStepInput_${stepNum}" class="sop-step-textarea" placeholder="Describe what you observe …" rows="3"></textarea>
            <button class="sop-submit-btn" onclick="submitSOPStepInput(${stepNum})">
                <i class="fas fa-arrow-right"></i> Submit Observation
            </button>
        </div>`;
}

/* ── Resolution buttons HTML ── */
export function getSOPResolutionButtonsHTML() {
    return `
        <div class="sop-resolution-controls">
            <button class="sop-resolved-btn" onclick="markSOPResolved()">
                <i class="fas fa-check-circle"></i> Issue Resolved
            </button>
            <button class="sop-notresolved-btn" onclick="markSOPNotResolved()">
                <i class="fas fa-times-circle"></i> Not Resolved — Try Next Step
            </button>
        </div>`;
}

/* ── Render a single SOP step result card ── */
export function renderSOPStepResult(step, stepNum) {
    const statusIcon = step.status === 'resolved' ? 'fa-check-circle' : 'fa-arrow-right';
    const instructionHtml = (step.instruction || step.steps || step.content || '')
        .split('\n').map(l => `<p>${l}</p>`).join('');

    return `<div class="sop-step-card" id="sopStepCard_${stepNum}">
        <div class="sop-step-header">
            <span class="sop-step-badge"><i class="fas ${statusIcon}"></i> Step ${stepNum}</span>
            <span class="sop-step-title">${step.title || step.step_title || 'Diagnostic Step'}</span>
        </div>
        <div class="sop-step-instructions">${instructionHtml}</div>
        ${step.expected_observation ? `<div class="sop-step-expected"><strong>Expected:</strong> ${step.expected_observation}</div>` : ''}
        ${getSOPInputAreaHTML(stepNum)}
        ${getSOPResolutionButtonsHTML()}
    </div>`;
}

/* ── Render an ongoing SOP step (from response data) ── */
export function renderSOPStep(data, cardEl) {
    if (!cardEl) return;
    const stepNum = (State.get('sopStepsCompleted') || []).length + 1;
    const stepHtml = renderSOPStepResult(data.step || data, stepNum);
    const bodyEl = cardEl.querySelector('.sop-card-body');
    if (bodyEl) bodyEl.insertAdjacentHTML('beforeend', stepHtml);
}

/* ── Update the master SOP workflow card ── */
export function updateSOPWorkflowCard(data, cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    renderSOPStep(data, card);
}

/* ── Create the master SOP workflow card ── */
export function createSOPWorkflowCard(data, problemDescription) {
    const cardId = 'sopCard_' + Math.random().toString(36).substr(2, 9);
    State.set('sopWorkflowCardId', cardId);

    const html = `<div class="sop-workflow-card" id="${cardId}">
        <div class="sop-card-header">
            <i class="fas fa-tools sop-card-icon"></i>
            <div class="sop-card-title">
                <strong>Semi-Auto Diagnostic</strong>
                <span class="sop-card-subtitle">${problemDescription}</span>
            </div>
        </div>
        <div class="sop-card-body">
            <!-- Steps will be appended here -->
        </div>
    </div>`;

    addSOPMessage(html);
    return cardId;
}

/* ── Show problem selection list ── */
export function showSOPProblemSelection(problems) {
    const listHtml = (problems || []).map((p, idx) =>
        `<div class="sop-problem-option" id="sopProblem_${p.s_no}" onclick="selectSOPProblem(this, '${p.s_no}')">
            <span class="sop-problem-idx">${idx + 1}</span>
            <span class="sop-problem-text">${p.problem || p.title || `Problem ${idx + 1}`}</span>
        </div>`
    ).join('');

    const html = `<div class="sop-problem-selection">
        <p class="sop-problem-intro"><i class="fas fa-list-ul"></i> Select the issue you are experiencing:</p>
        <div class="sop-problem-list">${listHtml}</div>
        <button class="sop-confirm-btn" onclick="confirmSOPSelection()" id="sopConfirmBtn" disabled>
            <i class="fas fa-check"></i> Confirm Selection
        </button>
    </div>`;

    addSOPMessage(html);
}

/* ── Select a problem from the list ── */
export function selectSOPProblem(elem, sNo) {
    document.querySelectorAll('.sop-problem-option').forEach(el => el.classList.remove('selected'));
    if (elem) elem.classList.add('selected');
    State.set('selectedSOPSNo', sNo);

    const confirmBtn = document.getElementById('sopConfirmBtn');
    if (confirmBtn) confirmBtn.disabled = false;
}

/* ── Confirm selected problem ── */
export async function confirmSOPSelection() {
    const sNo       = State.get('selectedSOPSNo');
    const sessionId = State.get('sopSessionId');
    if (!sNo || !sessionId) return;

    // Disable UI
    document.getElementById('sopConfirmBtn')?.setAttribute('disabled', true);
    document.querySelectorAll('.sop-problem-option').forEach(el => el.style.pointerEvents = 'none');

    try {
        const data = await sopSelect(sessionId, sNo);
        const cardId = createSOPWorkflowCard(data, data.problem || 'Selected Issue');
        updateSOPWorkflowCard(data, cardId);
    } catch (err) {
        addSOPMessage(`<em>Error selecting problem: ${err.message}</em>`);
    }
}

/* ── Submit free-text observation ── */
export async function submitSOPObservation() {
    const textarea = document.querySelector('.sop-observation-textarea');
    const description = textarea?.value?.trim();
    if (!description) { showToast('Please describe the issue.'); return; }

    // Show the submitted text
    addSOPMessage(description, 'user');

    try {
        const data = await sopStart(description, State.get('sopSessionId'));
        State.set('sopSessionId', data.session_id || data.sop_session_id);

        if (data.problems?.length > 0) {
            showSOPProblemSelection(data.problems);
        } else if (data.step) {
            const cardId = createSOPWorkflowCard(data, description);
            updateSOPWorkflowCard(data, cardId);
        } else {
            addSOPMessage(data.message || 'Workflow started. Please follow the instructions above.');
        }
    } catch (err) {
        addSOPMessage(`<em>Error starting SOP workflow: ${err.message}</em>`);
    }
}

/* ── Submit observation for a specific step ── */
export async function submitSOPStepInput(stepNum) {
    const ta = document.getElementById(`sopStepInput_${stepNum}`);
    const userInput = ta?.value?.trim();
    if (!userInput) { showToast('Please enter your observation.'); return; }

    // Disable the input
    if (ta) ta.disabled = true;
    const submitBtn = document.querySelector(`#sopInputArea_${stepNum} .sop-submit-btn`);
    if (submitBtn) submitBtn.disabled = true;

    addSOPMessage(userInput, 'user');

    try {
        const data = await sopStepInput(State.get('sopSessionId'), userInput);
        const completed = State.get('sopStepsCompleted') || [];
        State.set('sopStepsCompleted', [...completed, stepNum]);

        if (data.status === 'resolved') {
            addSOPMessage('<div class="sop-resolved-msg"><i class="fas fa-check-circle"></i> Issue has been resolved!</div>');
        } else if (data.step) {
            const cardId = State.get('sopWorkflowCardId');
            if (cardId) updateSOPWorkflowCard(data, cardId);
        } else {
            addSOPMessage(data.message || 'Continuing diagnostic…');
        }
    } catch (err) {
        addSOPMessage(`<em>Error submitting step: ${err.message}</em>`);
    }
}

/* ── Mark issue as resolved ── */
export async function markSOPResolved() {
    try {
        await apiSopResolved(State.get('sopSessionId'));
        addSOPMessage('<div class="sop-resolved-msg"><i class="fas fa-check-circle"></i> Great! Issue marked as resolved. The SOP has been completed.</div>');
    } catch (err) {
        addSOPMessage(`<em>Error: ${err.message}</em>`);
    }
}

/* ── Mark issue as not resolved; go to next step ── */
export async function markSOPNotResolved() {
    try {
        const data = await apiSopNotResolved(State.get('sopSessionId'));
        const completed = State.get('sopStepsCompleted') || [];
        State.set('sopStepsCompleted', [...completed, completed.length + 1]);

        if (data.status === 'exhausted') {
            addSOPMessage('<div class="sop-exhausted-msg"><i class="fas fa-exclamation-triangle"></i> All diagnostic steps have been exhausted. Please contact support.</div>');
        } else if (data.step) {
            const cardId = State.get('sopWorkflowCardId');
            if (cardId) updateSOPWorkflowCard(data, cardId);
        }
    } catch (err) {
        addSOPMessage(`<em>Error: ${err.message}</em>`);
    }
}

/* ── Entry point: handle the initial semi-auto diagnostic message ── */
export async function handleSemiAutoDiagnostic(description) {
    // Reset SOP state
    State.set('sopSessionId', null);
    State.set('sopStepsCompleted', []);
    State.set('sopWorkflowCardId', null);
    State.set('selectedSOPSNo', null);

    // Show input form if description not provided
    if (!description) {
        const html = `<div class="sop-start-form">
            <p><i class="fas fa-tools"></i> <strong>Semi-Auto Diagnostic</strong></p>
            <p>Describe the issue you are experiencing and NEO will guide you step-by-step through the diagnostic process.</p>
            <textarea class="sop-observation-textarea" placeholder="e.g., Machine is not responding, error code E03 on display…" rows="3"></textarea>
            <button class="sop-submit-btn" onclick="submitSOPObservation()">
                <i class="fas fa-arrow-right"></i> Start Diagnostic
            </button>
        </div>`;
        addSOPMessage(html);
        return;
    }

    await submitSOPObservation();
}

/* ── Wrapper to initiate from the chatbot type handler ── */
export function startSOPWorkflow(message) {
    handleSemiAutoDiagnostic(message || '');
}
