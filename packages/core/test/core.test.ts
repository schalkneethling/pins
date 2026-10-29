import { describe, expect, it } from "vite-plus/test";

import tsconfig from "../tsconfig.json";

describe("@pins/core groundwork", () => {
  it("uses only the ES2023 library so it stays portable between Worker, browser, and extension", () => {
    expect(tsconfig.compilerOptions.lib).toEqual(["ES2023"]);
  });
});
