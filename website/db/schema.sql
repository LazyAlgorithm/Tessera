-- Tessera website database. Content is loaded by db/import.php from the Markdown in content/ and the
-- engine's own README and docs, so this file only defines structure.
CREATE DATABASE IF NOT EXISTS tessera_site CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE tessera_site;

CREATE TABLE IF NOT EXISTS docs (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(80) NOT NULL UNIQUE,
    title VARCHAR(160) NOT NULL,
    category VARCHAR(60) NOT NULL,
    summary VARCHAR(300) NOT NULL DEFAULT '',
    sort_order INT NOT NULL DEFAULT 0,
    body MEDIUMTEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY docs_order (sort_order)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tutorials (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(80) NOT NULL UNIQUE,
    title VARCHAR(160) NOT NULL,
    summary VARCHAR(300) NOT NULL DEFAULT '',
    difficulty VARCHAR(20) NOT NULL DEFAULT 'Beginner',
    minutes SMALLINT UNSIGNED NOT NULL DEFAULT 10,
    sort_order INT NOT NULL DEFAULT 0,
    body MEDIUMTEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY tutorials_order (sort_order)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS screenshots (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    file VARCHAR(120) NOT NULL UNIQUE,
    title VARCHAR(160) NOT NULL,
    caption VARCHAR(400) NOT NULL DEFAULT '',
    sort_order INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;
