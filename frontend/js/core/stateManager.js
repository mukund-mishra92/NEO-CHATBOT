/**
 * stateManager.js — Single source of truth for all mutable UI state.
 *
 * Components read state via State.get() and write via State.set().
 * Setting a value fires any registered watchers automatically.
 */

const _state = {
    // Active chatbot type
    currentChatbotType: 'knowledge_base',

    // Current conversation session
    sessionId: null,

    // Number of assistant messages rendered
    messageCount: 0,

    // Whether a response is currently streaming
    responseInProgress: false,

    // Fetch AbortController for the active request
    activeResponseAbortController: null,

    // Token object used to cancel typewriter streaming
    activeRenderToken: null,

    // Whether the user pressed Stop
    stopRequested: false,

    // Monotonically-increasing ID so stale callbacks self-cancel
    activeResponseRunId: 0,

    // Currently attached document context
    attachedDocumentText: null,
    attachedFileName: null,

    // Semi-auto diagnostic / SOP state
    semiAutoDiagSession: null,
    sopSessionId: null,
    sopCurrentStatus: null,
    sopWorkflowCardId: null,
    sopStepsCompleted: [],
    selectedSOPSNo: null,

    // Scroll behaviour
    userNearBottom: true,
};

// Watcher registry: key → [fn, ...]
const _watchers = {};

const State = {
    get(key) {
        return _state[key];
    },

    set(key, value) {
        _state[key] = value;
        if (_watchers[key]) {
            _watchers[key].forEach(fn => fn(value, key));
        }
    },

    /** Watch a specific key for changes. Returns an unsubscribe function. */
    watch(key, fn) {
        if (!_watchers[key]) _watchers[key] = [];
        _watchers[key].push(fn);
        return () => {
            _watchers[key] = _watchers[key].filter(f => f !== fn);
        };
    },

    /** Convenience: increment a numeric state value and return new value. */
    increment(key) {
        const next = (_state[key] || 0) + 1;
        this.set(key, next);
        return next;
    },
};

export default State;
