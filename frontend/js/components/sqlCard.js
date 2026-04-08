/**
 * sqlCard.js — SQL card toggle, edit, execute and CSV export interactions.
 * Functions that must be on window are exported and re-exposed in app.js.
 */

import { showToast, escapeHtml } from '../utils/helpers.js';
import { executeSQL } from '../api/chatApi.js';
import { convertMarkdownToHTML, buildPageNumbers } from '../services/markdownRenderer.js';

/* ── Copy SQL from expander button ── */
export function copySqlFromExpander(event, encodedSql) {
    if (event) event.stopPropagation();
    const sql = decodeURIComponent(encodedSql);
    navigator.clipboard?.writeText(sql).then(() => showToast('SQL copied!'))
        .catch(() => {
            const ta = document.createElement('textarea');
            ta.value = sql; document.body.appendChild(ta);
            ta.select(); document.execCommand('copy');
            document.body.removeChild(ta);
            showToast('SQL copied!');
        });
}

/* ── Toggle visibility of the SQL panel ── */
export function toggleSqlPanel(cardId) {
    const layout = document.getElementById(`${cardId}_layout`);
    const toggle = document.getElementById(`${cardId}_toggle`);
    if (!layout) return;

    const isCollapsed = layout.classList.toggle('sql-panel-collapsed');
    const label = toggle?.querySelector('.toggle-label');
    if (label) label.textContent = isCollapsed ? 'View SQL' : 'Hide SQL';
    if (toggle) toggle.setAttribute('aria-expanded', String(!isCollapsed));
}

/* ── Toggle between display and edit mode for the SQL ── */
export function toggleSqlEdit(event, cardId) {
    if (event) event.stopPropagation();
    const displayEl = document.getElementById(`${cardId}_display`);
    const editorEl  = document.getElementById(`${cardId}_editor`);
    const btn       = event?.currentTarget || document.querySelector(`[onclick*="toggleSqlEdit"][onclick*="${cardId}"]`);

    if (!displayEl || !editorEl) return;

    const isEditing = editorEl.style.display !== 'none';
    if (isEditing) {
        // Switch back to display mode
        displayEl.style.display = '';
        editorEl.style.display  = 'none';
        if (btn) { btn.innerHTML = '<span class="btn-tooltip">Edit</span><i class="fas fa-pen"></i>'; }
    } else {
        // Switch to edit mode
        displayEl.style.display = 'none';
        editorEl.style.display  = '';
        if (btn) { btn.innerHTML = '<span class="btn-tooltip">Done</span><i class="fas fa-check"></i>'; }
        const ta = document.getElementById(`${cardId}_textarea`);
        if (ta) ta.focus();
    }
}

/* ── Execute SQL from the card ── */
export async function executeSqlFromCard(event, cardId) {
    if (event) event.stopPropagation();

    let sql = '';
    const ta          = document.getElementById(`${cardId}_textarea`);
    const hiddenInput = document.getElementById(`${cardId}_sql`);

    if (ta && document.getElementById(`${cardId}_editor`)?.style.display !== 'none') {
        sql = ta.value.trim();
    } else if (hiddenInput) {
        sql = decodeURIComponent(hiddenInput.value);
    }

    if (!sql) { showToast('No SQL to execute.'); return; }

    const dataBody = document.getElementById(`${cardId}_dataBody`);
    if (dataBody) {
        dataBody.innerHTML = `<div style="text-align:center;padding:20px;color:var(--text-muted);">
            <i class="fas fa-spinner fa-spin"></i> Executing query…
        </div>`;
    }

    try {
        const result = await executeSQL(sql);
        if (!dataBody) return;

        const rows    = result.rows || result.data || [];
        const columns = result.columns || (rows.length > 0 ? Object.keys(rows[0]) : []);

        if (!rows.length) {
            dataBody.innerHTML = `<div class="sql-empty-state">
                <div class="sql-empty-icon"><i class="fas fa-database"></i></div>
                <div class="sql-empty-title">No Results</div>
                <div class="sql-empty-desc">Query executed successfully but returned no rows.</div>
            </div>`;
            return;
        }

        // Build paginated table
        const tableId    = `exec_${cardId}`;
        const rowsPerPage = 5;
        const allRows    = rows.map(row => columns.map(col => row[col] ?? ''));

        if (!window.paginatedTables) window.paginatedTables = {};
        window.paginatedTables[tableId] = {
            headers: columns, rows: allRows, currentPage: 1, rowsPerPage,
            totalPages: Math.ceil(allRows.length / rowsPerPage),
        };

        let tableHtml = `<div class="paginated-table-container">
            <div class="paginated-table-header">
                <span class="result-count">${rows.length} row(s)</span>
                <span class="page-info" id="${tableId}_pageinfo">Page 1 of ${Math.ceil(allRows.length / rowsPerPage)}</span>
            </div>
            <div class="paginated-table-scroll"><table>
            <thead><tr>${columns.map(c => `<th>${escapeHtml(c)}</th>`).join('')}</tr></thead>
            <tbody id="${tableId}_tbody">`;

        allRows.slice(0, rowsPerPage).forEach((cells, idx) => {
            tableHtml += `<tr style="background:${idx % 2 === 0 ? '#fff' : '#f8f9fa'};">`;
            cells.forEach(cell => {
                const v = (cell === null || cell === undefined || String(cell) === 'null') ? '' : String(cell);
                tableHtml += `<td>${v === '' ? '&nbsp;' : escapeHtml(v)}</td>`;
            });
            tableHtml += '</tr>';
        });
        tableHtml += `</tbody></table></div>`;

        if (allRows.length > rowsPerPage) {
            const tp = Math.ceil(allRows.length / rowsPerPage);
            tableHtml += `<div class="pagination-controls">
                <button onclick="paginateTable('${tableId}','prev')" id="${tableId}_prev" disabled><i class="fas fa-chevron-left"></i> Prev</button>
                <div class="page-numbers" id="${tableId}_pages">${buildPageNumbers(1, tp, tableId)}</div>
                <button onclick="paginateTable('${tableId}','next')" id="${tableId}_next">Next <i class="fas fa-chevron-right"></i></button>
            </div>`;
        }
        tableHtml += '</div>';
        dataBody.innerHTML = tableHtml;
    } catch (err) {
        if (dataBody) {
            dataBody.innerHTML = `<div class="sql-empty-state">
                <div class="sql-empty-icon" style="color:#e53e3e;"><i class="fas fa-exclamation-circle"></i></div>
                <div class="sql-empty-title">Query Failed</div>
                <div class="sql-empty-desc">${escapeHtml(err.message || String(err))}</div>
            </div>`;
        }
    }
}

