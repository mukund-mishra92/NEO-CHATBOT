/**
 * markdownRenderer.js — Converts markdown text to HTML,
 *                        SQL syntax highlighting, and text sanitization.
 */

import { escapeHtml } from '../utils/helpers.js';

/* ── Paginated table registry (shared with sqlCard) ── */
if (!window.paginatedTables) window.paginatedTables = {};

/* ── Page number HTML builder ── */
export function buildPageNumbers(currentPage, totalPages, tableId) {
    let html = '';
    const maxVisible = 5;
    let startPage, endPage;

    if (totalPages <= maxVisible + 2) {
        startPage = 1; endPage = totalPages;
    } else {
        const half = Math.floor(maxVisible / 2);
        startPage = Math.max(1, currentPage - half);
        endPage   = Math.min(totalPages, currentPage + half);
        if (endPage - startPage + 1 < maxVisible) {
            if (startPage === 1) endPage = Math.min(totalPages, startPage + maxVisible - 1);
            else startPage = Math.max(1, endPage - maxVisible + 1);
        }
    }

    if (startPage > 1) {
        html += `<button onclick="paginateTable('${tableId}', 1)">1</button>`;
        if (startPage > 2) html += `<span style="padding:0 4px;color:#999;">...</span>`;
    }
    for (let i = startPage; i <= endPage; i++) {
        const cls = i === currentPage ? 'active' : '';
        html += `<button class="${cls}" onclick="paginateTable('${tableId}', ${i})">${i}</button>`;
    }
    if (endPage < totalPages) {
        if (endPage < totalPages - 1) html += `<span style="padding:0 4px;color:#999;">...</span>`;
        html += `<button onclick="paginateTable('${tableId}', ${totalPages})">${totalPages}</button>`;
    }
    return html;
}

/* ── Paginate an existing table ── */
export function paginateTable(tableId, action) {
    const tableData = window.paginatedTables[tableId];
    if (!tableData) return;

    let newPage = tableData.currentPage;
    if (action === 'prev')             newPage = Math.max(1, tableData.currentPage - 1);
    else if (action === 'next')        newPage = Math.min(tableData.totalPages, tableData.currentPage + 1);
    else if (typeof action === 'number') newPage = action;

    if (newPage === tableData.currentPage) return;
    tableData.currentPage = newPage;

    const tbody = document.getElementById(`${tableId}_tbody`);
    if (!tbody) return;

    const startIdx = (newPage - 1) * tableData.rowsPerPage;
    const pageRows = tableData.rows.slice(startIdx, startIdx + tableData.rowsPerPage);

    tbody.innerHTML = pageRows.map((cells, idx) => {
        const bg = idx % 2 === 0 ? '#ffffff' : '#f8f9fa';
        return `<tr style="background:${bg};">` + cells.map(cell => {
            const v = (cell === null || cell === undefined || cell === 'null' || cell === 'undefined') ? '' : String(cell).trim();
            const d = v === '' ? '&nbsp;' : escapeHtml(v);
            return `<td title="${v === '' ? '' : escapeHtml(v)}">${d}</td>`;
        }).join('') + '</tr>';
    }).join('');

    const pageInfo = document.getElementById(`${tableId}_pageinfo`);
    if (pageInfo) pageInfo.textContent = `Page ${newPage} of ${tableData.totalPages}`;

    const prevBtn = document.getElementById(`${tableId}_prev`);
    const nextBtn = document.getElementById(`${tableId}_next`);
    if (prevBtn) prevBtn.disabled = newPage === 1;
    if (nextBtn) nextBtn.disabled = newPage === tableData.totalPages;

    const pagesContainer = document.getElementById(`${tableId}_pages`);
    if (pagesContainer) pagesContainer.innerHTML = buildPageNumbers(newPage, tableData.totalPages, tableId);
}

/* Make paginateTable globally accessible for inline onclick attributes */
window.paginateTable = paginateTable;

