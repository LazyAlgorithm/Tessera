<?php
// Fills the database from content/manifest.php. Run from the command line:
//     /opt/lampp/bin/php website/db/import.php
// It replaces all docs, tutorials and screenshots, so edit the Markdown and run it again to publish changes.
if (PHP_SAPI !== 'cli') { http_response_code(403); exit("Run this from the command line.\n"); }
$site = dirname(__DIR__);
require $site . '/inc/db.php';

function read_source(string $site, array $entry): string
{
    $path = $site . '/' . $entry['file'];
    $text = @file_get_contents($path);
    if ($text === false) throw new RuntimeException("Cannot read $path");
    $text = str_replace("\r\n", "\n", $text);
    if (isset($entry['section'])) {
        // One "## Section" of a larger file, up to the next "## " heading. Headings inside code fences do not count.
        $out = []; $inside = false; $fenced = false;
        foreach (explode("\n", $text) as $line) {
            if (str_starts_with($line, '```')) $fenced = !$fenced;
            if (!$fenced && str_starts_with($line, '## ')) { $inside = trim(substr($line, 3)) === $entry['section']; continue; }
            if ($inside) $out[] = $line;
        }
        if (!$out) throw new RuntimeException("No section '{$entry['section']}' in $path");
        return trim(implode("\n", $out)) . "\n";
    }
    // A whole file: its "# Title" line is replaced by the page title.
    return trim(preg_replace('/\A# .*\n/', '', $text)) . "\n";
}

$manifest = require $site . '/content/manifest.php';
$pdo = db();
$pdo->beginTransaction();
$pdo->exec('DELETE FROM docs');
$pdo->exec('DELETE FROM tutorials');
$pdo->exec('DELETE FROM screenshots');

$insert = $pdo->prepare('INSERT INTO docs (slug, title, category, summary, sort_order, body) VALUES (?, ?, ?, ?, ?, ?)');
foreach ($manifest['docs'] as $order => $entry)
    $insert->execute([$entry['slug'], $entry['title'], $entry['category'], $entry['summary'], $order, read_source($site, $entry)]);

$insert = $pdo->prepare('INSERT INTO tutorials (slug, title, summary, difficulty, minutes, sort_order, body) VALUES (?, ?, ?, ?, ?, ?, ?)');
$tutorials = 0;
foreach (glob($site . '/content/tutorials/*.md') as $path) {
    $text = str_replace("\r\n", "\n", file_get_contents($path));
    if (!preg_match('/\A---\n(.*?)\n---\n(.*)\z/s', $text, $m)) throw new RuntimeException("$path has no front matter");
    $meta = [];
    foreach (explode("\n", $m[1]) as $line) {
        [$key, $value] = array_map('trim', explode(':', $line, 2));
        $meta[$key] = $value;
    }
    $insert->execute([basename($path, '.md'), $meta['title'], $meta['summary'] ?? '', $meta['difficulty'] ?? 'Beginner', (int)($meta['minutes'] ?? 10), (int)($meta['order'] ?? 0), trim($m[2]) . "\n"]);
    $tutorials++;
}

$insert = $pdo->prepare('INSERT INTO screenshots (file, title, caption, sort_order) VALUES (?, ?, ?, ?)');
foreach ($manifest['screenshots'] as $order => $entry) {
    if (!is_file("$site/assets/screenshots/{$entry['file']}.jpg")) throw new RuntimeException("Missing screenshot {$entry['file']}.jpg");
    $insert->execute([$entry['file'], $entry['title'], $entry['caption'], $order]);
}
$pdo->commit();
printf("Imported %d docs, %d tutorials, %d screenshots.\n", count($manifest['docs']), $tutorials, count($manifest['screenshots']));
