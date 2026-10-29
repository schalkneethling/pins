#!/usr/bin/env bash
# Usage: bash remote.sh <database-name> --remote|--local
# Runs the FTS5 spike against one D1 database, once per tokenizer, and prints
# every command with its JSON result. The database must be listed in
# wrangler.jsonc next to this script.
set -u
DB="$1"
LOC="$2"
W="npx wrangler@4.151.0"
mkdir -p exports
# Show which account the commands below will use.
if [ "$LOC" = "--remote" ]; then $W whoami; fi
run() { echo "\$ $*" | sed -E 's/a{40,}/a{...}/g'; "$@" 2>&1 | sed -E 's/a{40,}/a{...}/g'; echo; }
q() { run $W d1 execute "$DB" "$LOC" --json -y --command "$1"; }

COLS="title, domain, description, note, content = 'bookmarks', content_rowid = 'id'"
TRIGGERS="CREATE TRIGGER bookmarks_ai AFTER INSERT ON bookmarks BEGIN INSERT INTO bookmarks_fts (rowid, title, domain, description, note) VALUES (new.id, new.title, new.domain, new.description, new.note); END; CREATE TRIGGER bookmarks_ad AFTER DELETE ON bookmarks BEGIN INSERT INTO bookmarks_fts (bookmarks_fts, rowid, title, domain, description, note) VALUES ('delete', old.id, old.title, old.domain, old.description, old.note); END; CREATE TRIGGER bookmarks_au AFTER UPDATE OF title, domain, description, note ON bookmarks BEGIN INSERT INTO bookmarks_fts (bookmarks_fts, rowid, title, domain, description, note) VALUES ('delete', old.id, old.title, old.domain, old.description, old.note); INSERT INTO bookmarks_fts (rowid, title, domain, description, note) VALUES (new.id, new.title, new.domain, new.description, new.note); END;"
DROP_FTS="DROP TRIGGER IF EXISTS bookmarks_ai; DROP TRIGGER IF EXISTS bookmarks_ad; DROP TRIGGER IF EXISTS bookmarks_au; DROP TABLE IF EXISTS bookmarks_fts;"
RANK_OPTION="INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('rank', 'bm25(10.0, 4.0, 2.0, 6.0)');"
WEIGHTED="bm25(bookmarks_fts, 10.0, 4.0, 2.0, 6.0)"
READ_OPTION="SELECT v AS rank_option FROM bookmarks_fts_config WHERE k = 'rank';"
SEARCH="SELECT b.id, b.title, rank AS score FROM bookmarks_fts JOIN bookmarks AS b ON b.id = bookmarks_fts.rowid WHERE bookmarks_fts MATCH"
LONG="$(head -c 32768 /dev/zero | tr '\0' a)"

