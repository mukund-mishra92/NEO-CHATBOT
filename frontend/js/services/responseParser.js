/**
 * responseParser.js — Transforms raw API JSON into renderable HTML.
 *
 * This is the ONLY module that reads raw API response data.
 * All other components consume the output of formatMessage().
 */

import { convertMarkdownToHTML, extractSqlBlocks, formatSqlForDisplay, highlightSqlSyntax, sanitizeAssistantText, buildPageNumbers } from './markdownRenderer.js';
import { buildImageCard } from './imageHandler.js';
import { escapeHtml } from '../utils/helpers.js';

/* ── Shared paginated table state (global to allow inline onclick) ── */
if (!window.paginatedTables) window.paginatedTables = {};

/* ── Collapsible sections for long KB responses ── */
export function wrapCollapsibleSections(html) {
    const headingCount = (html.match(/<h[1-3][^>]*>/gi) || []).length;
    if (headingCount < 3) return html;

    return html.replace(
        /(<h[1-3][^>]*>)([\s\S]*?)(<\/h[1-3]>)([\s\S]*?)(?=<h[1-3][^>]*>|$)/gi,
        (match, openTag, headingContent, closeTag, body) => {
            if (!body.trim()) return match;
            const secId = 'sec_' + Math.random().toString(36).substr(2, 6);
            return `<div class="response-section" id="${secId}">
                <div class="response-section-toggle" onclick="this.parentElement.classList.toggle('collapsed')">
                    <i class="fas fa-chevron-down sec-chevron"></i>
                    ${openTag}${headingContent}${closeTag}
                </div>
                <div class="response-section-body">${body}</div>
            </div>`;
        }
    );
}

