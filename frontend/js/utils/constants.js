/**
 * constants.js — Application-wide constants and suggestion data
 */

// API base (empty string = same origin)
export const API_BASE = '';

// Chatbot type identifiers
export const CHATBOT_TYPES = {
    KNOWLEDGE_BASE:      'knowledge_base',
    SQL_ASSISTANT:       'sql_assistant',
    SEMI_AUTO_DIAGNOSTIC:'semi_auto_diagnostic',
    DIAGNOSTIC:          'diagnostic',
};

// Streaming typewriter config
export const STREAMING_CONFIG = {
    enabled: true,
    wordsPerSecond: 15,
    minDelay: 20,
    maxDelay: 60,
};

// Suggestion chips per chatbot type
export const SUGGESTIONS = {
    knowledge_base: [
        'How does this system work?',
        'What are the main features?',
        'Show me the troubleshooting guide',
        'Explain the architecture',
    ],
    sql_assistant: [
        'Show production summary for today',
        'List top 10 machines by downtime',
        'What is the current shift output?',
        'Show quality defects this week',
    ],
    diagnostic: [
        'Run system diagnostics',
        'Check current alarms',
        'Show error history',
        'What is the machine status?',
    ],
    semi_auto_diagnostic: [
        'Machine is not starting',
        'Production stopped unexpectedly',
        'Quality defects observed',
        'E-stop triggered',
    ],
};

// Image score thresholds (mirrors backend logic)
export const IMAGE_SCORE_ALWAYS = 0.90;
export const IMAGE_SCORE_NEVER  = 0.40;
export const MAX_IMAGES         = 3;

// Sidebar dimensions
export const SIDEBAR_MIN_WIDTH = 240;
export const SIDEBAR_MAX_WIDTH = 560;
