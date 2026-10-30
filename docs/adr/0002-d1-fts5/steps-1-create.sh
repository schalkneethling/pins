#!/usr/bin/env bash
# Step 1: create the three local databases, seed 200 rows, and read the schema back.
set -u
cd "$(dirname "$0")"
run() { echo "\$ $*"; "$@" 2>&1 | grep -v '^$'; echo; }
for v in porter trigram default; do
  run npx wrangler d1 execute "fts-$v" --local --file "sql/schema-$v.sql"
  run npx wrangler d1 execute "fts-$v" --local --file sql/seed.sql
  run npx wrangler d1 execute "fts-$v" --local --json --command "SELECT (SELECT count(*) FROM bookmarks) AS bookmarks, (SELECT sql FROM sqlite_schema WHERE name = 'bookmarks_fts') AS fts_sql, (SELECT v FROM bookmarks_fts_config WHERE k = 'rank') AS rank_option"
done
