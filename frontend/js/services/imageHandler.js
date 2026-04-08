/**
 * imageHandler.js — Processes and builds HTML for RAG images.
 */

/**
 * Build HTML for one RAG image card.
 * @param {object} img     — { image_path, caption, source_document, page_number }
 * @param {number} figNum  — 1-based figure number
 * @param {object} [opts]  — { compact: boolean }
 */
export function buildImageCard(img, figNum, opts = {}) {
    const pathSuffix = (img.image_path || '').replace(/^extracted_images\//, '');
    const imgUrl = `/api/images/${pathSuffix}`;
    const caption = img.caption || img.source_document || '';
    const maxCaptLen = opts.compact ? 60 : 80;
    const shortCaption = caption.length > maxCaptLen ? caption.substring(0, maxCaptLen - 3) + '...' : caption;
    const pageInfo  = img.page_number ? `Page ${img.page_number}` : '';
    const sourceDoc = img.source_document || '';
    const tooltip   = [caption, pageInfo].filter(Boolean).join(' — ');

    const captionHtml = shortCaption
        ? `<div class="fig-caption">${shortCaption}</div>`
        : '';

    const metaHtml = (pageInfo || sourceDoc)
        ? `<div class="fig-meta">
               ${sourceDoc ? `<span class="fig-src"><i class="fas fa-file-alt"></i> ${sourceDoc}</span>` : ''}
               ${pageInfo  ? `<span class="fig-page">${pageInfo}</span>` : ''}
           </div>`
        : '';

    return `
        <div id="rag-fig-${figNum}" class="rag-image-card" title="${tooltip}" onclick="window.open('${imgUrl}','_blank')">
            <div style="position:relative;">
                <img src="${imgUrl}" alt="${caption}" loading="lazy" onerror="this.closest('.rag-image-card').style.display='none'">
                <span class="fig-badge">Figure ${figNum}</span>
            </div>
            ${captionHtml}
            ${metaHtml}
        </div>`;
}

/**
 * Resolve the public URL for an image path.
 */
export function resolveImageUrl(imagePath) {
    const pathSuffix = (imagePath || '').replace(/^extracted_images\//, '');
    return `/api/images/${pathSuffix}`;
}
