<?php
require __DIR__ . '/inc/layout.php';
$query = trim((string)($_GET['q'] ?? ''));
$results = [];
try {
    if (mb_strlen($query) >= 2) {
        // LIKE wildcards in the query are matched literally.
        $like = '%' . addcslashes($query, '\\%_') . '%';
        $find = db()->prepare(
            "SELECT 'Documentation' AS kind, CONCAT('docs.php?page=', slug) AS url, title, summary, body, (title LIKE ?) AS in_title FROM docs WHERE title LIKE ? OR body LIKE ? OR summary LIKE ?
             UNION ALL
             SELECT 'Tutorial', CONCAT('tutorials.php?t=', slug), title, summary, body, (title LIKE ?) FROM tutorials WHERE title LIKE ? OR body LIKE ? OR summary LIKE ?
             ORDER BY in_title DESC, title");
        $find->execute(array_fill(0, 8, $like));
        $results = $find->fetchAll();
    }
} catch (PDOException $error) { database_problem($error); exit; }

/** Text around the first match, with the match marked. */
function excerpt(string $body, string $query, string $fallback): string
{
    $plain = preg_replace('/\s+/', ' ', preg_replace('/[`#*|>]/', '', $body));
    $at = mb_stripos($plain, $query);
    if ($at === false) return e($fallback);
    $start = max(0, $at - 70);
    $text = ($start > 0 ? '…' : '') . mb_substr($plain, $start, 200) . '…';
    return preg_replace('/(' . preg_quote(e($query), '/') . ')/iu', '<mark>$1</mark>', e($text));
}
page_header($query === '' ? 'Search' : "Search: $query");
?>
<div class="container py-4" style="max-width: 52rem">
  <h1 class="mb-3">Search</h1>
  <form class="mb-4" action="search.php" method="get" role="search">
    <div class="input-group">
      <input class="form-control" type="search" name="q" value="<?= e($query) ?>" placeholder="Search docs and tutorials" aria-label="Search" autofocus>
      <button class="btn btn-primary" type="submit">Search</button>
    </div>
  </form>
<?php if ($query !== '' && mb_strlen($query) < 2): ?>
  <p class="text-secondary">Type at least two characters.</p>
<?php elseif ($query !== ''): ?>
  <p class="text-secondary"><?= count($results) ?> <?= count($results) === 1 ? 'result' : 'results' ?> for “<?= e($query) ?>”</p>
<?php foreach ($results as $result): ?>
  <div class="mb-4">
    <span class="badge badge-soft"><?= e($result['kind']) ?></span>
    <h2 class="h5 mt-1 mb-1"><a href="<?= e($result['url']) ?>"><?= e($result['title']) ?></a></h2>
    <p class="small text-secondary mb-0"><?= excerpt($result['body'], $query, $result['summary']) ?></p>
  </div>
<?php endforeach; ?>
<?php endif; ?>
</div>
<?php page_footer();
