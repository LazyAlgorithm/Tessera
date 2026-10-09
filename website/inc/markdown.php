<?php
/**
 * Small Markdown renderer for the site's own content: headings, paragraphs, fenced code, bullet and numbered
 * lists, tables, block quotes, and inline code, bold, italics, links and images. All source text is escaped, so raw
 * HTML in a document is shown rather than run.
 */
function md_inline(string $text): string
{
    $codes = [];
    $text = preg_replace_callback('/`([^`]+)`/', function ($m) use (&$codes) {
        $codes[] = '<code>' . e($m[1]) . '</code>';
        return "\x01" . (count($codes) - 1) . "\x02";
    }, $text);
    $text = e($text);
    $text = preg_replace_callback('/!\[([^\]]*)\]\(([a-z0-9_\-.\/]+)\)/i', fn($m) => '<span class="shot my-3"><img src="' . $m[2] . '" alt="' . $m[1] . '"></span>', $text);
    $text = preg_replace_callback('/\[([^\]]+)\]\(([^)\s]+)\)/', function ($m) {
        $url = html_entity_decode($m[2], ENT_QUOTES);
        if (!preg_match('#^(https?://|/|\?|[a-z0-9_\-./]+(\?|$|\#))#i', $url)) return $m[0];
        return '<a href="' . e($url) . '">' . $m[1] . '</a>';
    }, $text);
    $text = preg_replace('/\*\*([^*]+)\*\*/', '<strong>$1</strong>', $text);
    $text = preg_replace('/(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])/', '<em>$1</em>', $text);
    return preg_replace_callback('/\x01(\d+)\x02/', fn($m) => $codes[(int)$m[1]], $text);
}

function md_slug(string $text): string
{
    return trim(preg_replace('/[^a-z0-9]+/', '-', strtolower($text)), '-');
}

function md_render(string $source): string
{
    $lines = preg_split('/\r?\n/', $source);
    $html = '';
    $count = count($lines);
    $i = 0;
    $cells = fn(string $row) => array_map('trim', explode('|', trim(trim($row), '|')));
    while ($i < $count) {
        $line = $lines[$i];
        if (trim($line) === '') { $i++; continue; }
        if (preg_match('/^```\s*([A-Za-z0-9_+-]*)/', $line, $m)) {
            // Beef has no highlighter of its own; C# rules are the closest match.
            $language = ['beef' => 'csharp', 'sh' => 'bash', '' => 'plaintext'][$m[1]] ?? $m[1];
            $code = [];
            for ($i++; $i < $count && !preg_match('/^```\s*$/', $lines[$i]); $i++) $code[] = $lines[$i];
            $i++;
            $html .= '<pre><code class="language-' . e($language) . '">' . e(implode("\n", $code)) . "</code></pre>\n";
            continue;
        }
        if (preg_match('/^(#{1,4})\s+(.*)$/', $line, $m)) {
            $level = strlen($m[1]) + 1; // the page title is the h1
            $html .= "<h$level id=\"" . e(md_slug($m[2])) . '">' . md_inline($m[2]) . "</h$level>\n";
            $i++;
            continue;
        }
        if (str_starts_with(trim($line), '|') && $i + 1 < $count && preg_match('/^\s*\|?[\s:|-]+\|[\s:|-]*$/', $lines[$i + 1])) {
            $html .= '<div class="table-responsive"><table class="table table-sm align-top"><thead><tr>';
            foreach ($cells($line) as $cell) $html .= '<th>' . md_inline($cell) . '</th>';
            $html .= "</tr></thead><tbody>\n";
            for ($i += 2; $i < $count && str_starts_with(trim($lines[$i]), '|'); $i++) {
                $html .= '<tr>';
                foreach ($cells($lines[$i]) as $cell) $html .= '<td>' . md_inline($cell) . '</td>';
                $html .= "</tr>\n";
            }
            $html .= "</tbody></table></div>\n";
            continue;
        }
        if (preg_match('/^\s*([-*]|\d+\.)\s+/', $line, $m)) {
            $tag = ctype_digit($m[1][0]) ? 'ol' : 'ul';
            $pattern = $tag === 'ol' ? '/^\s*\d+\.\s+(.*)$/' : '/^\s*[-*]\s+(.*)$/';
            $html .= "<$tag>\n";
            while ($i < $count && preg_match($pattern, $lines[$i], $item)) {
                $text = $item[1];
                // Indented lines under an item continue it.
                for ($i++; $i < $count && preg_match('/^\s{2,}\S/', $lines[$i]) && !preg_match('/^\s*([-*]|\d+\.)\s+/', $lines[$i]); $i++) $text .= ' ' . trim($lines[$i]);
                $html .= '<li>' . md_inline($text) . "</li>\n";
            }
            $html .= "</$tag>\n";
            continue;
        }
        if (str_starts_with($line, '>')) {
            $quote = [];
            for (; $i < $count && str_starts_with($lines[$i], '>'); $i++) $quote[] = ltrim(substr($lines[$i], 1));
            $html .= '<blockquote class="note">' . md_inline(implode(' ', $quote)) . "</blockquote>\n";
            continue;
        }
        $paragraph = [];
        for (; $i < $count && trim($lines[$i]) !== '' && !preg_match('/^(```|#{1,4}\s|>|\s*([-*]|\d+\.)\s+)/', $lines[$i]) && !(str_starts_with(trim($lines[$i]), '|') && $paragraph); $i++) $paragraph[] = trim($lines[$i]);
        if (!$paragraph) { $paragraph[] = trim($lines[$i]); $i++; }
        $html .= '<p>' . md_inline(implode(' ', $paragraph)) . "</p>\n";
    }
    return $html;
}
