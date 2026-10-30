# Issue #4: Spike: D1 FTS5 behaviour, tokenizers, row accounting, and query choice.
#
# This file is a manual guide, not an automated test. The spike measures how
# D1 behaves, locally through `wrangler d1 execute --local` and remotely against
# a scratch database in the owner's Cloudflare account. Those runs need a
# throwaway directory, a wrangler login for the remote half, and a person who
# reads the numbers and records them in docs/adr/0002-d1-fts5.md. There is no
# application code to test yet, so a Cucumber runner would have nothing to
# call. Issue #8 turns the decisions recorded here into automated tests.
#
# The SQL, the results, and the wrangler step scripts are in
# docs/adr/0002-d1-fts5/. The ADR
# (architecture decision record) lists the full commands, the script for the
# remote half, and the results.

Feature: D1 FTS5 behaviour for bookmark search

  Background:
    Given a copy of docs/adr/0002-d1-fts5 outside the repository with wrangler 4.151.0 installed
    And its wrangler.jsonc declares the local databases "fts-porter", "fts-trigram", and "fts-default"
    And a "bookmarks" table with the external content index "bookmarks_fts" over title, domain, description, and note
    And the rank option "bm25(10.0, 4.0, 2.0, 6.0)" set on the index
    And the three triggers that keep the index in step with the table, the update trigger limited to the indexed columns
    And 200 synthetic bookmarks, including one titled "SnapDOM"

  Scenario Outline: D1 accepts the tokenizer and the rank option
    When "CREATE VIRTUAL TABLE bookmarks_fts USING fts5(title, domain, description, note, content = 'bookmarks', content_rowid = 'id'<tokenize>)" runs with "--local"
    And "INSERT INTO bookmarks_fts (bookmarks_fts, rank) VALUES ('rank', 'bm25(10.0, 4.0, 2.0, 6.0)')" runs after it
    And both statements run with "--remote"
    Then the ADR records whether each location accepted each statement

    Examples:
      | tokenize                           |
      | , tokenize = 'porter unicode61'    |
      | , tokenize = 'trigram'             |
      | (no tokenize option, the default)  |

  Scenario: The rank column uses the column weights
    When every sample query runs as a strict and a loose query, once ordered by rank and once by "bm25(bookmarks_fts, 10.0, 4.0, 2.0, 6.0)"
    Then both orderings return the same rows in the same order with the same scores
    And the same holds after "INSERT INTO bookmarks_fts (bookmarks_fts) VALUES ('rebuild')"

  Scenario: Dropping the index erases the rank option
    When the index is dropped and recreated without setting the rank option
    Then "SELECT v FROM bookmarks_fts_config WHERE k = 'rank'" returns no row
    And ordering by rank matches unweighted "bm25(bookmarks_fts)" instead of the weighted one

  Scenario: The score is negative and lower is better
    When the loose query for "css container queries" runs ordered by rank
    Then every score is negative and the first row has the most negative score
    And dividing each score by the first row's score gives 1 for the first row and less than 1 for the others

  Scenario: Row accounting for the four operations at 200 rows
    When an insert, an update, a delete, and a three-word MATCH ordered by rank and by bm25() at the same LIMIT each run once
    Then the ADR tabulates meta.rows_read and meta.rows_written for each operation
    And the ADR states the daily free-plan budget those numbers imply for 100 searches and 50 saves, marked as a local floor
    And the ADR says which local numbers can stand in for remote billing and which cannot

  Scenario: An update that changes only the URL does not touch the index
    When "UPDATE bookmarks SET url = 'https://example.com/moved' WHERE id = 201" runs
    Then meta.rows_written is 2, for the table row and the url index
    And the index still finds the bookmark by its title

  Scenario: The quoting function neutralises FTS5 operators
    Given the input 'NOT "x" title:y'
    When the quoting function runs
    Then the MATCH string is '"NOT" """x""" "title:y"'
    And the query returns without an error

  Scenario Outline: Awkward input never reaches FTS5 as syntax
    Given the input <input>
    When the strict and the loose builders run and their MATCH strings are bound with "MATCH ?"
    Then no query raises an error, and an input without tokens sends no query at all

    Examples:
      | input                  |
      | a"b                    |
      | NOT                    |
      | title:x                |
      | "                      |
      | -                      |
      | *                      |
      | café                   |
      | 日本語                 |
      | (an empty string)      |
      | (only spaces)          |
      | (300 words)            |

  Scenario: A punctuation-only token is dropped instead of silently weakening the strict query
    Given the input "snapdom -"
    When the strict builder runs
    Then the MATCH string is '"snapdom"*'

  Scenario Outline: The last token becomes a prefix only when it has at least three letters or digits
    Given the input <input>
    When the strict builder runs
    Then the MATCH string is <match>

    Examples:
      | input   | match            |
      | snapd   | "snapd"*         |
      | c++     | "c++"            |
      | css c   | "css" "c"        |
      | a"b     | "a""b"           |

  Scenario: A prefix query finds a bookmark by the start of its name
    Given a bookmark titled "SnapDOM"
    When the prefix query '"snapd"*' runs
    Then the bookmark is returned

  Scenario: Boundary at the maximum token length
    When a bookmark whose note is one 32,769-byte token is inserted
    Then the insert succeeds, or the ADR records the error
    And a query that differs from the token only in byte 32,769 shows whether FTS5 truncated the token silently

  Scenario: Export refuses a database with a virtual table
    When "wrangler d1 export" runs against a database that contains "bookmarks_fts"
    Then the ADR records the error text
    And the ADR records the drop, export, recreate, and rebuild sequence that succeeded
    And the recreate step sets the rank option again, and reading it back returns "bm25(10.0, 4.0, 2.0, 6.0)"

  Scenario: Strict and loose queries on the sample queries
    Given at least ten natural-language queries and at least five name queries, each with the bookmark it is meant to find
    When the strict query (tokens joined with a space) and the loose query (tokens joined with OR) run, both ordered by rank
    Then the ADR shows each query's strict result count, whether the intended bookmark is in the strict results, and whether it is in the loose top five
    And the ADR shows which loose top fives the column weights changed
    And the ADR states how often a strict count between 1 and 5 contained the intended bookmark, and how weak that evidence is

  Scenario: The strict gate query needs only six rows
    Given the strict query for "make images smaller", which has 7 matches
    When the gate query runs with LIMIT 6
    Then it returns 6 rows, which reads as more than 5 and falls through to the full search

  Scenario: Zero strict results must fall through to the full search
    Given the bookmark "SnapDOM"
    When the strict and the loose queries run for "turn html into a picture"
    Then the ADR records whether the strict query returns zero results and whether the loose query finds SnapDOM

  Scenario: Every documented command was run once
    When the pull request is opened
    Then it lists every command the ADR documents, each noted as run once by the implementer or as pending for the owner