/* ── Export a table to CSV ── */
export function exportTableToCSV(bodyId) {
    const tbody = document.getElementById(bodyId);
    if (!tbody) return;

    const rows = Array.from(tbody.querySelectorAll('tr')).map(tr =>
        Array.from(tr.querySelectorAll('td,th')).map(td => {
            const text = (td.innerText || td.textContent || '').replace(/\s+/g, ' ').trim();
            return `"${text.replace(/"/g, '""')}"`;
        }).join(',')
    );

    const headers = (() => {
        const table = tbody.closest('table');
        if (!table) return '';
        return Array.from(table.querySelectorAll('thead th')).map(th => `"${(th.innerText || th.textContent || '').trim()}"`).join(',');
    })();

    const csvContent = [headers, ...rows].filter(Boolean).join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url; a.download = 'neo_results.csv';
    document.body.appendChild(a); a.click();
    document.body.removeChild(a); URL.revokeObjectURL(url);
    showToast('CSV downloaded!');
}

/* ── KPI chart rendering (depends on Chart.js global) ── */
export function renderKpiChart(containerId, chartType, rows, columns) {
    if (!window.Chart) return;
    if (!window._kpiChartInstances) window._kpiChartInstances = {};
    const container = document.getElementById(containerId);
    if (!container) return;

    const existing = window._kpiChartInstances[containerId];
    if (existing) { existing.destroy(); delete window._kpiChartInstances[containerId]; }

    const labels = (rows || []).map(r => {
        const firstCol = columns[0];
        return firstCol ? String(r[firstCol] ?? '') : '';
    });

    const datasetData = (rows || []).map(r => {
        const valCol = columns[1] || columns[0];
        return valCol ? (parseFloat(r[valCol]) || 0) : 0;
    });

    const colors = ['#667eea','#764ba2','#f6ad55','#68d391','#fc8181','#63b3ed','#ed8936','#9f7aea','#38b2ac','#e53e3e'];
    const bgs    = datasetData.map((_, i) => colors[i % colors.length] + 'cc');

    const type = chartType === 'pie' ? 'pie' : 'bar';

    const canvas = document.createElement('canvas');
    container.innerHTML = '';
    container.appendChild(canvas);

    const chart = new window.Chart(canvas.getContext('2d'), {
        type,
        data: {
            labels,
            datasets: [{
                label: columns[1] || 'Value',
                data: datasetData,
                backgroundColor: type === 'pie' ? bgs : (colors[0] + 'cc'),
                borderColor: type === 'pie' ? bgs.map(c => c.slice(0, 7)) : colors[0],
                borderWidth: 1,
            }],
        },
        options: {
            responsive: true, maintainAspectRatio: false,
            plugins: { legend: { display: type === 'pie' } },
        },
    });

    window._kpiChartInstances[containerId] = chart;
}

export function switchKpiChart(cardId, chartType) {
    const meta = window._kpiCardMeta?.[cardId];
    if (!meta) return;

    const chartContainer = document.getElementById(`${cardId}_chart`);
    if (chartContainer) chartContainer.style.display = 'block';

    // Update active button
    document.querySelectorAll(`[onclick*="switchKpiChart('${cardId}'"]`).forEach(btn => {
        btn.classList.toggle('active', btn.dataset.chart === chartType);
    });

    meta.activeChart = chartType;
    renderKpiChart(`${cardId}_chart`, chartType, meta.rows, meta.columns);
}

export function toggleKpiViz(cardId) {
    const vizBar      = document.getElementById(`${cardId}_vizbar`);
    const chartEl     = document.getElementById(`${cardId}_chart`);
    const toggleBtn   = document.getElementById(`${cardId}_vizToggle`);

    const isVisible = vizBar?.style.display === 'flex';
    if (vizBar) vizBar.style.display = isVisible ? 'none' : 'flex';
    if (!isVisible && chartEl) {
        chartEl.style.display = 'block';
        const meta = window._kpiCardMeta?.[cardId];
        if (meta && !meta.activeChart) {
            meta.activeChart = meta.defaultChart;
            renderKpiChart(`${cardId}_chart`, meta.defaultChart, meta.rows, meta.columns);
        }
    } else if (isVisible && chartEl) {
        chartEl.style.display = 'none';
    }

    if (toggleBtn) toggleBtn.classList.toggle('active', !isVisible);
}
