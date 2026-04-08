/**
 * suggestionChips.js — Renders and handles suggestion chips.
 */

import { SUGGESTIONS } from '../utils/constants.js';

let _onChipClick = null;

/**
 * Register a callback invoked when the user clicks a chip.
 * @param {function} fn - receives (text: string)
 */
export function onSuggestionClick(fn) {
    _onChipClick = fn;
}

/**
 * Re-render suggestion chips for the given chatbot type.
 * Looks for #emptySuggestions or #suggestionsArea in the DOM.
 */
export function updateSuggestions(chatbotType) {
    const suggestions = SUGGESTIONS[chatbotType] || [];
    const container   = document.getElementById('emptySuggestions') || document.getElementById('suggestionsArea');
    if (!container) return;

    const chips = container.querySelectorAll('.suggestion-chip');
    chips.forEach((chip, idx) => {
        const text = suggestions[idx] || '';
        if (text) {
            chip.textContent  = text;
            chip.style.display = '';
        } else {
            chip.style.display = 'none';
        }
    });

    // Bind click events
    container.querySelectorAll('.suggestion-chip').forEach(chip => {
        chip.onclick = () => {
            const text = chip.textContent.trim();
            if (text && _onChipClick) _onChipClick(text);
        };
    });
}