/* ── SQL expander blocks ── */
export function renderSqlExpanders(sqlBlocks) {
    if (!sqlBlocks || !sqlBlocks.length) return '';

    return sqlBlocks.map((sql, idx) => {
        const formatted = formatSqlForDisplay(sql);
        const highlighted = highlightSqlSyntax(formatted);
        const encodedSql = encodeURIComponent(sql).replace(/'/g, '%27');
        const label = sqlBlocks.length > 1 ? `Generated SQL ${idx + 1}` : 'Generated SQL';

        return `
            <details class="sql-expander">
                <summary>
                    <span class="sql-expander-label"><i class="fas fa-database"></i> ${label}</span>
                    <i class="fas fa-chevron-down sql-expander-chevron"></i>
                </summary>
                <div class="sql-expander-content">
                    <div class="sql-expander-actions">
                        <button class="sql-copy-btn" onclick="copySqlFromExpander(event,'${encodedSql}')" title="Copy SQL">
                            <i class="fas fa-copy"></i> Copy SQL
                        </button>
                    </div>
                    <pre class="sql-pretty-block"><code>${highlighted}</code></pre>
                </div>
            </details>`;
    }).join('');
}

/* ── Main message formatter ── */
export function formatMessage(content, data = {}, messageType = 'assistant') {
    const isAssistant  = messageType === 'assistant';
    const isSqlAssist  = isAssistant && (data?.chatbot_type === 'sql_assistant');
    const sanitized    = isAssistant ? sanitizeAssistantText(content) : (content || '');
    const extracted    = isSqlAssist ? extractSqlBlocks(sanitized) : { cleanedText: sanitized, sqlBlocks: [] };
    const uniqueSql    = isSqlAssist
        ? [...new Set([...extracted.sqlBlocks, ...(data.sql_query ? [data.sql_query] : [])])]
        : [];

    let html = convertMarkdownToHTML(extracted.cleanedText);

    // ── SQL assistant: strip redundant headings ──
    if (isSqlAssist) {
        html = html
            .replace(/<h[1-6][^>]*>\s*[🧾📜]?\s*SQL\s*Query\s*:?\s*<\/h[1-6]>/gi, '')
            .replace(/<strong[^>]*>\s*[🧾📜]?\s*SQL\s*Query\s*:?\s*<\/strong>/gi, '')
            .replace(/<strong[^>]*>\s*Confidence\s*:?\s*<\/strong>\s*\d+(?:\.\d+)?%?/gi, '')
            .replace(/(?:<br>\s*)*[🧾📜]?\s*SQL\s*Query\s*:?\s*(?:<br>\s*)*/gi, '<br>')
            .replace(/(?:<br>\s*)*Confidence\s*:\s*\d+(?:\.\d+)?%?(?:<br>\s*)*/gi, '<br>')
            .replace(/(?:<br>\s*){3,}/g, '<br><br>')
            .replace(/(?:<br>\s*){2,}/g, '<br>')
            .replace(/^(?:\s*<br>\s*)+/, '')
            .replace(/(?:\s*<br>\s*)+$/, '');
    }

    // ══════════════════════════════════════════════════╗
    // SQL ASSISTANT — two-column card layout            ║
    // ══════════════════════════════════════════════════╝
    if (isSqlAssist) {

        // ── KPI Disambiguation UI ──
        // When the backend is unsure between two KPIs, it returns
        // metadata.kpi_disambiguation with candidates for the user to pick.
        const disambig = data?.metadata?.kpi_disambiguation;
        if (disambig && disambig.candidates?.length >= 2) {
            const c1 = disambig.candidates[0];
            const c2 = disambig.candidates[1];
            const origQ = disambig.original_question || '';
            const disambigId = 'kpi_disambig_' + Math.random().toString(36).substr(2, 9);

            return `<div class="kpi-disambiguation-container" id="${disambigId}">
                <div class="kpi-disambig-header">
                    <i class="fas fa-question-circle"></i>
                    <span>${html || 'I found multiple matching KPIs. Please select the one you\'re looking for:'}</span>
                </div>
                <div class="kpi-disambig-options">
                    <button class="kpi-disambig-btn kpi-option-1"
                        onclick="handleKpiSelection('${disambigId}', '${c1.kpi_id}', '${escapeHtml(origQ).replace(/'/g, "\\'")}')">
                        <div class="kpi-option-label">
                            <i class="fas fa-chart-bar"></i>
                            <strong>${escapeHtml(c1.kpi_name)}</strong>
                        </div>
                        <div class="kpi-option-detail">${escapeHtml((c1.logic || '').substring(0, 120))}${(c1.logic || '').length > 120 ? '…' : ''}</div>
                        <span class="kpi-option-score">${(c1.score * 100).toFixed(0)}% match</span>
                    </button>
                    <button class="kpi-disambig-btn kpi-option-2"
                        onclick="handleKpiSelection('${disambigId}', '${c2.kpi_id}', '${escapeHtml(origQ).replace(/'/g, "\\'")}')">
                        <div class="kpi-option-label">
                            <i class="fas fa-chart-bar"></i>
                            <strong>${escapeHtml(c2.kpi_name)}</strong>
                        </div>
                        <div class="kpi-option-detail">${escapeHtml((c2.logic || '').substring(0, 120))}${(c2.logic || '').length > 120 ? '…' : ''}</div>
                        <span class="kpi-option-score">${(c2.score * 100).toFixed(0)}% match</span>
                    </button>
                    <button class="kpi-disambig-btn kpi-option-none"
                        onclick="handleKpiSelection('${disambigId}', 'none', '${escapeHtml(origQ).replace(/'/g, "\\'")}')">
                        <i class="fas fa-times-circle"></i>
                        <strong>None of these</strong>
                        <span class="kpi-option-hint">Generate custom SQL instead</span>
                    </button>
                </div>
                <div class="kpi-disambig-loading" id="${disambigId}_loading" style="display:none;">
                    <i class="fas fa-spinner fa-spin"></i> Processing your selection…
                </div>
            </div>`;
        }

        const cardId = 'sqlcard_' + Math.random().toString(36).substr(2, 9);

        let sqlConfidenceInline = '';
        if (data.confidence_score) {
            const pct   = (data.confidence_score * 100).toFixed(0);
            const cls   = pct >= 80 ? 'conf-high' : pct >= 50 ? 'conf-medium' : 'conf-low';
            sqlConfidenceInline = `<span class="sql-confidence-inline ${cls}"><i class="fas fa-shield-alt"></i> ${pct}%</span>`;
        }

        const primarySql = uniqueSql.length > 0 ? uniqueSql[0] : '';
        const primaryEncoded = primarySql ? encodeURIComponent(primarySql).replace(/'/g, '%27') : '';

        const sqlHeaderControls = primarySql ? `
            <div class="sql-toolbar sql-toolbar-header">
                ${sqlConfidenceInline}
                <button class="sql-tool-btn" onclick="copySqlFromExpander(event,'${primaryEncoded}')" title="Copy">
                    <span class="btn-tooltip">Copy</span><i class="fas fa-copy"></i>
                </button>
                <button class="sql-tool-btn" onclick="toggleSqlEdit(event,'${cardId}')" title="Edit">
                    <span class="btn-tooltip">Edit</span><i class="fas fa-pen"></i>
                </button>
                <button class="sql-tool-btn sql-execute-btn" onclick="executeSqlFromCard(event,'${cardId}')" title="Execute">
                    <span class="btn-tooltip">Run Query</span><i class="fas fa-play"></i> Run
                </button>
            </div>` : '';

        let sqlCardHtml = uniqueSql.map(sql => {
            const formatted    = formatSqlForDisplay(sql);
            const highlighted  = highlightSqlSyntax(formatted);
            const encoded      = encodeURIComponent(sql).replace(/'/g, '%27');
            return `
                <div class="sql-meta-block">
                    <div id="${cardId}_display">
                        <pre class="sql-pretty-block"><code>${highlighted}</code></pre>
                    </div>
                    <div id="${cardId}_editor" style="display:none;">
                        <textarea class="sql-edit-area" id="${cardId}_textarea">${escapeHtml(sql)}</textarea>
                    </div>
                    <input type="hidden" id="${cardId}_sql" value="${encoded}">
                </div>`;
        }).join('');

        // KPI chart
        const kpiMeta = data?.metadata?.dashboard_kpi;
        let kpiToggleHtml = '', kpiVizBarHtml = '', kpiChartHtml = '';
        if (kpiMeta && kpiMeta.source === 'dashboard_kpi') {
            const availableCharts = kpiMeta.available_chart_types || ['bar chart', 'pie', 'table', 'stat'];
            const defaultChart    = kpiMeta.chart_type || 'bar chart';
            const chartIcons      = { 'bar chart':'fa-chart-bar','pie':'fa-chart-pie','table':'fa-table','stat':'fa-hashtag','time series':'fa-chart-line','bar gauge':'fa-chart-bar','state timeline':'fa-stream' };
            const vizBtns = availableCharts.map(ct =>
                `<button class="kpi-viz-btn ${ct === defaultChart ? 'active' : ''}" data-chart="${ct}" onclick="switchKpiChart('${cardId}','${ct}')">
                    <i class="fas ${chartIcons[ct] || 'fa-chart-bar'}"></i> ${ct.replace(/^\w/, c => c.toUpperCase())}
                </button>`
            ).join('');

            kpiToggleHtml = `<button class="kpi-viz-toggle" id="${cardId}_vizToggle" onclick="toggleKpiViz('${cardId}')">
                <i class="fas fa-chart-pie"></i> Visualize
                <span class="kpi-badge"><i class="fas fa-database"></i> ${kpiMeta.category.replace(/^\w/, c => c.toUpperCase())} KPI</span>
            </button>`;

            kpiVizBarHtml = `<div class="kpi-viz-bar" id="${cardId}_vizbar">
                <span class="kpi-label"><i class="fas fa-chart-pie"></i> Chart type:</span>
                ${vizBtns}
            </div>`;

            kpiChartHtml = `<div class="kpi-chart-container" id="${cardId}_chart" style="height:300px;"></div>`;

            if (!window._kpiCardMeta) window._kpiCardMeta = {};
            window._kpiCardMeta[cardId] = {
                rows: data.query_results || [],
                columns: kpiMeta.columns || [],
                defaultChart,
            };
        }

        // Strip table artefacts from HTML before showing in data card
        const rowCountMatch = html.match(/Found\s+(\d+)\s+result/);
        const rowCountBadge = rowCountMatch ? `<span class="sql-rows-info"><i class="fas fa-table"></i> ${rowCountMatch[1]} rows</span>` : '';

        html = html
            .replace(/<br>\s*Rows\s+Returned\s*:\s*\d+\s*<br>/gi, '<br>')
            .replace(/Rows\s+Returned\s*:\s*\d+/gi, '')
            .replace(/(?:^|<br>\s*)(?:[\uFFFD]|📊)\s*(?=<br>|$)/gi, '$1');

        const tableStartMatch = html.match(/<div[^>]*class=["'][^"']*paginated-table-container[^"']*["'][\s\S]*$/i);
        if (tableStartMatch) html = tableStartMatch[0];

        html = html.replace(/^(?:\s*<br>\s*)+/i, '').replace(/(?:\s*<br>\s*)+$/i, '');

        const hasNoData = /No data found|0 rows returned|No rows returned/i.test(html) && !html.includes('paginated-table-container');
        if (hasNoData) {
            html = `<div class="sql-empty-state">
                <div class="sql-empty-icon"><i class="fas fa-database"></i></div>
                <div class="sql-empty-title">No Results Found</div>
                <div class="sql-empty-desc">The query executed successfully but returned no matching records.</div>
                <div class="sql-empty-hints">
                    <span class="sql-empty-hint"><i class="fas fa-filter"></i> Filters may be too narrow</span>
                    <span class="sql-empty-hint"><i class="fas fa-table"></i> Table may be empty</span>
                    <span class="sql-empty-hint"><i class="fas fa-sync-alt"></i> Try editing the query</span>
                </div>
            </div>`;
        }

        const sqlPanelToggle = uniqueSql.length > 0
            ? `<button class="sql-panel-toggle" id="${cardId}_toggle" onclick="toggleSqlPanel('${cardId}')" aria-expanded="false">
                   <i class="fas fa-code"></i> <span class="toggle-label">View SQL</span>
                   <i class="fas fa-chevron-right toggle-chevron"></i>
               </button>`
            : '';

        return `<div class="assistant-rich-response sql-assistant-response">
            <div class="sql-cards-layout sql-panel-collapsed" id="${cardId}_layout">
                <div class="sql-card sql-card-data" id="${cardId}_data">
                    <div class="sql-card-header">
                        <i class="fas fa-table"></i> Query Results ${rowCountBadge}
                        ${kpiToggleHtml}
                        <button class="sql-csv-download-btn" onclick="exportTableToCSV('${cardId}_dataBody')" title="Download CSV">
                            <i class="fas fa-download"></i> CSV
                        </button>
                        ${sqlPanelToggle}
                    </div>
                    ${kpiVizBarHtml}
                    <div class="sql-card-body" id="${cardId}_dataBody">${html}</div>
                    ${kpiChartHtml}
                </div>
                <div class="sql-right-column" id="${cardId}_sqlPanel">
                    ${sqlCardHtml ? `
                    <div class="sql-card sql-card-sql">
                        <div class="sql-card-header">${sqlHeaderControls}</div>
                        <div class="sql-card-body">${sqlCardHtml}</div>
                    </div>` : ''}
                </div>
            </div>
        </div>`;
    }

    // ══════════════════════════════════════════════════╗
    // NON-SQL ASSISTANT paths                           ║
    // ══════════════════════════════════════════════════╝

    // Confidence badge
    if (isAssistant && data.confidence_score) {
        const pct   = (data.confidence_score * 100).toFixed(0);
        const tier  = pct >= 75 ? 'conf-high' : pct >= 45 ? 'conf-medium' : 'conf-low';
        const icon  = pct >= 75 ? 'fa-check-circle' : pct >= 45 ? 'fa-exclamation-circle' : 'fa-question-circle';
        html += `<span class="confidence-badge ${tier}"><i class="fas ${icon}"></i> ${pct}% Confident</span>`;
    }

    // Source documents (deduplicated)
    if (isAssistant && data.source_documents?.length > 0) {
        const seen = new Set();
        const uniqueDocs = data.source_documents.filter(doc => {
            const name = (doc.filename || 'Document').toLowerCase();
            if (seen.has(name)) return false;
            seen.add(name);
            return true;
        });
        html += '<div class="source-tags-bar">';
        uniqueDocs.forEach(doc => {
            html += `<span class="source-tag"><i class="fas fa-file-alt"></i> ${doc.filename || 'Document'}</span>`;
        });
        html += '</div>';
    }

    // Images gallery
    if (isAssistant && data.images?.length > 0) {
        // Link "Figure N" text to scrollable cards
        const figureMap = {};
        data.images.forEach((img, idx) => {
            figureMap[idx + 1] = (img.image_path || '').replace(/^extracted_images\//, '');
        });

        html = html.replace(/\bFigure\s+(\d+)\b/gi, (match, num) => {
            const n = parseInt(num);
            if (n >= 1 && n <= data.images.length) {
                return `<a href="#rag-fig-${n}" class="figure-ref" onclick="document.getElementById('rag-fig-${n}')?.scrollIntoView({behavior:'smooth',block:'center'}); return false;">${match}</a>`;
            }
            return match;
        });

        const sr = data.structured_response;
        if (sr?.sections?.length > 0) {
            const figDataMap  = {};
            data.images.forEach((img, idx) => { figDataMap[idx + 1] = img; });
            const inlinedFigures = new Set();

            sr.sections.forEach(section => {
                if (!section.figures?.length) return;
                let inlineFigHtml = '<div class="rag-inline-figures" style="margin:6px 0;display:flex;flex-wrap:wrap;gap:8px;">';
                section.figures.forEach(figNum => {
                    const img = figDataMap[figNum];
                    if (!img) return;
                    inlinedFigures.add(figNum);
                    inlineFigHtml += buildImageCard(img, figNum, { compact: true });
                });
                inlineFigHtml += '</div>';

                if (section.heading) {
                    const escaped = section.heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    const pat = new RegExp(`(<(?:h[1-6]|strong)[^>]*>[^<]*${escaped}[^<]*<\/(?:h[1-6]|strong)>(?:\\s*<\\/?(?:br|p)[^>]*>)*)`, 'i');
                    const m   = html.match(pat);
                    if (m) {
                        const insertIdx = html.indexOf(m[0]) + m[0].length;
                        const after     = html.substring(insertIdx);
                        const nextBreak = after.match(/<\/(?:p|ul|ol|div|blockquote)>|<(?:h[1-6]|hr)[^>]*>/i);
                        if (nextBreak) {
                            const bi = insertIdx + nextBreak.index + nextBreak[0].length;
                            html = html.substring(0, bi) + inlineFigHtml + html.substring(bi);
                        } else {
                            html = html.substring(0, insertIdx) + inlineFigHtml + html.substring(insertIdx);
                        }
                    }
                }
            });

            const remaining = data.images.filter((_, idx) => !inlinedFigures.has(idx + 1));
            if (remaining.length > 0) {
                const gridClass = remaining.length <= 4 ? 'rag-image-grid compact-grid' : 'rag-image-grid';
                html += `<div class="rag-image-gallery">
                    <div class="rag-image-gallery-header"><i class="fas fa-images"></i> Additional Figures</div>
                    <div class="${gridClass}">${remaining.map(img => buildImageCard(img, data.images.indexOf(img) + 1)).join('')}</div>
                </div>`;
            }
        } else {
            if (data.images.length === 1) {
                html = `<div class="kb-text-with-image">
                    <div class="kb-text-col">${html}</div>
                    <div class="kb-image-col">${buildImageCard(data.images[0], 1)}</div>
                </div>`;
            } else {
                const gridClass = data.images.length <= 4 ? 'rag-image-grid compact-grid' : 'rag-image-grid';
                html += `<div class="rag-image-gallery">
                    <div class="rag-image-gallery-header"><i class="fas fa-images"></i> Figures</div>
                    <div class="${gridClass}">${data.images.map((img, idx) => buildImageCard(img, idx + 1)).join('')}</div>
                </div>`;
            }
        }
    }

    // Suggested actions
    if (isAssistant && data.suggested_actions?.length > 0) {
        html += '<div class="action-buttons">';
        data.suggested_actions.forEach(action => {
            html += `<button class="action-btn" onclick="executeSuggestedAction('${action.replace(/'/g, "\\'")}')">${action}</button>`;
        });
        html += '</div>';
    }

    // Collapsible sections for long KB answers
    if (isAssistant) html = wrapCollapsibleSections(html);

    // Wrap in surface div
    if (isAssistant) html = `<div class="assistant-rich-response">${html}</div>`;

    return html;
}
