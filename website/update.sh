#!/usr/bin/env bash
# Reloads the website's documentation and tutorials from the repository into the database. No sudo needed; XAMPP's
# MySQL must be running. Use setup.sh instead after changing the site's PHP, styles or images.
set -euo pipefail
site="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
lampp="${LAMPP:-/opt/lampp}"
if [ ! -S "$lampp/var/mysql/mysql.sock" ]; then echo "MySQL is not running. Start XAMPP first: sudo $lampp/lampp start" >&2; exit 1; fi
TESSERA_DB_DSN="mysql:unix_socket=$lampp/var/mysql/mysql.sock;dbname=tessera_site;charset=utf8mb4" "$lampp/bin/php" "$site/db/import.php"
