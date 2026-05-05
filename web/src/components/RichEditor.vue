<script setup lang="ts">
import { onBeforeUnmount, watch } from 'vue'
import { Editor, EditorContent } from '@tiptap/vue-3'
import StarterKit from '@tiptap/starter-kit'
import Placeholder from '@tiptap/extension-placeholder'
import Link from '@tiptap/extension-link'

import type { TiptapDoc } from '../stores/board'

const props = withDefaults(
  defineProps<{
    modelValue: TiptapDoc | null | undefined
    placeholder?: string
    readonly?: boolean
  }>(),
  {
    placeholder: 'Начните писать…',
    readonly: false,
  },
)

const emit = defineEmits<{
  (e: 'update:modelValue', doc: TiptapDoc): void
}>()

const editor = new Editor({
  editable: !props.readonly,
  content: props.modelValue ?? { type: 'doc', content: [] },
  extensions: [
    StarterKit.configure({
      heading: { levels: [2, 3] },
    }),
    Placeholder.configure({ placeholder: props.placeholder }),
    Link.configure({
      openOnClick: false,
      autolink: true,
      HTMLAttributes: { rel: 'noopener noreferrer nofollow', target: '_blank' },
    }),
  ],
  onUpdate: ({ editor: ed }) => {
    emit('update:modelValue', ed.getJSON() as TiptapDoc)
  },
})

// Keep external prop changes in sync without triggering an emit loop.
watch(
  () => props.modelValue,
  (next) => {
    const current = editor.getJSON()
    if (JSON.stringify(current) === JSON.stringify(next ?? {})) return
    editor.commands.setContent(next ?? { type: 'doc', content: [] }, { emitUpdate: false })
  },
)

watch(
  () => props.readonly,
  (ro) => {
    editor.setEditable(!ro)
  },
)

onBeforeUnmount(() => editor.destroy())

function isActive(name: string, attrs?: Record<string, unknown>) {
  return editor.isActive(name, attrs)
}

function toggleLink() {
  if (editor.isActive('link')) {
    editor.chain().focus().unsetLink().run()
    return
  }
  const url = window.prompt('Адрес ссылки')
  if (!url) return
  editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
}
</script>

<template>
  <div class="hh-rich" :class="{ 'hh-rich--ro': readonly }">
    <div v-if="!readonly" class="hh-rich__toolbar">
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('bold') }"
        :disabled="!editor.can().chain().focus().toggleBold().run()"
        @click="editor.chain().focus().toggleBold().run()"
        title="Жирный (Ctrl+B)"
      >
        <v-icon size="18">mdi-format-bold</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('italic') }"
        @click="editor.chain().focus().toggleItalic().run()"
        title="Курсив (Ctrl+I)"
      >
        <v-icon size="18">mdi-format-italic</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('strike') }"
        @click="editor.chain().focus().toggleStrike().run()"
        title="Зачёркнутый"
      >
        <v-icon size="18">mdi-format-strikethrough</v-icon>
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('heading', { level: 2 }) }"
        @click="editor.chain().focus().toggleHeading({ level: 2 }).run()"
        title="Заголовок"
      >
        <v-icon size="18">mdi-format-header-2</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('heading', { level: 3 }) }"
        @click="editor.chain().focus().toggleHeading({ level: 3 }).run()"
        title="Подзаголовок"
      >
        <v-icon size="18">mdi-format-header-3</v-icon>
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('bulletList') }"
        @click="editor.chain().focus().toggleBulletList().run()"
        title="Список"
      >
        <v-icon size="18">mdi-format-list-bulleted</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('orderedList') }"
        @click="editor.chain().focus().toggleOrderedList().run()"
        title="Нумерованный список"
      >
        <v-icon size="18">mdi-format-list-numbered</v-icon>
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('blockquote') }"
        @click="editor.chain().focus().toggleBlockquote().run()"
        title="Цитата"
      >
        <v-icon size="18">mdi-format-quote-close</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('codeBlock') }"
        @click="editor.chain().focus().toggleCodeBlock().run()"
        title="Блок кода"
      >
        <v-icon size="18">mdi-code-tags</v-icon>
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('link') }"
        @click="toggleLink"
        title="Ссылка"
      >
        <v-icon size="18">mdi-link-variant</v-icon>
      </button>
    </div>

    <EditorContent :editor="editor" class="hh-rich__content" />
  </div>
