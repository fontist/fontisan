<template>
  <span :class="['badge', type]">
    <slot />
  </span>
</template>

<script setup lang="ts">
defineProps<{
  type?: "tip" | "warning" | "danger" | "info" | "pure-ruby";
}>();
</script>

<style scoped>
.badge {
  display: inline-flex;
  align-items: center;
  padding: 0.125rem 0.5rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 600;
  line-height: 1.25rem;
}

.tip {
  background-color: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
}

.warning {
  background-color: rgba(255, 197, 61, 0.14);
  color: var(--vp-c-warning-1);
}

.danger {
  background-color: rgba(244, 63, 94, 0.14);
  color: var(--vp-c-danger-1);
}

.info {
  background-color: rgba(96, 165, 250, 0.14);
  color: var(--vp-c-info-1);
}

.pure-ruby {
  background: linear-gradient(135deg, var(--fontist-rose), #d4718a);
  color: white;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
</style>
