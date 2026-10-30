import { defineConfig } from "vite-plus";

export default defineConfig({
  staged: {
    "*": "vp check --fix",
  },
  fmt: {
    // html-validate owns HTML style (uppercase doctype, no self-closing void
    // tags) and its Calavera-managed rules conflict with Oxfmt's HTML output.
    ignorePatterns: ["**/*.html"],
  },
  lint: {
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
});