</template>

<style scoped>
.hh-rich {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.7);
  border-radius: var(--md-shape-m);
  background: rgb(var(--v-theme-surface-container-lowest));
  overflow: hidden;
  transition: border-color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-rich:focus-within {
  border-color: rgb(var(--v-theme-primary));
  box-shadow: 0 0 0 1px rgb(var(--v-theme-primary));
}
.hh-rich--ro {
  background: transparent;
  border-color: rgba(var(--v-theme-outline-variant), 0.4);
}
.hh-rich--ro:focus-within {
  border-color: rgba(var(--v-theme-outline-variant), 0.4);
  box-shadow: none;
}

.hh-rich__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 2px;
  padding: 6px 8px;
  background: rgb(var(--v-theme-surface-container));
  border-bottom: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
}
.hh-rich__btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 32px;
  width: 32px;
  border: none;
  background: transparent;
  color: rgb(var(--v-theme-on-surface));
  border-radius: var(--md-shape-s);
  cursor: pointer;
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-rich__btn:hover {
  background: rgba(var(--v-theme-on-surface), 0.08);
}
.hh-rich__btn:active {
  background: rgba(var(--v-theme-on-surface), 0.12);
}
.hh-rich__btn.is-active {
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.hh-rich__btn:disabled {
  opacity: 0.4;
  cursor: default;
}
.hh-rich__sep {
  width: 1px;
  height: 20px;
  background: rgba(var(--v-theme-outline-variant), 0.7);
  margin: 0 4px;
}

.hh-rich__content {
  padding: 12px 16px;
  min-height: 140px;
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
}

/* tiptap puts its content inside an absolutely-classed `.tiptap` div. */
.hh-rich :deep(.tiptap) {
  outline: none;
  color: rgb(var(--v-theme-on-surface));
}
.hh-rich :deep(.tiptap p) {
  margin: 0 0 8px;
  line-height: 1.5;
}
.hh-rich :deep(.tiptap p:last-child) {
  margin-bottom: 0;
}
.hh-rich :deep(.tiptap h2) {
  font-family: inherit;
  font-size: var(--md-type-title-large);
  line-height: 1.25;
  font-weight: 500;
  margin: 16px 0 8px;
}
.hh-rich :deep(.tiptap h3) {
  font-family: inherit;
  font-size: var(--md-type-title-medium);
  line-height: 1.3;
  font-weight: 500;
  margin: 12px 0 6px;
}
.hh-rich :deep(.tiptap ul),
.hh-rich :deep(.tiptap ol) {
  padding-left: 22px;
  margin: 4px 0;
}
.hh-rich :deep(.tiptap blockquote) {
  border-left: 3px solid rgb(var(--v-theme-primary));
  padding: 2px 12px;
  margin: 8px 0;
  color: rgba(var(--v-theme-on-surface), 0.78);
}
.hh-rich :deep(.tiptap pre) {
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: var(--md-shape-s);
  padding: 10px 12px;
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  overflow-x: auto;
}
.hh-rich :deep(.tiptap code) {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 0.92em;
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: 4px;
  padding: 1px 4px;
}
.hh-rich :deep(.tiptap a) {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
}

/* Placeholder. */
.hh-rich :deep(.tiptap p.is-editor-empty:first-child::before) {
  content: attr(data-placeholder);
  color: rgba(var(--v-theme-on-surface), 0.45);
  pointer-events: none;
  height: 0;
  float: left;
}
</style>
