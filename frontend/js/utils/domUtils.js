/**
 * domUtils.js — Tiny selector and element-creation helpers.
 */

/**
 * Single-element selector (querySelector shorthand).
 * @param {string} selector
 * @param {Element} [root=document]
 */
export function $(selector, root = document) {
    return root.querySelector(selector);
}

/**
 * Multi-element selector (querySelectorAll shorthand).
 * @param {string} selector
 * @param {Element} [root=document]
 * @returns {Element[]}
 */
export function $$(selector, root = document) {
    return Array.from(root.querySelectorAll(selector));
}

/**
 * Create an element with optional class names, attributes and text.
 * @param {string} tag
 * @param {object} [opts]
 * @param {string|string[]} [opts.className]
 * @param {object}          [opts.attrs]
 * @param {string}          [opts.text]
 * @param {string}          [opts.html]
 * @returns {HTMLElement}
 */
export function createElement(tag, opts = {}) {
    const el = document.createElement(tag);

    if (opts.className) {
        const classes = Array.isArray(opts.className) ? opts.className : [opts.className];
        el.classList.add(...classes);
    }

    if (opts.attrs) {
        Object.entries(opts.attrs).forEach(([k, v]) => el.setAttribute(k, v));
    }

    if (opts.text !== undefined) el.textContent = opts.text;
    if (opts.html !== undefined) el.innerHTML   = opts.html;

    return el;
}
