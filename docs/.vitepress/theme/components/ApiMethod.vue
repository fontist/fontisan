<template>
  <div class="api-method">
    <div class="method-header">
      <code class="method-signature">
        <span class="method-name">{{ name }}</span
        ><span class="method-params"
          >({{ params.map((p) => p.name).join(", ") }})</span
        >
      </code>
      <span v-if="returns" class="method-returns"> → {{ returns }}</span>
    </div>
    <p v-if="description" class="method-description">{{ description }}</p>
    <div v-if="params.length" class="method-params-list">
      <h4>Parameters</h4>
      <ul>
        <li v-for="param in params" :key="param.name">
          <code>{{ param.name }}</code>
          <span v-if="param.type" class="param-type">: {{ param.type }}</span>
          <span v-if="param.required" class="param-required">*</span>
          <span v-if="param.description" class="param-desc"
            >— {{ param.description }}</span
          >
        </li>
      </ul>
    </div>
    <div v-if="example" class="method-example">
      <h4>Example</h4>
      <pre><code :class="`language-${exampleLang}`">{{ example }}</code></pre>
    </div>
  </div>
</template>

<script setup lang="ts">
interface Param {
  name: string;
  type?: string;
  required?: boolean;
  description?: string;
}

defineProps<{
  name: string;
  params?: Param[];
  returns?: string;
  description?: string;
  example?: string;
  exampleLang?: string;
}>();
</script>

<style scoped>
.api-method {
  margin: 1.5rem 0;
  padding: 1rem;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background: var(--vp-c-bg-soft);
}

.method-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.method-signature {
  font-size: 1rem;
  font-weight: 500;
}

.method-name {
  color: var(--vp-c-brand-1);
}

.method-params {
  color: var(--vp-c-text-2);
}

.method-returns {
  color: var(--vp-c-text-2);
  font-size: 0.9rem;
}

.method-description {
  margin: 0.75rem 0 0;
  color: var(--vp-c-text-2);
}

.method-params-list h4,
.method-example h4 {
  margin: 1rem 0 0.5rem;
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--vp-c-text-1);
}

.method-params-list ul {
  margin: 0;
  padding-left: 1.5rem;
  list-style: disc;
}

.method-params-list li {
  margin: 0.25rem 0;
}

.param-type {
  color: var(--vp-c-text-3);
}

.param-required {
  color: var(--vp-c-danger-1);
}

.param-desc {
  color: var(--vp-c-text-2);
}

.method-example pre {
  margin: 0.5rem 0;
  padding: 1rem;
  background: var(--vp-c-bg-alt);
  border-radius: 6px;
  overflow-x: auto;
}
</style>
