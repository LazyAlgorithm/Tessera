<?php
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/markdown.php';

function page_header(string $title, string $active = ''): void
{
    $links = ['docs' => ['docs.php', 'Documentation'], 'tutorials' => ['tutorials.php', 'Tutorials'], 'screenshots' => ['screenshots.php', 'Screenshots']];
    ?><!doctype html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?> · Tessera</title>
<link rel="icon" href="assets/icon.svg" type="image/svg+xml">
<link rel="alternate icon" href="assets/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="assets/icon-180.png">
<link href="assets/vendor/bootstrap.min.css" rel="stylesheet">
<link href="assets/vendor/highlight-dark.min.css" rel="stylesheet">
<link href="assets/css/site.css" rel="stylesheet">
</head>
<body class="d-flex flex-column min-vh-100">
<nav class="navbar navbar-expand-lg border-bottom sticky-top site-nav">
  <div class="container">
    <a class="navbar-brand fw-semibold" href="index.php"><img class="brand-mark" src="assets/icon.svg" width="26" height="26" alt="">Tessera</a>
    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nav" aria-controls="nav" aria-expanded="false" aria-label="Toggle navigation"><span class="navbar-toggler-icon"></span></button>
    <div class="collapse navbar-collapse" id="nav">
      <ul class="navbar-nav me-auto">
<?php foreach ($links as $key => [$href, $label]): ?>
        <li class="nav-item"><a class="nav-link<?= $key === $active ? ' active' : '' ?>" href="<?= $href ?>"<?= $key === $active ? ' aria-current="page"' : '' ?>><?= $label ?></a></li>
<?php endforeach; ?>
      </ul>
      <form class="d-flex" role="search" action="search.php" method="get">
        <input class="form-control form-control-sm" type="search" name="q" placeholder="Search docs and tutorials" aria-label="Search" value="<?= e($_GET['q'] ?? '') ?>">
      </form>
    </div>
  </div>
</nav>
<main class="flex-grow-1">
<?php
}

function page_footer(): void
{
    ?>
</main>
<footer class="border-top mt-5 py-4 small text-secondary">
  <div class="container d-flex flex-wrap justify-content-between gap-2">
    <span>Tessera, a 3D game engine and editor written in Beef.</span>
    <span><a class="link-secondary" href="docs.php">Docs</a> · <a class="link-secondary" href="tutorials.php">Tutorials</a> · <a class="link-secondary" href="screenshots.php">Screenshots</a></span>
  </div>
</footer>
<script src="assets/vendor/bootstrap.bundle.min.js"></script>
<script src="assets/vendor/highlight.min.js"></script>
<script>hljs.highlightAll();</script>
</body>
</html>
<?php
}

/** Shown instead of a page when the database is missing, with the command that creates it. */
function database_problem(Throwable $error): void
{
    http_response_code(503);
    page_header('Database not set up');
    ?>
<div class="container py-5" style="max-width: 46rem">
  <h1 class="h3">The site database is not set up yet</h1>
  <p>Start MySQL from the XAMPP control panel, then create and fill the database from the Tessera folder:</p>
  <pre><code class="language-bash">sudo website/setup.sh</code></pre>
  <p class="text-secondary small mb-0">Reported error: <?= e($error->getMessage()) ?></p>
</div>
<?php
    page_footer();
}
