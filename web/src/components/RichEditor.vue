<script setup lang="ts">
import { onBeforeUnmount, watch } from 'vue'
import { Editor, EditorContent, type FocusPosition } from '@tiptap/vue-3'
import type { AnyExtension } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Placeholder from '@tiptap/extension-placeholder'
import Link from '@tiptap/extension-link'
import {
  TextB,
  TextItalic,
  TextStrikethrough,
  H2,
  H3,
  ListBullets,
  ListNumbers,
  Quote,
  Code,
  Link as LinkIcon
} from '@phosphor-icons/vue'

import type { TiptapDoc } from '../stores/board'

const props = withDefaults(
  defineProps<{
    modelValue: TiptapDoc | null | undefined
    placeholder?: string
    readonly?: boolean
    autofocus?: FocusPosition
  }>(),
  {
    placeholder: 'Начните писать…',
    autofocus: false,
    readonly: false,
  },
)

const emit = defineEmits<{
  (e: 'update:modelValue', doc: TiptapDoc): void
}>()

const extensions: AnyExtension[] = [
  StarterKit.configure({
    link: false,
    heading: { levels: [2, 3] },
  }),
  Placeholder.configure({ placeholder: props.placeholder }),
  Link.configure({
    openOnClick: false,
    autolink: true,
    HTMLAttributes: { rel: 'noopener noreferrer nofollow', target: '_blank' },
  }),
]

const editor = new Editor({
  editable: !props.readonly,
  autofocus: props.autofocus,
  content: props.modelValue ?? { type: 'doc', content: [] },
  extensions,
  onUpdate: ({ editor: ed }) => {
    emit('update:modelValue', ed.getJSON() as TiptapDoc)
  },
})

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
        <TextB :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('italic') }"
        @click="editor.chain().focus().toggleItalic().run()"
        title="Курсив (Ctrl+I)"
      >
        <TextItalic :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('strike') }"
        @click="editor.chain().focus().toggleStrike().run()"
        title="Зачёркнутый"
      >
        <TextStrikethrough :size="18" />
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('heading', { level: 2 }) }"
        @click="editor.chain().focus().toggleHeading({ level: 2 }).run()"
        title="Заголовок"
      >
        <H2 :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('heading', { level: 3 }) }"
        @click="editor.chain().focus().toggleHeading({ level: 3 }).run()"
        title="Подзаголовок"
      >
        <H3 :size="18" />
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('bulletList') }"
        @click="editor.chain().focus().toggleBulletList().run()"
        title="Список"
      >
        <ListBullets :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('orderedList') }"
        @click="editor.chain().focus().toggleOrderedList().run()"
        title="Нумерованный список"
      >
        <ListNumbers :size="18" />
      </button>
      <span class="hh-rich__sep" />
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('blockquote') }"
        @click="editor.chain().focus().toggleBlockquote().run()"
        title="Цитата"
      >
        <Quote :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('codeBlock') }"
        @click="editor.chain().focus().toggleCodeBlock().run()"
        title="Блок кода"
      >
        <Code :size="18" />
      </button>
      <button
        type="button"
        class="hh-rich__btn"
        :class="{ 'is-active': isActive('link') }"
        @click="toggleLink"
        title="Ссылка"
      >
        <LinkIcon :size="18" />
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

  &:focus-within {
    border-color: rgb(var(--v-theme-primary));
    box-shadow: 0 0 0 1px rgb(var(--v-theme-primary));
  }

  &--ro {
    background: transparent;
    border-color: rgba(var(--v-theme-outline-variant), 0.4);

    &:focus-within {
      border-color: rgba(var(--v-theme-outline-variant), 0.4);
      box-shadow: none;
    }
  }

  :deep(.tiptap) {
    outline: none;
    color: rgb(var(--v-theme-on-surface));

    p {
      margin: 0 0 8px;
      line-height: 1.5;

      &:last-child {
        margin-bottom: 0;
      }
    }

    h2 {
      font-family: inherit;
      font-size: var(--md-type-title-large);
      line-height: 1.25;
      font-weight: 500;
      margin: 16px 0 8px;
    }

    h3 {
      font-family: inherit;
      font-size: var(--md-type-title-medium);
      line-height: 1.3;
      font-weight: 500;
      margin: 12px 0 6px;
    }

    ul, ol {
      padding-left: 22px;
      margin: 4px 0;
    }

    blockquote {
      border-left: 3px solid rgb(var(--v-theme-primary));
      padding: 2px 12px;
      margin: 8px 0;
      color: rgba(var(--v-theme-on-surface), 0.78);
    }

    pre {
      background: rgb(var(--v-theme-surface-container-high));
      border-radius: var(--md-shape-s);
      padding: 10px 12px;
      font-family: 'Roboto Mono', ui-monospace, monospace;
      font-size: 13px;
      overflow-x: auto;
    }

    code {
      font-family: 'Roboto Mono', ui-monospace, monospace;
      font-size: 0.92em;
      background: rgb(var(--v-theme-surface-container-high));
      border-radius: 4px;
      padding: 1px 4px;
    }

    a {
      color: rgb(var(--v-theme-primary));
      text-decoration: underline;
    }

    p.is-editor-empty:first-child::before {
      content: attr(data-placeholder);
      color: rgba(var(--v-theme-on-surface), 0.45);
      pointer-events: none;
      height: 0;
      float: left;
    }
  }
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

  &:hover {
    background: rgba(var(--v-theme-on-surface), 0.08);
  }

  &:active {
    background: rgba(var(--v-theme-on-surface), 0.12);
  }

  &.is-active {
    background: rgb(var(--v-theme-secondary-container));
    color: rgb(var(--v-theme-on-secondary-container));
  }

  &:disabled {
    opacity: 0.4;
    cursor: default;
  }
}

.hh-rich__sep {
  width: 1px;
  height: 20px;
  background: rgba(var(--v-theme-outline-variant), 0.7);
  margin: 0 4px;
}

.hh-rich__content {
  padding: 12px 16px;
  min-height: 170px;
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
}
</style>
