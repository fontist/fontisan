import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";

// Parity with the VitePress srcExclude: three standalone guide stubs collide
// with their richer directory routes (guide/<name>/index.md is canonical).
const guide = defineCollection({
  loader: glob({
    pattern: ["**/*.md", "!hinting.md", "!validation.md", "!conversion.md"],
    base: "./guide",
  }),
});

const cli = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./cli" }),
});

const api = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./api" }),
});

const history = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./history" }),
});

const rootPages = defineCollection({
  loader: glob({
    pattern: ["*.md", "!index.md", "!TODO.improve-docs.md"],
    base: "./",
  }),
});

export const collections = { guide, cli, api, history, rootPages };
