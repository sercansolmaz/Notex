// Tiny, dependency-free Markdown → HTML renderer.
// Covers the common cases for note-taking + Notex-specific links:
//   [[başlık]]  → wiki link (navigate by title)
//   {{uuid}}    → uuid link (navigate by id)

function esc(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function attr(s) {
  return s.replace(/"/g, '&quot;');
}

function inline(t) {
  t = esc(t);
  // inline code first so its contents aren't further processed
  t = t.replace(/`([^`]+)`/g, (_, c) => `<code>${c}</code>`);
  // links [text](url)
  t = t.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,
    (_, txt, url) => `<a href="${attr(url)}" target="_blank" rel="noopener">${txt}</a>`);
  // wiki link [[title]]
  t = t.replace(/\[\[([^\]]+)\]\]/g,
    (_, name) => `<a href="#" class="wikilink" data-link="${attr(name.trim())}">${name.trim()}</a>`);
  // uuid link {{uuid}}
  t = t.replace(/\{\{([^}]+)\}\}/g,
    (_, id) => `<a href="#" class="uuidlink" data-uuid="${attr(id.trim())}">↪ ${esc(id.trim().slice(0, 8))}</a>`);
  // bold, italic, strikethrough
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
  t = t.replace(/~~([^~]+)~~/g, '<del>$1</del>');
  return t;
}

// Best-effort HTML → Markdown, for when a note is switched from rich to markdown.
export function htmlToMarkdown(html) {
  const doc = new DOMParser().parseFromString(html || '', 'text/html');

  function listToMd(listNode, ordered) {
    let s = '';
    let i = 1;
    listNode.querySelectorAll(':scope > li').forEach((li) => {
      const prefix = ordered ? `${i++}. ` : '- ';
      s += prefix + walk(li).trim() + '\n';
    });
    return s;
  }

  function walk(node) {
    let out = '';
    node.childNodes.forEach((n) => {
      if (n.nodeType === 3) { out += n.textContent; return; }
      if (n.nodeType !== 1) return;
      const tag = n.tagName.toLowerCase();
      const inner = walk(n);
      switch (tag) {
        case 'h1': out += `# ${inner}\n\n`; break;
        case 'h2': out += `## ${inner}\n\n`; break;
        case 'h3': out += `### ${inner}\n\n`; break;
        case 'strong': case 'b': out += `**${inner}**`; break;
        case 'em': case 'i': out += `*${inner}*`; break;
        case 'strike': case 's': case 'del': out += `~~${inner}~~`; break;
        case 'u': out += inner; break;                       // no markdown underline
        case 'br': out += '\n'; break;
        case 'p': case 'div': out += `${inner}\n\n`; break;
        case 'blockquote': out += `> ${inner.trim().replace(/\n/g, '\n> ')}\n\n`; break;
        case 'pre': out += `\`\`\`\n${inner.replace(/\n$/, '')}\n\`\`\`\n\n`; break;
        case 'code': out += `\`${inner}\``; break;
        case 'a': out += `[${inner}](${n.getAttribute('href') || ''})`; break;
        case 'ul': out += listToMd(n, false) + '\n'; break;
        case 'ol': out += listToMd(n, true) + '\n'; break;
        default: out += inner;
      }
    });
    return out;
  }

  return walk(doc.body).replace(/\n{3,}/g, '\n\n').trim();
}

export function renderMarkdown(src) {
  const lines = (src || '').replace(/\r\n/g, '\n').split('\n');
  let html = '';
  let i = 0;
  let list = null; // 'ul' | 'ol'
  const closeList = () => { if (list) { html += `</${list}>`; list = null; } };

  while (i < lines.length) {
    const line = lines[i];

    // fenced code block
    if (/^```/.test(line)) {
      closeList();
      let code = '';
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) { code += lines[i] + '\n'; i++; }
      i++; // closing fence
      html += `<pre><code>${esc(code)}</code></pre>`;
      continue;
    }

    if (/^\s*$/.test(line)) { closeList(); i++; continue; }

    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) { closeList(); const n = h[1].length; html += `<h${n}>${inline(h[2])}</h${n}>`; i++; continue; }

    if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { closeList(); html += '<hr>'; i++; continue; }

    if (/^>\s?/.test(line)) {
      closeList();
      html += `<blockquote>${inline(line.replace(/^>\s?/, ''))}</blockquote>`;
      i++; continue;
    }

    // List items tolerate leading whitespace so indented (nested) items still
    // render as bullets/checkboxes (flattened — good enough for notes).
    const cb = line.match(/^\s*[-*]\s+\[([ xX])\]\s+(.*)$/);
    if (cb) {
      if (list !== 'ul') { closeList(); html += '<ul class="task-list">'; list = 'ul'; }
      const checked = cb[1].toLowerCase() === 'x' ? 'checked' : '';
      html += `<li class="task"><input type="checkbox" disabled ${checked}> ${inline(cb[2])}</li>`;
      i++; continue;
    }

    const ul = line.match(/^\s*[-*]\s+(.*)$/);
    if (ul) {
      if (list !== 'ul') { closeList(); html += '<ul>'; list = 'ul'; }
      html += `<li>${inline(ul[1])}</li>`; i++; continue;
    }

    const ol = line.match(/^\s*\d+\.\s+(.*)$/);
    if (ol) {
      if (list !== 'ol') { closeList(); html += '<ol>'; list = 'ol'; }
      html += `<li>${inline(ol[1])}</li>`; i++; continue;
    }

    closeList();
    html += `<p>${inline(line)}</p>`;
    i++;
  }
  closeList();
  return html;
}
