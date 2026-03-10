import { defineConfig } from "vitepress";

// https://vitepress.dev/reference/site-config
export default defineConfig({
  lang: "en-US",

  // https://vitepress.dev/guide/routing#generating-clean-url
  cleanUrls: true,

  title: "Fontisan",
  description:
    "The most comprehensive font processing library for Ruby — 100% Pure Ruby, no Python, no C++, no C# dependencies.",

  lastUpdated: true,

  // Base path for deployment (e.g., /fontisan/ for fontist.org/fontisan/)
  base: process.env.BASE_PATH || "/fontisan/",

  head: [
    [
      "link",
      { rel: "icon", type: "image/png", href: "/favicon-96x96.png", sizes: "96x96" },
    ],
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],
    ["link", { rel: "shortcut icon", href: "/favicon.ico" }],
    [
      "link",
      { rel: "apple-touch-icon", sizes: "180x180", href: "/apple-touch-icon.png" },
    ],
    ["link", { rel: "manifest", href: "/site.webmanifest" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "Fontisan" }],
    [
      "meta",
      {
        property: "og:description",
        content:
          "The most comprehensive font processing library for Ruby — 100% Pure Ruby.",
      },
    ],
    ["meta", { property: "og:image", content: "/logo-full.svg" }],
    ["meta", { name: "twitter:card", content: "summary_large_image" }],
  ],

  // https://vitepress.dev/reference/default-theme-config
  themeConfig: {
    logo: "/logo-full.svg",
    siteTitle: false,

    // Local search with MiniSearch
    search: {
      provider: "local",
      options: {
        detailedView: true,
        miniSearch: {
          searchOptions: {
            fuzzy: 0.2,
            prefix: true,
            boost: { title: 4, text: 2, titles: 1 },
          },
        },
      },
    },

    // Top navigation (minimal: 4 items)
    nav: [
      { text: "← Fontist.org", link: "https://www.fontist.org" },
      { text: "Guide", link: "/guide/" },
      { text: "CLI", link: "/cli/" },
      { text: "API", link: "/api/" },
      { text: "Fontist", link: "https://www.fontist.org/fontist/", target: "_self" },
      { text: "Formulas", link: "https://www.fontist.org/formulas/", target: "_self" },
    ],

    // Sidebar configuration
    sidebar: {
      "/guide/": [
        {
          text: "Getting Started",
          items: [
            { text: "Introduction", link: "/guide/" },
            { text: "Installation", link: "/guide/installation" },
            { text: "Quick Start", link: "/guide/quick-start" },
          ],
        },
        {
          text: "CLI Reference",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/cli/" },
            { text: "convert", link: "/guide/cli/convert" },
            { text: "info", link: "/guide/cli/info" },
            { text: "validate", link: "/guide/cli/validate" },
            { text: "subset", link: "/guide/cli/subset" },
            { text: "pack/unpack", link: "/guide/cli/pack" },
            { text: "export", link: "/guide/cli/export" },
          ],
        },
        {
          text: "Font Formats",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/formats/" },
            { text: "TrueType (TTF)", link: "/guide/formats/ttf" },
            { text: "OpenType (OTF)", link: "/guide/formats/otf" },
            { text: "Type 1 (PFB/PFA)", link: "/guide/formats/type1" },
            { text: "WOFF & WOFF2", link: "/guide/formats/woff" },
            { text: "Collections (TTC/OTC)", link: "/guide/formats/collections" },
            { text: "Apple dfont", link: "/guide/formats/dfont" },
            { text: "SVG Fonts", link: "/guide/formats/svg" },
          ],
        },
        {
          text: "Conversion Guide",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/conversion/" },
            { text: "TTF ↔ OTF", link: "/guide/conversion/ttf-otf" },
            { text: "Type 1 → Modern", link: "/guide/conversion/type1" },
            { text: "Web Formats", link: "/guide/conversion/web" },
            { text: "Collections", link: "/guide/conversion/collections" },
            { text: "Curve Conversion", link: "/guide/conversion/curves" },
            { text: "Options Reference", link: "/guide/conversion/options" },
          ],
        },
        {
          text: "Validation",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/validation/" },
            { text: "Validation Profiles", link: "/guide/validation/profiles" },
            { text: "Validation Helpers", link: "/guide/validation/helpers" },
            { text: "Custom Validators", link: "/guide/validation/custom" },
          ],
        },
        {
          text: "Variable Fonts",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/variable-fonts/" },
            { text: "Axes & Instances", link: "/guide/variable-fonts/axes" },
            { text: "Instance Generation", link: "/guide/variable-fonts/instances" },
            { text: "Format Conversion", link: "/guide/variable-fonts/conversion" },
            { text: "Named Instances", link: "/guide/variable-fonts/named-instances" },
            { text: "Static Fonts", link: "/guide/variable-fonts/static" },
            { text: "Advanced Topics", link: "/guide/variable-fonts/advanced" },
          ],
        },
        {
          text: "Font Hinting",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/hinting/" },
            { text: "TrueType Hinting", link: "/guide/hinting/truetype" },
            { text: "PostScript Hinting", link: "/guide/hinting/postscript" },
            { text: "Hint Conversion", link: "/guide/hinting/conversion" },
            { text: "Autohint", link: "/guide/hinting/autohint" },
          ],
        },
        {
          text: "Color Fonts",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/color-fonts/" },
            { text: "COLR/CPAL", link: "/guide/color-fonts/colr-cpal" },
            { text: "sbix & CBDT", link: "/guide/color-fonts/bitmaps" },
            { text: "SVG Color", link: "/guide/color-fonts/svg" },
          ],
        },
        {
          text: "Migration Guides",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/migrations/" },
            { text: "From fonttools (Python)", link: "/guide/migrations/fonttools" },
            { text: "From extract_ttc", link: "/guide/migrations/extract-ttc" },
            { text: "From otfinfo", link: "/guide/migrations/otfinfo" },
            { text: "From Font-Validator", link: "/guide/migrations/font-validator" },
          ],
        },
        {
          text: "Feature Comparisons",
          collapsed: true,
          items: [
            { text: "Overview", link: "/guide/comparisons/" },
            { text: "vs fonttools", link: "/guide/comparisons/fonttools" },
            { text: "vs lcdf-typetools", link: "/guide/comparisons/lcdf-typetools" },
            { text: "vs Font-Validator", link: "/guide/comparisons/font-validator" },
          ],
        },
      ],
      "/cli/": [
        {
          text: "CLI Reference",
          items: [
            { text: "Overview", link: "/cli/" },
          ],
        },
        {
          text: "Font Information",
          collapsed: true,
          items: [
            { text: "info", link: "/cli/info" },
            { text: "ls", link: "/cli/ls" },
            { text: "tables", link: "/cli/tables" },
            { text: "glyphs", link: "/cli/glyphs" },
            { text: "unicode", link: "/cli/unicode" },
            { text: "scripts", link: "/cli/scripts" },
            { text: "features", link: "/cli/features" },
            { text: "variable", link: "/cli/variable" },
            { text: "optical-size", link: "/cli/optical-size" },
          ],
        },
        {
          text: "Font Operations",
          collapsed: true,
          items: [
            { text: "convert", link: "/cli/convert" },
            { text: "subset", link: "/cli/subset" },
            { text: "validate", link: "/cli/validate" },
            { text: "instance", link: "/cli/instance" },
            { text: "export", link: "/cli/export" },
            { text: "dump-table", link: "/cli/dump-table" },
          ],
        },
        {
          text: "Collection Operations",
          collapsed: true,
          items: [
            { text: "pack/unpack", link: "/cli/pack" },
          ],
        },
      ],
      "/api/": [
        {
          text: "API Reference",
          items: [
            { text: "Overview", link: "/api/" },
          ],
        },
        {
          text: "Core Classes",
          collapsed: true,
          items: [
            { text: "FontLoader", link: "/api/font-loader" },
            { text: "FontWriter", link: "/api/font-writer" },
            { text: "ConversionOptions", link: "/api/conversion-options" },
            { text: "SfntFont", link: "/api/sfnt-font" },
            { text: "Type1Font", link: "/api/type1-font" },
          ],
        },
        {
          text: "Converters",
          collapsed: true,
          items: [
            { text: "OutlineConverter", link: "/api/converters/outline-converter" },
            { text: "CurveConverter", link: "/api/converters/curve-converter" },
            { text: "HintConverter", link: "/api/converters/hint-converter" },
          ],
        },
        {
          text: "Validators",
          collapsed: true,
          items: [
            { text: "FontValidator", link: "/api/validators/font-validator" },
            { text: "ValidationProfile", link: "/api/validators/profile" },
            { text: "ValidationHelper", link: "/api/validators/helper" },
          ],
        },
        {
          text: "Models",
          collapsed: true,
          items: [
            { text: "Glyph", link: "/api/models/glyph" },
            { text: "GlyphAccessor", link: "/api/models/glyph-accessor" },
            { text: "TableAnalyzer", link: "/api/models/table-analyzer" },
          ],
        },
      ],
    },

    socialLinks: [
      { icon: "github", link: "https://github.com/fontist/fontisan" },
    ],

    footer: {
      message: 'Fontisan is a [Ribose](https://open.ribose.com/) project',
      copyright: `Copyright &copy; 2026 Ribose Group Inc. All rights reserved.`,
    },

    editLink: {
      pattern: "https://github.com/fontist/fontisan/edit/main/docs/:path",
      text: "Edit this page on GitHub",
    },
  },
});
