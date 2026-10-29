import { describe, expect, it } from "vite-plus/test";

import tsconfig from "../tsconfig.json";

describe("@pins/extension groundwork", () => {
  it("type-checks against the DOM library", () => {
    expect(tsconfig.compilerOptions.lib).toContain("DOM");
  });
});
