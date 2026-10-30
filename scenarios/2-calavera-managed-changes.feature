# Issue #2: Calavera-managed changes, made only through Calavera.
#
# These scenarios are a manual QA guide, not an automated suite: they check
# what Calavera's MCP tools and CLI report, and the project has no Cucumber
# runner.

Feature: Calavera-managed tooling changes land only through Calavera

  Scenario: React Doctor is gone from the recipe and the quality gate
    Given the repository after this change
    When calavera.config.json, .calavera/state.json, and package.json are read
    Then no integration is named react-doctor
    And package.json has no react-doctor dependency and no react:doctor scripts
    And the quality script contains neither react:doctor nor --passWithNoTests

  Scenario: The quality gate still runs the tests
    Given each workspace package defines a test script that runs vp test
    When pnpm quality runs
    Then its test step runs vp run -r test
    And the step runs the test script of all three workspace packages, and each passes

  Scenario: The repository and the recipe agree
    Given the recipe in calavera.config.json
    When validate_recipe and then dry_run_apply run
    Then every file in the dry run is reported as unchanged
    And no package.json script would change

  Scenario: The pre-commit hook no longer rewrites Calavera's files
    Given a commit made with git commit, which runs vp staged and so vp check --fix on the staged files
    When dry_run_apply runs after the commit
    Then it still reports every managed file as unchanged

  Scenario: Changes Calavera cannot express are recorded, not hand-edited
    Given Calavera exposes no option for knip ignores, stylelint ignore files, or the Dependabot schedule
    When the managed files are compared with the dry-run output
    Then knip.json, .stylelintrc.json, and .github/dependabot.yml match what Calavera wrote
    And the gaps are recorded in schalkneethling/create-project-calavera#795 and its linked issues