/* ── SQL syntax highlighter ── */
export function highlightSqlSyntax(sqlText) {
    const escaped = escapeHtml(sqlText || '');
    const keywordPattern = /\b(LEFT\s+JOIN|RIGHT\s+JOIN|INNER\s+JOIN|GROUP\s+BY|ORDER\s+BY|SELECT|FROM|WHERE|HAVING|LIMIT|JOIN|ON|AND|OR|IN|AS|DISTINCT|DESC|ASC)\b/gi;
    const functionPattern = /\b(COUNT|AVG|SUM|MIN|MAX|DATE_SUB|CURDATE|INTERVAL|NOW)\b/gi;
    const numberPattern = /\b(\d+)\b/g;

    return escaped
        .replace(functionPattern, '<span class="sql-token-function">$1</span>')
        .replace(keywordPattern, '<span class="sql-token-keyword">$1</span>')
        .replace(numberPattern, '<span class="sql-token-number">$1</span>');
}

/* ── Text sanitizer ── */
export function sanitizeAssistantText(text) {
    return (text || '')
        .replace(/\uFFFD/g, '')
        .replace(/[\u200D\uFE0F]/g, '')
        .replace(/[ \t]{2,}/g, ' ')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

/* ── SQL formatter ── */
export function formatSqlForDisplay(sql) {
    if (!sql) return '';
    const condensed = sql.replace(/\s+/g, ' ').trim();
    return condensed
        .replace(/\bSELECT\b/gi, 'SELECT')
        .replace(/\bFROM\b/gi, '\nFROM')
        .replace(/\bWHERE\b/gi, '\nWHERE')
        .replace(/\bGROUP BY\b/gi, '\nGROUP BY')
        .replace(/\bORDER BY\b/gi, '\nORDER BY')
        .replace(/\bHAVING\b/gi, '\nHAVING')
        .replace(/\bLIMIT\b/gi, '\nLIMIT')
        .replace(/\bINNER JOIN\b/gi, '\nINNER JOIN')
        .replace(/\bLEFT JOIN\b/gi, '\nLEFT JOIN')
        .replace(/\bRIGHT JOIN\b/gi, '\nRIGHT JOIN')
        .replace(/\bJOIN\b/gi, '\nJOIN')
        .replace(/\bAND\b/gi, '\n  AND')
        .replace(/\bOR\b/gi, '\n  OR');
}

/* ── Extract SQL blocks from markdown text ── */
export function extractSqlBlocks(text) {
    const sqlBlocks = [];
    let cleaned = (text || '').replace(/```sql\s*([\s\S]*?)```/gi, (match, sqlBody) => {
        const normalized = (sqlBody || '').trim();
        if (normalized) sqlBlocks.push(normalized);
        return '';
    });

    cleaned = cleaned
        .replace(/^\s*(?:\*\*)?\s*[🧾📜]?\s*SQL\s*Query\s*:?\s*(?:\*\*)?\s*$/gmi, '')
        .replace(/^\s*#{1,6}\s*[🧾📜]?\s*SQL\s*Query\s*:?\s*$/gmi, '')
        .replace(/^\s*<h[1-6][^>]*>\s*[🧾📜]?\s*SQL\s*Query\s*:?\s*<\/h[1-6]>\s*$/gmi, '')
        .replace(/\n{3,}/g, '\n\n')
        .trim();

    return { cleanedText: cleaned, sqlBlocks };
}

/* ── Main markdown → HTML converter ── */
export function convertMarkdownToHTML(text) {
    if (!text) return '';
    let html = text;

    // Horizontal rules
    html = html.replace(/^\s*---+\s*$/gm, '<hr style="border:none;border-top:1px solid #dbe3f5;margin:12px 0;">');

    // Markdown tables → paginated HTML tables
    html = html.replace(/\|(.+)\|\n\|([\s\-\|]+)\|\n((\|.+\|\n?)+)/g, function(match, header, separator, rows) {
        const headers  = header.split('|').map(h => h.trim()).filter(h => h);
        const rowLines = rows.trim().split('\n');
        const rowsPerPage = 5;
        const tableId = 'ptable_' + Math.random().toString(36).substr(2, 9);

        const allRows = [];
        rowLines.forEach(row => {
            let cells = row.split('|').map(c => c.trim()).filter(c => c);
            if (headers.length > 0 && cells.length > headers.length) {
                if (headers.length === 1) {
                    cells = [cells.join(' | ')];
                } else {
                    const tailCount = headers.length - 1;
                    cells = [cells.slice(0, cells.length - tailCount).join(' | '), ...cells.slice(cells.length - tailCount)];
                }
            }
            if (cells.length > 0) allRows.push(cells);
        });

        window.paginatedTables[tableId] = {
            headers, rows: allRows, currentPage: 1, rowsPerPage,
            totalPages: Math.ceil(allRows.length / rowsPerPage),
        };

        let t = `<div class="paginated-table-container" id="${tableId}_container">`;
        t += `<div class="paginated-table-header">
            <span class="result-count">Found ${allRows.length} result(s)</span>
            <span class="page-info" id="${tableId}_pageinfo">Page 1 of ${Math.ceil(allRows.length / rowsPerPage)}</span>
        </div>`;
        t += `<div class="paginated-table-scroll"><table>
            <thead><tr>${headers.map(h => `<th>${h}</th>`).join('')}</tr></thead>
            <tbody id="${tableId}_tbody">`;
        allRows.slice(0, rowsPerPage).forEach((cells, idx) => {
            t += `<tr style="background:${idx % 2 === 0 ? '#ffffff' : '#f8f9fa'};">`;
            cells.forEach(cell => {
                const v = (cell === null || cell === undefined || cell === 'null' || cell === 'undefined') ? '' : String(cell).trim();
                t += `<td title="${v === '' ? '' : escapeHtml(v)}">${v === '' ? '&nbsp;' : escapeHtml(v)}</td>`;
            });
            t += '</tr>';
        });
        t += '</tbody></table></div>';

        if (allRows.length > rowsPerPage) {
            const totalPages = Math.ceil(allRows.length / rowsPerPage);
            t += `<div class="pagination-controls" id="${tableId}_pagination">
                <button onclick="paginateTable('${tableId}','prev')" id="${tableId}_prev" disabled><i class="fas fa-chevron-left"></i> Prev</button>
                <div class="page-numbers" id="${tableId}_pages">${buildPageNumbers(1, totalPages, tableId)}</div>
                <button onclick="paginateTable('${tableId}','next')" id="${tableId}_next">Next <i class="fas fa-chevron-right"></i></button>
            </div>`;
        }
        t += '</div>';
        return t;
    });

    // Headings
    html = html.replace(/^### (.*?)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.*?)$/gm,  '<h2>$1</h2>');
    html = html.replace(/^# (.*?)$/gm,   '<h1>$1</h1>');

    // Bold / italic
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g,     '<em>$1</em>');

    // [Document Name] references (not followed by '(' so we don't break links)
    html = html.replace(/\[([^\]]+)\](?!\()/g,
        '<span style="background:#e3f2fd;color:#1976d2;padding:2px 8px;border-radius:4px;font-size:0.9em;font-weight:500;">$1</span>');

    // Markdown links [text](url)
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g,
        '<a href="$2" target="_blank" rel="noopener" style="color:#667eea;font-weight:500;text-decoration:underline;">$1</a>');

    // Bullet / numbered lists
    html = html.replace(/^[•·]\s*(.+)$/gm, '<li>$1</li>');
    html = html.replace(/^-\s+(.+)$/gm,    '<li>$1</li>');
    html = html.replace(/^(\d+)\.\s+(.+)$/gm, '<li value="$1">$2</li>');

    // Wrap consecutive <li> in <ul> or <ol>
    html = html.replace(/(<li[^>]*>[\s\S]*?<\/li>\s*)+/g, match => {
        const tag = match.includes('value="') ? 'ol' : 'ul';
        return `<${tag}>${match}</${tag}>`;
    });

    // Line breaks
    html = html.replace(/\n\n/g, '<br>');
    html = html.replace(/\n/g,   '<br>');
    html = html.replace(/(<br\s*\/?\s*>){3,}/gi, '<br><br>');

    // Remove <br> immediately after/before block-level elements
    html = html.replace(/(<\/(?:h[1-6]|ul|ol|li|p|div|table|blockquote|hr)>)\s*(?:<br\s*\/?\s*>)+/gi, '$1');
    html = html.replace(/(?:<br\s*\/?\s*>)+\s*(<(?:h[1-6]|ul|ol|p|div|table|blockquote|hr)[^>]*>)/gi, '$1');

    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    return html;
}
