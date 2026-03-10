import DefaultTheme from "vitepress/theme";
import type { Theme } from "vitepress";
import "./style.css";

// Import custom components
import FeatureComparison from "./components/FeatureComparison.vue";
import Badge from "./components/Badge.vue";
import ApiMethod from "./components/ApiMethod.vue";
import HeroCodeBlock from "./components/HeroCodeBlock.vue";
import WithinHero from "./components/WithinHero.vue";

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    // Register global components
    app.component("FeatureComparison", FeatureComparison);
    app.component("Badge", Badge);
    app.component("ApiMethod", ApiMethod);
    app.component("HeroCodeBlock", HeroCodeBlock);
    app.component("WithinHero", WithinHero);
  },
} satisfies Theme;
