<?php
// Database settings. The defaults match a stock XAMPP install (user root, no password).
// Environment variables override them, which is how the import script and tests reach other servers.
return [
    'dsn'      => getenv('TESSERA_DB_DSN') ?: 'mysql:host=localhost;dbname=tessera_site;charset=utf8mb4',
    'user'     => getenv('TESSERA_DB_USER') ?: 'root',
    'password' => getenv('TESSERA_DB_PASSWORD') ?: '',
];
