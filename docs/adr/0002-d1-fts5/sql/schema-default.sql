CREATE TABLE bookmarks (
  id INTEGER PRIMARY KEY,
  url TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  domain TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT ''
);
CREATE VIRTUAL TABLE bookmarks_fts USING fts5(title, domain, description, note, content = 'bookmarks', content_rowid = 'id');
INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('rank', 'bm25(10.0, 4.0, 2.0, 6.0)');
CREATE TRIGGER bookmarks_ai AFTER INSERT ON bookmarks BEGIN
  INSERT INTO bookmarks_fts (rowid, title, domain, description, note)
  VALUES (new.id, new.title, new.domain, new.description, new.note);
END;
CREATE TRIGGER bookmarks_ad AFTER DELETE ON bookmarks BEGIN
  INSERT INTO bookmarks_fts (bookmarks_fts, rowid, title, domain, description, note)
  VALUES ('delete', old.id, old.title, old.domain, old.description, old.note);
END;
CREATE TRIGGER bookmarks_au AFTER UPDATE OF title, domain, description, note ON bookmarks BEGIN
  INSERT INTO bookmarks_fts (bookmarks_fts, rowid, title, domain, description, note)
  VALUES ('delete', old.id, old.title, old.domain, old.description, old.note);
  INSERT INTO bookmarks_fts (rowid, title, domain, description, note)
  VALUES (new.id, new.title, new.domain, new.description, new.note);
END;
