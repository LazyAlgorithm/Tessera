#!/usr/bin/env bash
# Installs the Tessera website into XAMPP: copies it to htdocs/tessera, creates the tessera_site database and
# loads the content. The first run needs sudo, because htdocs belongs to root:
#     sudo website/setup.sh
# That run hands htdocs/tessera to your user, so later runs (after changing pages or content) need no sudo:
#     website/setup.sh
# website/update.sh reloads only the documentation and tutorials, which is all a content change needs.
set -euo pipefail
site="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
lampp="${LAMPP:-/opt/lampp}"
target="$lampp/htdocs/tessera"

if [ ! -x "$lampp/bin/php" ]; then echo "XAMPP not found at $lampp (set LAMPP=/path/to/lampp)." >&2; exit 1; fi
if [ -d "$target" ] && [ ! -w "$target" ] || [ ! -d "$target" ] && [ ! -w "$lampp/htdocs" ]; then
	echo "Cannot write to $target; run this once with sudo." >&2; exit 1
fi
if [ ! -S "$lampp/var/mysql/mysql.sock" ]; then
	if [ "$(id -u)" != 0 ]; then echo "MySQL is not running. Start XAMPP first: sudo $lampp/lampp start" >&2; exit 1; fi
	echo "MySQL is not running; starting XAMPP..."
	"$lampp/lampp" start
	for _ in $(seq 30); do [ -S "$lampp/var/mysql/mysql.sock" ] && break; sleep 1; done
fi

mkdir -p "$target"
# The copy in htdocs is replaced each time, so edit the files here, not there.
rm -rf "$target/assets" "$target/inc" "$target/db" "$target/content"
cp -r "$site"/*.php "$site/assets" "$site/inc" "$site/db" "$site/content" "$target/"
chmod -R a+rX "$target"
# Later runs can then replace these files without sudo.
if [ -n "${SUDO_USER:-}" ]; then chown -R "$SUDO_USER" "$target"; fi

"$lampp/bin/mysql" -u root < "$site/db/schema.sql"
# Imported from this folder, because the docs are read from the repository's README and docs/.
TESSERA_DB_DSN="mysql:unix_socket=$lampp/var/mysql/mysql.sock;dbname=tessera_site;charset=utf8mb4" "$lampp/bin/php" "$site/db/import.php"
echo "Done: http://localhost/tessera/"
