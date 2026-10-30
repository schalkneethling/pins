import { defineConfig } from "vite-plus";

// Calavera writes these files and records a hash of each one. If the pre-commit
// hook (`vp check --fix`) reformats or lint-fixes them, the next Calavera apply
// refuses to overwrite them, because they no longer match what it installed
// (see schalkneethling/create-project-calavera#795). The list holds every file
// in `managedFiles` in `.calavera/state.json` that Oxfmt or Oxlint can read
// (`.editorconfig` and `.htmlvalidateignore` are file types both tools skip),
// plus `calavera.config.json` and `.calavera/**`, which Calavera also writes.
const calaveraManagedFiles = [
  "calavera.config.json",
  ".calavera/**",
  ".stylelintrc.json",
  ".htmlvalidate.json",
  "react-doctor.config.json",
  "knip.json",
  ".github/repository-controls.json",
  ".github/dependabot.yml",
  "docs/repository-controls.md",
  "scripts/lint-html.mjs",
  "scripts/repository-controls.mjs",
];

export default defineConfig({
  staged: {
    "*": "vp check --fix",
  },
  fmt: {
    // html-validate owns HTML style (uppercase doctype, no self-closing void
    // tags) and its Calavera-managed rules conflict with Oxfmt's HTML output.
    ignorePatterns: ["**/*.html", ...calaveraManagedFiles],
  },
  lint: {
    // Lint findings in Calavera's generated scripts can only be fixed in
    // Calavera, so they are reported upstream instead of failing this project.
    ignorePatterns: calaveraManagedFiles.filter((path) => path.endsWith(".mjs")),
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
});
