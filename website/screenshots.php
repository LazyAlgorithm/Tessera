<?php
require __DIR__ . '/inc/layout.php';
try {
    $shots = db()->query('SELECT file, title, caption FROM screenshots ORDER BY sort_order')->fetchAll();
} catch (PDOException $error) { database_problem($error); exit; }
page_header('Screenshots', 'screenshots');
?>
<div class="container py-4">
  <h1 class="mb-2">Screenshots</h1>
  <p class="text-secondary mb-4">Captured from the editor on Linux with the Vulkan backend. Select one to see it full size.</p>
  <div class="row g-4">
<?php foreach ($shots as $shot): ?>
    <div class="col-md-6 col-lg-4">
      <a class="shot" href="assets/screenshots/<?= e($shot['file']) ?>.jpg" data-bs-toggle="modal" data-bs-target="#viewer" data-title="<?= e($shot['title']) ?>" data-caption="<?= e($shot['caption']) ?>">
        <img src="assets/screenshots/<?= e($shot['file']) ?>-thumb.jpg" width="640" height="337" alt="<?= e($shot['title']) ?>">
      </a>
      <h2 class="h6 mt-3 mb-1"><?= e($shot['title']) ?></h2>
      <p class="small text-secondary mb-0"><?= e($shot['caption']) ?></p>
    </div>
<?php endforeach; ?>
  </div>
</div>
<div class="modal fade" id="viewer" tabindex="-1" aria-labelledby="viewer-title" aria-hidden="true">
  <div class="modal-dialog modal-xl modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header border-0 pb-2">
        <h2 class="modal-title h6" id="viewer-title"></h2>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body pt-0">
        <img id="viewer-image" class="img-fluid rounded border" src="" alt="">
        <p id="viewer-caption" class="small text-secondary mt-3 mb-0"></p>
      </div>
    </div>
  </div>
</div>
<script>
document.getElementById('viewer').addEventListener('show.bs.modal', function (event) {
  var link = event.relatedTarget;
  document.getElementById('viewer-title').textContent = link.dataset.title;
  document.getElementById('viewer-caption').textContent = link.dataset.caption;
  var image = document.getElementById('viewer-image');
  image.src = link.getAttribute('href');
  image.alt = link.dataset.title;
});
</script>
<?php page_footer();
