<script setup lang="ts">
import { useId } from 'vue'

defineProps<{
  label: string
  type?: string
  autocomplete?: string
  errors?: string[]
  hint?: string
  inputmode?: 'text' | 'email' | 'numeric'
  maxlength?: number
  placeholder?: string
}>()

const model = defineModel<string>({ required: true })
const id = useId()
</script>

<template>
  <div class="space-y-2">
    <label :for="id" class="field-label">{{ label }}</label>
    <input
      :id="id"
      v-model="model"
      class="field-input"
      :type="type ?? 'text'"
      :autocomplete="autocomplete"
      :inputmode="inputmode"
      :maxlength="maxlength"
      :placeholder="placeholder"
      :aria-invalid="errors?.length ? 'true' : undefined"
      :aria-describedby="errors?.length || hint ? `${id}-desc` : undefined"
    />
    <p v-if="errors?.length" :id="`${id}-desc`" class="field-error">{{ errors.join(', ') }}</p>
    <p v-else-if="hint" :id="`${id}-desc`" class="field-hint">{{ hint }}</p>
  </div>
</template>
