<script setup lang="ts">
import { computed, onBeforeUnmount, watch, type Component } from 'vue'
import { Editor, EditorContent, type FocusPosition } from '@tiptap/vue-3'
import { BubbleMenu } from '@tiptap/vue-3/menus'
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
  PhCode as InlineCode,
  PhCodeBlock as CodeBlock,
  PhLink as LinkIcon,
} from '@phosphor-icons/vue'

import type { TiptapDoc } from '@/stores/board'

type ToolSep = { sep: true }
type ToolButton = {
  id: string
  icon: Component
  title: string
  run: () => void
  active?: () => boolean
  disabled?: () => boolean
}
type ToolItem = ToolSep | ToolButton

function isSep(item: ToolItem): item is ToolSep {
  return 'sep' in item
}

type CollabUser = { name: string; color: string }

const props = withDefaults(
  defineProps<{
    modelValue?: TiptapDoc | null
    placeholder?: string
    readonly?: boolean
    editable?: boolean
    headings?: boolean
    compact?: boolean
    bubble?: boolean
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
    headings: true,
    compact: false,
    bubble: false,
    modelValue: null,
    ydoc: null,
    awareness: null,
    user: null,
  },
)

const emit = defineEmits<{
  (e: 'update:modelValue', doc: TiptapDoc): void
  (e: 'blur'): void
}>()

const collabMode = !!props.ydoc

function resolveEditable(): boolean {
  if (typeof props.editable === 'boolean') return props.editable
  return !props.readonly
}

