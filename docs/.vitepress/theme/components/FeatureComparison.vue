<template>
  <table class="feature-comparison">
    <thead>
      <tr>
        <th>Feature</th>
        <th v-for="tool in tools" :key="tool">{{ tool }}</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="feature in features" :key="feature.name">
        <td class="feature-name">{{ feature.name }}</td>
        <td
          v-for="(tool, index) in tools"
          :key="tool"
          :class="getSupportClass(feature.support[index])"
        >
          <span class="support-icon">{{ getSupportIcon(feature.support[index]) }}</span>
          <span v-if="feature.notes?.[index]" class="note">{{ feature.notes[index] }}</span>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<script setup lang="ts">
interface Feature {
  name: string;
  support: boolean[];
  notes?: string[];
}

defineProps<{
  tools: string[];
  features: Feature[];
}>();

function getSupportIcon(supported: boolean): string {
  return supported ? "✓" : "✗";
}

function getSupportClass(supported: boolean): string {
  return supported ? "supported" : "not-supported";
}
</script>

<style scoped>
.feature-comparison {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
}

.feature-comparison th,
.feature-comparison td {
  padding: 0.75rem 1rem;
  text-align: left;
  border-bottom: 1px solid var(--vp-c-divider);
}

.feature-comparison th {
  background: var(--vp-c-bg-soft);
  font-weight: 600;
}

.feature-name {
  font-weight: 500;
}

.supported {
  color: var(--vp-c-green-1);
}

.not-supported {
  color: var(--vp-c-red-1);
}

.support-icon {
  font-weight: bold;
}

.note {
  display: block;
  font-size: 0.85rem;
  color: var(--vp-c-text-2);
  margin-top: 0.25rem;
}
</style>
