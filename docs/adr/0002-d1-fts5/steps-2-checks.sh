#!/usr/bin/env bash
# Step 2: acceptance checks, maintenance commands, boundary, and export through wrangler.
set -u
cd "$(dirname "$0")"
mkdir -p exports
run() { echo "\$ $*"; "$@" 2>&1 | grep -v "^$" | head -c 1200; echo; echo; }
SEARCH="SELECT b.id, b.title FROM bookmarks_fts JOIN bookmarks AS b ON b.id = bookmarks_fts.rowid WHERE bookmarks_fts MATCH"
ORDER="ORDER BY rank LIMIT 50"

for v in porter trigram default; do
  run npx wrangler d1 execute "fts-$v" --local --json --command "$SEARCH '\"NOT\" \"\"\"x\"\"\" \"title:y\"' $ORDER"
  run npx wrangler d1 execute "fts-$v" --local --json --command "$SEARCH '\"snapd\"*' $ORDER"
  run npx wrangler d1 execute "fts-$v" --local --json --command "$SEARCH '\"turn\" \"html\" \"into\" \"a\" \"picture\"*' $ORDER"
  run npx wrangler d1 execute "fts-$v" --local --json --command "$SEARCH '\"turn\" OR \"html\" OR \"into\" OR \"a\" OR \"picture\"*' $ORDER"
  run npx wrangler d1 execute "fts-$v" --local --json --command "INSERT INTO bookmarks_fts (bookmarks_fts) VALUES ('rebuild')"
  run npx wrangler d1 execute "fts-$v" --local --json --command "INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('integrity-check', 1)"
done

# Boundary: 32,769-byte token.
run npx wrangler d1 execute fts-porter --local --json --file sql/long-token.sql
run npx wrangler d1 execute fts-porter --local --json --command "SELECT id, length(note) AS note_bytes FROM bookmarks WHERE id = 300"
run npx wrangler d1 execute fts-porter --local --json --file sql/long-token-query.sql
run npx wrangler d1 execute fts-porter --local --json --command "DELETE FROM bookmarks WHERE id = 300"

# Export with the index present: expected to fail.
run npx wrangler d1 export fts-porter --local --output exports/with-index.sql
run npx wrangler d1 export fts-porter --local --no-data --output exports/with-index-schema.sql
run npx wrangler d1 export fts-porter --local --table bookmarks --output exports/with-index-bookmarks-only.sql

# Variant: drop only the virtual table, keep the triggers.
run npx wrangler d1 execute fts-default --local --json --command "DROP TABLE bookmarks_fts"
run npx wrangler d1 export fts-default --local --output exports/default-triggers-kept.sql
run npx wrangler d1 execute fts-default --local --json --command "INSERT INTO bookmarks (id, url, title, domain) VALUES (900, 'https://example.com/900', 'trigger check', 'example.com')"

# Sequence that succeeds: drop triggers and index, export, recreate, rebuild.
run npx wrangler d1 execute fts-porter --local --json --file sql/drop-fts.sql
run npx wrangler d1 export fts-porter --local --output exports/porter.sql
run npx wrangler d1 execute fts-porter --local --json --file sql/fts-porter.sql
run npx wrangler d1 execute fts-porter --local --json --command "INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('integrity-check', 1)"
run npx wrangler d1 execute fts-porter --local --json --command "SELECT v AS rank_option FROM bookmarks_fts_config WHERE k = 'rank'"
run npx wrangler d1 execute fts-porter --local --json --command "$SEARCH '\"snapd\"*' $ORDER"

# Restore the export into an empty database, then add the index.
run npx wrangler d1 execute fts-restore --local --json --file exports/porter.sql
run npx wrangler d1 execute fts-restore --local --json --file sql/fts-porter.sql
run npx wrangler d1 execute fts-restore --local --json --command "SELECT (SELECT count(*) FROM bookmarks) AS bookmarks, (SELECT count(*) FROM bookmarks_fts WHERE bookmarks_fts MATCH '\"snapd\"*') AS snapd_matches, (SELECT v FROM bookmarks_fts_config WHERE k = 'rank') AS rank_option"
