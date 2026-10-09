<?php
require __DIR__ . '/inc/layout.php';
try {
    $pages = db()->query('SELECT slug, title, category FROM docs ORDER BY sort_order, title')->fetchAll();
    $slug = (string)($_GET['page'] ?? ($pages[0]['slug'] ?? ''));
    $find = db()->prepare('SELECT * FROM docs WHERE slug = ?');
    $find->execute([$slug]);
    $page = $find->fetch();
} catch (PDOException $error) { database_problem($error); exit; }
if (!$page) http_response_code(404);
$index = array_search($slug, array_column($pages, 'slug'), true);
page_header($page ? $page['title'] : 'Page not found', 'docs');
?>
<div class="container py-4">
  <div class="row g-5">
    <aside class="col-lg-3">
      <nav class="sidebar" aria-label="Documentation pages">
<?php $category = null; foreach ($pages as $entry): if ($entry['category'] !== $category): $category = $entry['category']; ?>
        <p class="section-title mt-3 mb-1 px-2"><?= e($category) ?></p>
<?php endif; ?>
        <a class="nav-link<?= $entry['slug'] === $slug ? ' active' : '' ?>" href="docs.php?page=<?= e($entry['slug']) ?>"><?= e($entry['title']) ?></a>
<?php endforeach; ?>
      </nav>
    </aside>
    <article class="col-lg-9 prose">
<?php if ($page): ?>
      <p class="section-title mb-1"><?= e($page['category']) ?></p>
      <h1 class="mb-2"><?= e($page['title']) ?></h1>
      <p class="text-secondary"><?= e($page['summary']) ?></p>
      <?= md_render($page['body']) ?>
      <div class="d-flex justify-content-between border-top pt-3 mt-5 small">
        <span><?php if ($index > 0): ?><a href="docs.php?page=<?= e($pages[$index - 1]['slug']) ?>">&larr; <?= e($pages[$index - 1]['title']) ?></a><?php endif; ?></span>
        <span><?php if ($index !== false && $index + 1 < count($pages)): ?><a href="docs.php?page=<?= e($pages[$index + 1]['slug']) ?>"><?= e($pages[$index + 1]['title']) ?> &rarr;</a><?php endif; ?></span>
      </div>
<?php else: ?>
      <h1>Page not found</h1>
      <p>There is no documentation page called <code><?= e($slug) ?></code>. Pick one from the list.</p>
<?php endif; ?>
    </article>
  </div>
</div>
<?php page_footer();