const baseExtensions: AnyExtension[] = [
  StarterKit.configure({
    link: false,
    heading: props.headings ? { levels: [2, 3] } : false,
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
  cursor.className = 'ks-collab-caret'
  cursor.style.borderColor = user.color
  cursor.appendChild(document.createTextNode('⁠'))

  const label = document.createElement('div')
  label.className = 'ks-collab-caret__label'
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
  onBlur: () => emit('blur'),
  ...(collabMode
    ? {}
    : {
        onUpdate: ({ editor: ed }) => {
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

function toggleLink() {
  if (editor.isActive('link')) {
    editor.chain().focus().unsetLink().run()
    return
  }
  const url = window.prompt('Адрес ссылки')
  if (!url) return
  editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
}

const tools = computed<ToolItem[]>(() => {
  const items: ToolItem[] = [
    {
      id: 'bold',
      icon: TextB,
      title: 'Жирный (Ctrl+B)',
      run: () => editor.chain().focus().toggleBold().run(),
      active: () => editor.isActive('bold'),
    },
    {
      id: 'italic',
      icon: TextItalic,
      title: 'Курсив (Ctrl+I)',
      run: () => editor.chain().focus().toggleItalic().run(),
      active: () => editor.isActive('italic'),
    },
    {
      id: 'strike',
      icon: TextStrikethrough,
      title: 'Зачёркнутый',
      run: () => editor.chain().focus().toggleStrike().run(),
      active: () => editor.isActive('strike'),
    },
    {
      id: 'code',
      icon: InlineCode,
      title: 'Код',
      run: () => editor.chain().focus().toggleCode().run(),
      active: () => editor.isActive('code'),
    },
  ]

  if (props.headings) {
    items.push(
      { sep: true },
      {
        id: 'h2',
        icon: H2,
        title: 'Заголовок',
        run: () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
        active: () => editor.isActive('heading', { level: 2 }),
      },
      {
        id: 'h3',
        icon: H3,
        title: 'Подзаголовок',
        run: () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
        active: () => editor.isActive('heading', { level: 3 }),
      },
    )
  }

  items.push(
    { sep: true },
    {
      id: 'bulletList',
      icon: ListBullets,
      title: 'Список',
      run: () => editor.chain().focus().toggleBulletList().run(),
      active: () => editor.isActive('bulletList'),
    },
    {
      id: 'orderedList',
      icon: ListNumbers,
      title: 'Нумерованный список',
      run: () => editor.chain().focus().toggleOrderedList().run(),
      active: () => editor.isActive('orderedList'),
    },
    { sep: true },
    {
      id: 'blockquote',
      icon: Quote,
      title: 'Цитата',
      run: () => editor.chain().focus().toggleBlockquote().run(),
      active: () => editor.isActive('blockquote'),
    },
    {
      id: 'codeBlock',
      icon: CodeBlock,
      title: 'Блок кода',
      run: () => editor.chain().focus().toggleCodeBlock().run(),
      active: () => editor.isActive('codeBlock'),
    },
    {
      id: 'link',
      icon: LinkIcon,
      title: 'Ссылка',
      run: toggleLink,
      active: () => editor.isActive('link'),
    },
  )

  return items
})

const bubbleOptions = {
  placement: 'top' as const,
  offset: 8,
  flip: true,
  shift: { padding: 8 },
}

function bubbleAppendTo(): HTMLElement {
  return document.body
}

function focusEditableSurface(event: MouseEvent) {
  if (!resolveEditable()) return
  const target = event.target as HTMLElement | null
  const proseMirror = target?.closest('.ProseMirror')
  if (proseMirror && target !== proseMirror) return
  editor.commands.focus('end')
}
</script>

<template>
  <div
    class="ks-rich"
    :class="{ 'ks-rich--ro': !resolveEditable(), 'ks-rich--compact': compact }"
    @mousedown.self="focusEditableSurface"
  >
    <BubbleMenu
      v-if="bubble && resolveEditable()"
      :editor="editor"
      :options="bubbleOptions"
      :append-to="bubbleAppendTo"
      class="ks-rich__bubble"
      :style="{ zIndex: 2500 }"
    >
      <div class="ks-rich__toolbar ks-rich__toolbar--bubble">
        <template v-for="(item, i) in tools" :key="i">
          <span v-if="isSep(item)" class="ks-rich__sep" />
          <button
            v-else
            type="button"
            class="ks-rich__btn"
            :class="{ 'is-active': item.active?.() }"
            :disabled="item.disabled?.()"
            :title="item.title"
            @click="item.run()"
          >
            <component :is="item.icon" :size="18" />
          </button>
        </template>
      </div>
    </BubbleMenu>

    <div v-else-if="resolveEditable()" class="ks-rich__toolbar">
      <template v-for="(item, i) in tools" :key="i">
        <span v-if="isSep(item)" class="ks-rich__sep" />
        <button
          v-else
          type="button"
          class="ks-rich__btn"
          :class="{ 'is-active': item.active?.() }"
          :disabled="item.disabled?.()"
          :title="item.title"
          @click="item.run()"
        >
          <component :is="item.icon" :size="18" />
        </button>
      </template>
    </div>

    <EditorContent :editor="editor" class="ks-rich__content" @mousedown="focusEditableSurface" />
  </div>
</template>

<style scoped>
.ks-rich {
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
    padding: 12px 16px;
    min-height: 170px;

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
      border-radius: var(--md-shape-xs);
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

  :deep(.ks-collab-caret) {
    border-left: 1px solid;
    border-right: 1px solid;
    margin-left: -1px;
    margin-right: -1px;
    pointer-events: none;
    position: relative;
    word-break: normal;
  }

  :deep(.ks-collab-caret__label) {
    border-radius: var(--md-shape-xs);
    color: white;
    font-size: 11px;
    font-weight: 500;
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

.ks-rich__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 2px;
  padding: 6px 8px;
  background: rgb(var(--v-theme-surface-container));
  border-bottom: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
}

.ks-rich__bubble {
  z-index: 30;
}

.ks-rich__toolbar--bubble {
  flex-wrap: nowrap;
  gap: 2px;
  padding: 4px;
  border-bottom: none;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  box-shadow: var(--md-elev-2);
}

.ks-rich__toolbar--bubble .ks-rich__btn {
  height: 36px;
  width: 36px;
  border-radius: var(--md-shape-full);
}

.ks-rich__toolbar--bubble .ks-rich__btn.is-active:hover {
  background: rgb(var(--v-theme-secondary-container));
  box-shadow: inset 0 0 0 999px rgba(var(--v-theme-on-secondary-container), var(--md-state-hover));
}

.ks-rich__toolbar--bubble .ks-rich__sep {
  height: 18px;
  margin: 0 2px;
  background: rgba(var(--v-theme-outline-variant), 0.6);
}

.ks-rich__btn {
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

.ks-rich__sep {
  width: 1px;
  height: 20px;
  background: rgba(var(--v-theme-outline-variant), 0.7);
  margin: 0 4px;
}

.ks-rich__content {
  display: flex;
  flex-direction: column;
  cursor: text;
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
}

.ks-rich__content :deep(.tiptap) {
  flex: 1;
}

.ks-rich--compact :deep(.tiptap) {
  min-height: 84px;
  padding: 10px 12px;
}
</style>
