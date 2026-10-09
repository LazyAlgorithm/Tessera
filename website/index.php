<?php
require __DIR__ . '/inc/layout.php';
try {
    $tutorials = db()->query('SELECT slug, title, summary, difficulty, minutes FROM tutorials ORDER BY sort_order, title')->fetchAll();
    $shots = db()->query('SELECT file, title FROM screenshots ORDER BY sort_order LIMIT 3')->fetchAll();
    $docs = db()->query('SELECT slug, title, summary FROM docs ORDER BY sort_order LIMIT 6')->fetchAll();
} catch (PDOException $error) { database_problem($error); exit; }
$features = [
    ['Editor', 'Hierarchy, Scene and Game views, Inspector, Project browser, code editor and undo, in one window.'],
    ['Terrain and voxels', 'A flat terrain you sculpt like Unity\'s, endless generation when you want it, and destructible voxel objects.'],
    ['Materials and shaders', 'PBR materials with normal maps, a shader graph, surface shaders in code that keep the lighting, and compute shaders.'],
    ['Animator', 'Unity-style state machines and a clip timeline, watched live while the game runs.'],
    ['Voice chat', 'Players in a session can talk: open microphone or push to talk, proximity and team-only voice, all built in.'],
    ['3D audio', 'Audio sources and a listener with optional built-in HRTF for headphones, Doppler, occlusion behind walls and reverb zones.'],
    ['Visual scripting', 'Node graphs with a node for everything in the engine and in your scripts, compiled to ordinary Beef components.'],
    ['Navigation and AI', 'Baked walking surfaces and 3D flight volumes with A* path search, and behaviour trees you can watch run.'],
    ['Physics', 'Jolt rigid bodies and colliders, shape casts, and a character controller that walks up steps and slopes.'],
    ['Multiplayer', 'Ready when you want it: physics, AI, voxels and animation are shared automatically, over UDP or Steam.'],
];
page_header('3D game engine and editor');
?>
<section class="hero border-bottom">
  <div class="container">
    <h1>Tessera</h1>
    <p class="lead mt-3">A 3D game engine and editor written in Beef, aimed at low-poly games with voxel worlds and server-authoritative multiplayer.</p>
    <div class="d-flex flex-wrap gap-2 mt-4">
      <a class="btn btn-primary" href="docs.php?page=getting-started">Get started</a>
      <a class="btn btn-outline-light" href="tutorials.php">Tutorials</a>
      <a class="btn btn-outline-light" href="screenshots.php">Screenshots</a>
    </div>
<?php if ($shots): ?>
    <a class="shot mt-5" href="screenshots.php"><img src="assets/screenshots/<?= e($shots[0]['file']) ?>.jpg" width="1920" height="1012" alt="<?= e($shots[0]['title']) ?>"></a>
<?php endif; ?>
  </div>
</section>

<section class="container py-5">
  <p class="section-title mb-3">What is in it</p>
  <div class="row g-4">
<?php foreach ($features as [$name, $text]): ?>
    <div class="col-md-6 col-lg-4 feature"><h3><?= e($name) ?></h3><p><?= e($text) ?></p></div>
<?php endforeach; ?>
  </div>
</section>

<section class="container pb-5">
  <div class="d-flex justify-content-between align-items-baseline mb-3">
    <p class="section-title mb-0">Tutorials</p><a class="small" href="tutorials.php">All tutorials</a>
  </div>
  <div class="row g-3">
<?php foreach ($tutorials as $tutorial): ?>
    <div class="col-md-4">
      <a class="card h-100" href="tutorials.php?t=<?= e($tutorial['slug']) ?>">
        <div class="card-body">
          <h3 class="h6 card-title"><?= e($tutorial['title']) ?></h3>
          <p class="card-text small text-secondary"><?= e($tutorial['summary']) ?></p>
          <span class="badge badge-soft"><?= e($tutorial['difficulty']) ?></span> <span class="badge badge-soft"><?= (int)$tutorial['minutes'] ?> min</span>
        </div>
      </a>
    </div>
<?php endforeach; ?>
  </div>
</section>

<section class="container pb-5">
  <div class="row g-5">
    <div class="col-lg-5">
      <div class="d-flex justify-content-between align-items-baseline mb-3">
        <p class="section-title mb-0">Documentation</p><a class="small" href="docs.php">All pages</a>
      </div>
      <div class="list-group list-group-flush border rounded">
<?php foreach ($docs as $doc): ?>
        <a class="list-group-item list-group-item-action" href="docs.php?page=<?= e($doc['slug']) ?>"><span class="fw-semibold"><?= e($doc['title']) ?></span><br><span class="small text-secondary"><?= e($doc['summary']) ?></span></a>
<?php endforeach; ?>
      </div>
    </div>
    <div class="col-lg-7">
      <div class="d-flex justify-content-between align-items-baseline mb-3">
        <p class="section-title mb-0">Screenshots</p><a class="small" href="screenshots.php">Gallery</a>
      </div>
      <div class="row g-3">
<?php foreach (array_slice($shots, 1) as $shot): ?>
        <div class="col-sm-6"><a class="shot" href="screenshots.php"><img src="assets/screenshots/<?= e($shot['file']) ?>-thumb.jpg" width="640" height="337" loading="lazy" alt="<?= e($shot['title']) ?>"></a><p class="small text-secondary mt-2 mb-0"><?= e($shot['title']) ?></p></div>
<?php endforeach; ?>
      </div>
    </div>
  </div>
</section>
<?php page_footer();