for TOKENIZE in "tokenize = 'porter unicode61'" "tokenize = 'trigram'" ""; do
  OPTS="$COLS${TOKENIZE:+, $TOKENIZE}"
  echo "######## tokenizer option: ${TOKENIZE:-(none, default unicode61)}"
  q "$DROP_FTS DROP TABLE IF EXISTS bookmarks;"
  # 1. Tokenizer acceptance.
  q "CREATE TABLE bookmarks (id INTEGER PRIMARY KEY, url TEXT NOT NULL UNIQUE, title TEXT NOT NULL, domain TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT ''); CREATE VIRTUAL TABLE bookmarks_fts USING fts5($OPTS); $RANK_OPTION $TRIGGERS"
  q "$READ_OPTION"
  # 2. 200 rows: SnapDOM plus 199 generated rows.
  q "INSERT INTO bookmarks (id, url, title, domain, description, note) VALUES (1, 'https://github.com/zumerlab/snapdom', 'SnapDOM', 'github.com', 'snapDOM is a fast and accurate DOM-to-image capture tool. It converts any HTML element into a scalable SVG image, preserving styles, fonts, background images and pseudo-elements.', '');"
  q "WITH RECURSIVE n(i) AS (SELECT 2 UNION ALL SELECT i + 1 FROM n WHERE i < 200) INSERT INTO bookmarks (id, url, title, domain, description, note) SELECT i, 'https://example.com/' || i, CASE i % 4 WHEN 0 THEN 'Notes on CSS grid' WHEN 1 THEN 'Understanding web components' WHEN 2 THEN 'Practical image formats' ELSE 'Debugging JavaScript modules' END, 'example.com', CASE i % 5 WHEN 0 THEN 'How the browser renders each element.' WHEN 1 THEN 'Styling components without leaking CSS.' WHEN 2 THEN 'Making files smaller for the web.' WHEN 3 THEN 'A comparison of popular tools.' ELSE 'Searching text quickly with an index.' END, CASE WHEN i % 3 = 0 THEN 'read later' ELSE '' END FROM n;"
  q "SELECT count(*) AS bookmarks FROM bookmarks;"
  # 3. Row accounting for the four operations at 200 rows.
  q "INSERT INTO bookmarks (id, url, title, domain, description, note) VALUES (201, 'https://example.com/new', 'Snap a DOM node to PNG', 'example.com', 'A new bookmark saved during the measurement.', '');"
  q "UPDATE bookmarks SET title = 'Snap a DOM node to an image', description = 'Updated description.' WHERE id = 201;"
  q "UPDATE bookmarks SET url = 'https://example.com/moved' WHERE id = 201;"
  q "DELETE FROM bookmarks WHERE id = 201;"
  # Same LIMIT for both orderings; the gate query uses LIMIT 6.
  q "$SEARCH '\"css\" \"web\" \"components\"*' ORDER BY rank LIMIT 6;"
  q "$SEARCH '\"css\" \"web\" \"components\"*' ORDER BY $WEIGHTED LIMIT 6;"
  q "$SEARCH '\"css\" OR \"web\" OR \"components\"*' ORDER BY rank LIMIT 100;"
  q "$SEARCH '\"css\" OR \"web\" OR \"components\"*' ORDER BY $WEIGHTED LIMIT 100;"
  # Does rank use the weights? Both columns must be equal on every row.
  q "SELECT bookmarks_fts.rowid AS id, rank AS rank_score, $WEIGHTED AS weighted_bm25 FROM bookmarks_fts WHERE bookmarks_fts MATCH '\"css\" OR \"web\" OR \"components\"*' ORDER BY rank LIMIT 5;"
  # 4. Acceptance queries.
  q "$SEARCH '\"NOT\" \"\"\"x\"\"\" \"title:y\"' ORDER BY rank LIMIT 50;"
  q "$SEARCH '\"snapd\"*' ORDER BY rank LIMIT 50;"
  # 5. Boundary: one 32,769-byte token, then a query that differs only in byte 32,769.
  q "INSERT INTO bookmarks (id, url, title, domain, description, note) VALUES (300, 'https://example.com/long', 'Long token row', 'example.com', 'boundary test', '${LONG}b');"
  q "SELECT count(*) AS same_first_32768_bytes FROM bookmarks_fts WHERE bookmarks_fts MATCH '\"${LONG}c\"';"
  q "DELETE FROM bookmarks WHERE id = 300;"
  # 6. Maintenance.
  q "INSERT INTO bookmarks_fts (bookmarks_fts) VALUES ('rebuild');"
  q "$READ_OPTION"
  q "INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('integrity-check', 1);"
  # 7. Export with the index present, then the sequence that should succeed.
  run $W d1 export "$DB" "$LOC" -y --output exports/with-index.sql
  run $W d1 export "$DB" "$LOC" -y --table bookmarks --output exports/bookmarks-table-only.sql
  q "$DROP_FTS"
  run $W d1 export "$DB" "$LOC" -y --output exports/without-index.sql
  q "CREATE VIRTUAL TABLE bookmarks_fts USING fts5($OPTS); $RANK_OPTION $TRIGGERS INSERT INTO bookmarks_fts (bookmarks_fts) VALUES ('rebuild');"
  q "$READ_OPTION"
  q "INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('integrity-check', 1);"
  q "$SEARCH '\"snapd\"*' ORDER BY rank LIMIT 50;"
done
