<?php
require __DIR__ . '/inc/layout.php';
try {
    $all = db()->query('SELECT slug, title, summary, difficulty, minutes FROM tutorials ORDER BY sort_order, title')->fetchAll();
    $slug = (string)($_GET['t'] ?? '');
    $tutorial = null;
    if ($slug !== '') {
        $find = db()->prepare('SELECT * FROM tutorials WHERE slug = ?');
        $find->execute([$slug]);
        $tutorial = $find->fetch();
        if (!$tutorial) http_response_code(404);
    }
} catch (PDOException $error) { database_problem($error); exit; }
page_header($tutorial ? $tutorial['title'] : 'Tutorials', 'tutorials');
?>
<div class="container py-4">
<?php if ($tutorial): $index = array_search($slug, array_column($all, 'slug'), true); ?>
  <article class="prose mx-auto">
    <p class="small mb-2"><a href="tutorials.php">&larr; All tutorials</a></p>
    <h1 class="mb-2"><?= e($tutorial['title']) ?></h1>
    <p class="text-secondary mb-2"><?= e($tutorial['summary']) ?></p>
    <p><span class="badge badge-soft"><?= e($tutorial['difficulty']) ?></span> <span class="badge badge-soft"><?= (int)$tutorial['minutes'] ?> min</span></p>
    <?= md_render($tutorial['body']) ?>
    <div class="d-flex justify-content-between border-top pt-3 mt-5 small">
      <span><?php if ($index > 0): ?><a href="tutorials.php?t=<?= e($all[$index - 1]['slug']) ?>">&larr; <?= e($all[$index - 1]['title']) ?></a><?php endif; ?></span>
      <span><?php if ($index + 1 < count($all)): ?><a href="tutorials.php?t=<?= e($all[$index + 1]['slug']) ?>"><?= e($all[$index + 1]['title']) ?> &rarr;</a><?php endif; ?></span>
    </div>
  </article>
<?php else: ?>
  <h1 class="mb-2"><?= $slug === '' ? 'Tutorials' : 'Tutorial not found' ?></h1>
  <p class="text-secondary mb-4">Step-by-step guides. Each one ends with something running in the editor.</p>
  <div class="row g-3">
<?php foreach ($all as $entry): ?>
    <div class="col-md-6 col-lg-4">
      <a class="card h-100" href="tutorials.php?t=<?= e($entry['slug']) ?>">
        <div class="card-body">
          <h2 class="h5 card-title"><?= e($entry['title']) ?></h2>
          <p class="card-text text-secondary"><?= e($entry['summary']) ?></p>
          <span class="badge badge-soft"><?= e($entry['difficulty']) ?></span> <span class="badge badge-soft"><?= (int)$entry['minutes'] ?> min</span>
        </div>
      </a>
    </div>
<?php endforeach; ?>
  </div>
<?php endif; ?>
</div>
<?php page_footer();
