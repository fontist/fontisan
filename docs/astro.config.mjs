import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Deployed at fontist.org/fontisan/ by the docs workflow.
const SITE_ORIGIN = process.env.SITE_URL || "https://www.fontist.org";
const SITE_PATH = process.env.BASE_PATH || "/fontisan/";

export default defineConfig({
  site: SITE_ORIGIN,
  base: SITE_PATH,
  trailingSlash: "ignore",
  output: "static",
  vite: {
    plugins: [tailwindcss()],
  },
});
