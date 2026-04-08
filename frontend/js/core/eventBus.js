/**
 * eventBus.js — Lightweight publish/subscribe event bus.
 *
 * Usage:
 *   import EventBus from './eventBus.js';
 *   EventBus.on('message:send', ({ text }) => { ... });
 *   EventBus.emit('message:send', { text: 'Hello' });
 *   EventBus.off('message:send', handler);
 */

const _listeners = {};

const EventBus = {
    /**
     * Subscribe to an event.
     * @param {string}   event
     * @param {Function} fn
     * @returns {Function} Unsubscribe function
     */
    on(event, fn) {
        if (!_listeners[event]) _listeners[event] = [];
        _listeners[event].push(fn);
        return () => this.off(event, fn);
    },

    /** Subscribe for a single firing, then auto-unsubscribe. */
    once(event, fn) {
        const wrapper = (...args) => {
            fn(...args);
            this.off(event, wrapper);
        };
        return this.on(event, wrapper);
    },

    /** Unsubscribe a specific handler. */
    off(event, fn) {
        if (!_listeners[event]) return;
        _listeners[event] = _listeners[event].filter(f => f !== fn);
    },

    /** Emit an event, passing payload to all subscribers. */
    emit(event, payload) {
        (_listeners[event] || []).forEach(fn => {
            try { fn(payload); } catch (e) { console.error(`EventBus error [${event}]:`, e); }
        });
    },
};

export default EventBus;
