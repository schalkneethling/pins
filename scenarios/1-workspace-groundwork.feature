# Source: GitHub issue #1, "Groundwork: workspace layout, starter cleanup, ignore rules, and CI".
# These scenarios are not run by a Cucumber runner. They are the input to the red
# phase (the package tests under apps/*/test and packages/core/test cover the
# automatable ones) and a manual QA guide for the rest.
Feature: Workspace groundwork

  Scenario: Every gate checks something real
    Given a fresh clone
    When "vp install" and then "pnpm quality" run
    Then every step exits 0
    And "vp test" reports at least three test files, one per package
    And "vp test" does not report that no tests were found

  Scenario: Local-only files are ignored and Calavera state stays tracked
    Given the repository after "vp install"
    When "git status --ignored" runs
    Then ".calavera/cache" and ".wrangler" appear as ignored
    And ".calavera/state.json" does not appear as ignored

  Scenario: Core has no DOM library
    Given a scratch file under "packages/core/src" that reads "document.title"
    When "tsc -b" runs from the root
    Then type-checking fails with an error that names "document"
    # The scratch file is never committed.

  Scenario: A stray .dev.vars file fails CI
    Given a pull request that adds an empty "apps/site/.dev.vars" file
    When the "quality" job runs
    Then the job fails with a message that names the one-writer rule for secrets
    When the file is removed
    Then the job passes

  Scenario: The quality job runs every documented gate
    Given a pull request
    When the "quality" job runs
    Then it runs "pnpm quality", "vp -C apps/site build", and "vp -C apps/extension build"
    And all three exit 0

  Scenario: The workflow is least-privilege
    Given ".github/workflows/quality.yml"
    When it is read
    Then it sets "permissions: contents: read" only
    And it pins every action to a version tag
    And it references no repository secret

  Scenario: Starter files are gone
    Given the repository after the change
    Then "src/main.ts", "src/counter.ts", "src/style.css", "src/assets", and "public/icons.svg" do not exist
    And "knip" reports no unused files caused by their removal
