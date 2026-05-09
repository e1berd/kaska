<script setup lang="ts">
import { onBeforeUnmount, watch } from 'vue'
import { Editor, EditorContent, type FocusPosition } from '@tiptap/vue-3'
import type { AnyExtension } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Placeholder from '@tiptap/extension-placeholder'
import Link from '@tiptap/extension-link'
import Collaboration from '@tiptap/extension-collaboration'
import CollaborationCaret from '@tiptap/extension-collaboration-caret'
import { autoUpdate, computePosition, flip, offset, shift } from '@floating-ui/dom'
import type * as Y from 'yjs'
import type { Awareness } from 'y-protocols/awareness'
import {
  PhTextB as TextB,
  PhTextItalic as TextItalic,
  PhTextStrikethrough as TextStrikethrough,
  PhTextHTwo as H2,
  PhTextHThree as H3,
  PhListBullets as ListBullets,
  PhListNumbers as ListNumbers,
  PhQuotes as Quote,
  PhCode as Code,
  PhLink as LinkIcon,
} from '@phosphor-icons/vue'

import type { TiptapDoc } from '@/stores/board'

type CollabUser = { name: string; color: string }

const props = withDefaults(
  defineProps<{
    modelValue?: TiptapDoc | null
    placeholder?: string
    readonly?: boolean
    editable?: boolean
    autofocus?: FocusPosition
    ydoc?: Y.Doc | null
    awareness?: Awareness | null
    user?: CollabUser | null
  }>(),
  {
    placeholder: 'Начните писать…',
    autofocus: false,
    readonly: false,
    editable: undefined,
    modelValue: null,
    ydoc: null,
    awareness: null,
    user: null,
  },
)

const emit = defineEmits<{
  (e: 'update:modelValue', doc: TiptapDoc): void
}>()

const collabMode = !!props.ydoc

function resolveEditable(): boolean {
  if (typeof props.editable === 'boolean') return props.editable
  return !props.readonly
}

const baseExtensions: AnyExtension[] = [
  StarterKit.configure({
    link: false,
    heading: { levels: [2, 3] },
    ...(collabMode ? { undoRedo: false as const } : {}),
  }),
  Placeholder.configure({ placeholder: props.placeholder }),
  Link.configure({
    openOnClick: false,
    autolink: true,
    HTMLAttributes: { rel: 'noopener noreferrer nofollow', target: '_blank' },
  }),
]

function buildCaret(user: CollabUser): HTMLElement {
  const cursor = document.createElement('span')
  cursor.className = 'hh-collab-caret'
  cursor.style.borderColor = user.color
  cursor.appendChild(document.createTextNode('⁠'))

  const label = document.createElement('div')
  label.className = 'hh-collab-caret__label'
  label.style.background = user.color
  label.textContent = user.name
  cursor.appendChild(label)
  cursor.appendChild(document.createTextNode('⁠'))

  let stop: (() => void) | null = null
  let removalObserver: MutationObserver | null = null

  requestAnimationFrame(() => {
    if (!cursor.isConnected) return
    const editor = cursor.closest('.tiptap') as HTMLElement | null

    stop = autoUpdate(cursor, label, () => {
      void computePosition(cursor, label, {
        placement: 'top-start',
        strategy: 'absolute',
        middleware: [
          offset(2),
          flip({ fallbackPlacements: ['bottom-start', 'top-end', 'bottom-end'] }),
          shift({ padding: 4, ...(editor ? { boundary: editor } : {}) }),
        ],
      }).then(({ x, y }) => {
        if (!cursor.isConnected) return
        label.style.left = `${x}px`
        label.style.top = `${y}px`
      })
    })

    const root = editor ?? document.body
    removalObserver = new MutationObserver(() => {
      if (cursor.isConnected) return
      stop?.()
      stop = null
      removalObserver?.disconnect()
      removalObserver = null
    })
    removalObserver.observe(root, { childList: true, subtree: true })
  })

  return cursor
}

const collabExtensions: AnyExtension[] = []
if (collabMode && props.ydoc) {
  collabExtensions.push(Collaboration.configure({ document: props.ydoc }))
  if (props.awareness) {
    collabExtensions.push(
      CollaborationCaret.configure({
        provider: { awareness: props.awareness },
        user: props.user ?? { name: 'Гость', color: '#9ca3af' },
        render: buildCaret,
      }),
    )
  }
}

const editor = new Editor({
  editable: resolveEditable(),
  autofocus: props.autofocus,
  content: collabMode ? undefined : (props.modelValue ?? { type: 'doc', content: [] }),
  extensions: [...baseExtensions, ...collabExtensions],
  ...(collabMode
    ? {}
    : {
        onUpdate: ({ editor: ed }: { editor: Editor }) => {
          emit('update:modelValue', ed.getJSON() as TiptapDoc)
        },
      }),
})

if (!collabMode) {
  watch(
    () => props.modelValue,
    (next) => {
      const current = editor.getJSON()
      if (JSON.stringify(current) === JSON.stringify(next ?? {})) return
      editor.commands.setContent(next ?? { type: 'doc', content: [] }, { emitUpdate: false })
    },
  )
}

watch(
  () => resolveEditable(),
  (val) => {
    editor.setEditable(val)
  },
)

onBeforeUnmount(() => editor.destroy())

defineExpose({
  getJSON: () => editor.getJSON() as TiptapDoc,
  focus: (position: FocusPosition = 'end') => editor.commands.focus(position),
})

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
  <div class="hh-rich" :class="{ 'hh-rich--ro': !resolveEditable() }">
    <div v-if="resolveEditable()" class="hh-rich__toolbar">
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

  :deep(.hh-collab-caret) {
    border-left: 1px solid;
    border-right: 1px solid;
    margin-left: -1px;
    margin-right: -1px;
    pointer-events: none;
    position: relative;
    word-break: normal;
  }

  :deep(.hh-collab-caret__label) {
    border-radius: 4px;
    color: white;
    font-size: 11px;
    font-weight: 600;
    line-height: normal;
    padding: 0.1rem 0.3rem;
    position: absolute;
    top: -9999px;
    left: -9999px;
    user-select: none;
    white-space: nowrap;
    max-width: 160px;
    overflow: hidden;
    text-overflow: ellipsis;
    pointer-events: none;
    z-index: 1;
  }

  :deep(.ProseMirror-yjs-selection) {
    pointer-events: none;
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
