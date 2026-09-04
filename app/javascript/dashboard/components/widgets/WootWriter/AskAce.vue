<script setup>
// NSID custom component — "Ask Ace" agent-assist chat modal. Talks to the NSID
// Symfony endpoint (AceAgentAssistController::ask), which runs each question through
// the internal agent lane (S3 KB + Claude) and returns the answer. Keeps a running
// thread (persisted per conversation in this agent's browser) so it reads like a
// chat and Ace remembers prior turns. Self-contained (own markup + scoped styles)
// so a Chatwoot upgrade doesn't clobber it — only the one-line hook in
// CopilotMenuBar.vue needs re-applying.
import { ref, nextTick, onMounted, onUnmounted } from 'vue';
import MarkdownIt from 'markdown-it';
import DOMPurify from 'dompurify';
// Endpoint host + optional shared secret live in the shared helper so the modal
// and the reply-box AI actions can't drift apart. The URL is resolved at call time
// (from Super Admin settings), never cached at module load.
import { aceAskUrl, aceAssistHeaders } from 'dashboard/helper/aceAssist';

const props = defineProps({
  conversationId: { type: Number, default: null },
});
const emit = defineEmits(['close', 'insert']);

// Render Ace's markdown answers safely (bold, links, lists). Links open in a new tab.
const md = new MarkdownIt({ linkify: true, breaks: true });
const renderMarkdown = text =>
  DOMPurify.sanitize(md.render(String(text || '')), {
    ADD_ATTR: ['target', 'rel'],
  });

// Quick-start prompts shown on the empty state.
const SUGGESTIONS = [
  'How do I handle a duplicate charge?',
  'What is the refund process?',
  'How do I verify a coach?',
  'Ineligible vs Unverified — how do I explain it?',
];

// Keep at most this many turns in storage so it can't grow unbounded.
const MAX_TURNS = 40;

const messages = ref([]); // { role: 'user' | 'ace' | 'error', text }
const turns = ref([]); // { q, a } completed pairs sent back as context
const question = ref('');
const loading = ref(false);
const copiedIndex = ref(-1);
const threadRef = ref(null);
const inputRef = ref(null);

const scrollToBottom = () => {
  nextTick(() => {
    if (threadRef.value)
      threadRef.value.scrollTop = threadRef.value.scrollHeight;
  });
};

// After an answer arrives, align the LATEST question to the top of the thread so a
// long answer is read from its START (not scrolled to its end).
const scrollAnswerToTop = () => {
  nextTick(() => {
    const thread = threadRef.value;
    if (!thread) return;
    const questions = thread.querySelectorAll('.aa__row--user');
    const lastQ = questions[questions.length - 1];
    if (!lastQ) {
      thread.scrollTop = thread.scrollHeight;
      return;
    }
    // getBoundingClientRect is robust regardless of the row's offsetParent.
    const delta =
      lastQ.getBoundingClientRect().top - thread.getBoundingClientRect().top;
    thread.scrollTop += delta - 8;
  });
};

// Persist the thread PER CONVERSATION in THIS agent's browser (localStorage), so
// closing/reopening the modal and reloads keep it; switching conversations shows
// its own thread. Not shared between agents or devices.
const storageKey = () =>
  `ace_assist_history_${props.conversationId || 'global'}`;
const saveHistory = () => {
  try {
    localStorage.setItem(
      storageKey(),
      JSON.stringify({
        messages: messages.value.slice(-MAX_TURNS * 2),
        turns: turns.value.slice(-MAX_TURNS),
      })
    );
  } catch (e) {
    /* storage may be unavailable (private mode etc.) — non-fatal */
  }
};
const clearHistory = () => {
  messages.value = [];
  turns.value = [];
  try {
    localStorage.removeItem(storageKey());
  } catch (e) {
    /* non-fatal */
  }
};
const onKeydown = e => {
  if (e.key === 'Escape') emit('close');
};
onMounted(() => {
  try {
    const raw = localStorage.getItem(storageKey());
    if (raw) {
      const data = JSON.parse(raw);
      if (Array.isArray(data.messages)) messages.value = data.messages;
      if (Array.isArray(data.turns)) turns.value = data.turns;
    }
  } catch (e) {
    /* non-fatal */
  }
  scrollToBottom();
  nextTick(() => inputRef.value?.focus());
  window.addEventListener('keydown', onKeydown);
});
onUnmounted(() => window.removeEventListener('keydown', onKeydown));

const send = async q => {
  if (!q || loading.value) return;

  let answered = false;
  messages.value.push({ role: 'user', text: q });
  question.value = '';
  loading.value = true;
  scrollToBottom();

  const url = aceAskUrl();
  if (!url) {
    messages.value.push({
      role: 'error',
      text: 'Ace isn’t set up yet. An admin needs to open Chatwoot Super Admin → Settings → General → “Ace Agent-Assist Base URL” and enter the NSID app URL. Once that’s saved, ask again here.',
    });
    loading.value = false;
    saveHistory();
    scrollToBottom();
    return;
  }

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: aceAssistHeaders(),
      body: JSON.stringify({ question: q, history: turns.value.slice(-10) }),
    });
    const body = await res.json().catch(() => ({}));
    if (res.ok && body.answer) {
      messages.value.push({ role: 'ace', text: body.answer });
      turns.value.push({ q, a: body.answer });
      answered = true;
    } else {
      messages.value.push({
        role: 'error',
        text: body.error || 'Something went wrong. Please try again.',
      });
    }
  } catch (e) {
    messages.value.push({
      role: 'error',
      text: 'Could not reach Ace. Please try again.',
    });
  } finally {
    loading.value = false;
    saveHistory();
    // Read a real answer from its start; keep errors in view at the bottom.
    if (answered) scrollAnswerToTop();
    else scrollToBottom();
  }
};

const ask = () => send(question.value.trim());
const askSuggestion = text => send(text);

const copyAnswer = async (text, i) => {
  try {
    await navigator.clipboard.writeText(text);
    copiedIndex.value = i;
    setTimeout(() => {
      if (copiedIndex.value === i) copiedIndex.value = -1;
    }, 1500);
  } catch (e) {
    /* clipboard may be blocked — non-fatal */
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template --
       NSID internal agent tool — its labels are intentionally not i18n'd. -->
  <div class="aa__overlay" @click.self="emit('close')">
    <div class="aa__card">
      <!-- Header -->
      <header class="aa__head">
        <span class="aa__dot" />
        <div class="aa__titles">
          <strong class="aa__title">Ask Ace</strong>
          <span class="aa__sub">Agent knowledge base · only you see this</span>
        </div>
        <button
          v-if="messages.length"
          type="button"
          class="aa__clear"
          title="Clear this Ask Ace thread — deletes all questions & answers here and starts a fresh chat"
          @click="clearHistory"
        >
          Clear
        </button>
        <button
          type="button"
          class="aa__close"
          aria-label="Close"
          title="Close — this chat stays saved for next time"
          @click="emit('close')"
        >
          ×
        </button>
      </header>

      <!-- Thread -->
      <div ref="threadRef" class="aa__thread">
        <div v-if="messages.length === 0" class="aa__empty">
          <p class="aa__empty-lead">What do you need help with?</p>
          <p class="aa__empty-hint">
            Ask anything from the agent knowledge base. Ace remembers this
            thread, so you can keep asking follow-ups.
          </p>
          <div class="aa__chips">
            <button
              v-for="s in SUGGESTIONS"
              :key="s"
              type="button"
              class="aa__chip"
              @click="askSuggestion(s)"
            >
              {{ s }}
            </button>
          </div>
        </div>

        <div
          v-for="(m, i) in messages"
          :key="i"
          class="aa__row"
          :class="`aa__row--${m.role}`"
        >
          <div class="aa__bubble" :class="`aa__bubble--${m.role}`">
            <!-- eslint-disable-next-line vue/no-v-html -->
            <div
              v-if="m.role === 'ace'"
              class="aa__md"
              v-html="renderMarkdown(m.text)"
            />
            <div v-else class="aa__bubble-text">{{ m.text }}</div>
            <div v-if="m.role === 'ace'" class="aa__actions">
              <button
                type="button"
                class="aa__act aa__act--primary"
                title="Put this answer into your reply box"
                @click="emit('insert', m.text)"
              >
                Insert into reply
              </button>
              <button
                type="button"
                class="aa__act"
                title="Copy answer to clipboard"
                @click="copyAnswer(m.text, i)"
              >
                {{ copiedIndex === i ? 'Copied' : 'Copy' }}
              </button>
            </div>
          </div>
        </div>

        <div v-if="loading" class="aa__row aa__row--ace">
          <div class="aa__bubble aa__bubble--ace aa__typing">
            Ace is thinking…
          </div>
        </div>
      </div>

      <!-- Composer -->
      <div class="aa__composer">
        <textarea
          ref="inputRef"
          v-model="question"
          class="aa__input"
          placeholder="Ask Ace a question…"
          maxlength="2000"
          rows="1"
          @keydown.enter.exact.prevent="ask"
        />
        <button
          type="button"
          class="aa__send"
          :disabled="loading || !question.trim()"
          @click="ask"
        >
          {{ loading ? '…' : 'Ask' }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.aa__overlay {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 32, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  font:
    14px/1.55 -apple-system,
    BlinkMacSystemFont,
    'Segoe UI',
    Roboto,
    Arial,
    sans-serif;
  color: #1f2733;
}
.aa__card {
  width: 460px;
  max-width: 94vw;
  height: 580px;
  max-height: 90vh;
  background: #fff;
  border-radius: 14px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.3);
}

/* Header */
.aa__head {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 16px;
  border-bottom: 1px solid #eef1f5;
}
.aa__dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: #1f9d55;
  flex: none;
}
.aa__titles {
  display: flex;
  flex-direction: column;
  line-height: 1.2;
  margin-right: auto;
}
.aa__title {
  font-size: 15px;
}
.aa__sub {
  font-size: 11px;
  color: #8b95a1;
}
.aa__clear {
  border: 1px solid #e3e8ee;
  background: #fff;
  border-radius: 7px;
  padding: 4px 10px;
  font-size: 12px;
  color: #6b7684;
  cursor: pointer;
}
.aa__clear:hover {
  background: #f4f6f8;
}
.aa__close {
  border: 0;
  background: none;
  font-size: 22px;
  line-height: 1;
  color: #8b95a1;
  cursor: pointer;
  padding: 0 2px;
}
.aa__close:hover {
  color: #1f2733;
}

/* Thread */
.aa__thread {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  background: #f7f9fb;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.aa__empty {
  margin: auto 0;
  text-align: center;
  padding: 8px 4px;
}
.aa__empty-lead {
  margin: 0 0 4px;
  font-weight: 600;
  font-size: 15px;
}
.aa__empty-hint {
  margin: 0 auto 14px;
  max-width: 320px;
  color: #6b7684;
  font-size: 12.5px;
}
.aa__chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: center;
}
.aa__chip {
  border: 1px solid #dbe6df;
  background: #fff;
  color: #1f7a45;
  border-radius: 999px;
  padding: 6px 12px;
  font-size: 12.5px;
  cursor: pointer;
  transition: background 0.12s;
}
.aa__chip:hover {
  background: #edf7f1;
}
.aa__row {
  display: flex;
}
.aa__row--user {
  justify-content: flex-end;
}
.aa__row--ace,
.aa__row--error {
  justify-content: flex-start;
}
.aa__bubble {
  position: relative;
  max-width: 88%;
  padding: 9px 13px;
  border-radius: 14px;
  white-space: pre-wrap;
  word-wrap: break-word;
}
.aa__bubble--user {
  background: #1f9d55;
  color: #fff;
  border-bottom-right-radius: 5px;
}
.aa__bubble--ace {
  background: #fff;
  border: 1px solid #e6ebf0;
  border-bottom-left-radius: 5px;
}
.aa__bubble--error {
  background: #fdf3f3;
  border: 1px solid #f3caca;
  color: #b4232a;
}
.aa__actions {
  display: flex;
  gap: 14px;
  justify-content: flex-end;
  margin-top: 8px;
  padding-top: 7px;
  border-top: 1px solid #f0f3f6;
}
.aa__act {
  border: 0;
  background: none;
  font-size: 11.5px;
  color: #6b7684;
  cursor: pointer;
  padding: 0;
}
.aa__act:hover {
  text-decoration: underline;
}
.aa__act--primary {
  color: #1f9d55;
  font-weight: 600;
}
/* Markdown answer content */
.aa__md :deep(p) {
  margin: 0 0 8px;
}
.aa__md :deep(p:last-child) {
  margin-bottom: 0;
}
.aa__md :deep(ul),
.aa__md :deep(ol) {
  margin: 4px 0 8px;
  padding-left: 18px;
}
.aa__md :deep(li) {
  margin: 2px 0;
}
.aa__md :deep(a) {
  color: #1f7a45;
  text-decoration: underline;
}
.aa__md :deep(strong) {
  font-weight: 600;
}
.aa__md :deep(code) {
  background: #f0f3f6;
  padding: 1px 4px;
  border-radius: 4px;
  font-size: 12px;
}
.aa__typing {
  color: #6b7684;
}

/* Composer */
.aa__composer {
  display: flex;
  gap: 8px;
  align-items: flex-end;
  padding: 12px 14px;
  border-top: 1px solid #eef1f5;
  background: #fff;
}
.aa__input {
  box-sizing: border-box;
  flex: 1;
  /* Chatwoot's global `textarea { @apply field-base h-16 }` forces a fixed height +
     mb-4 margin on every textarea — override both. Taller box, drag-resizable, and
     scrolls past the max. */
  height: 84px !important;
  min-height: 84px !important;
  max-height: 200px !important;
  margin: 0 !important;
  resize: vertical;
  overflow-y: auto;
  padding: 11px 12px;
  border: 1px solid #dbe1e8;
  border-radius: 10px;
  font: inherit;
  line-height: 20px;
}
.aa__input:focus {
  outline: none;
  border-color: #1f9d55;
  box-shadow: 0 0 0 3px rgba(31, 157, 85, 0.12);
}
.aa__send {
  box-sizing: border-box;
  flex: none;
  height: 44px;
  min-width: 64px;
  padding: 0 18px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: #1f9d55;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font: inherit;
  font-weight: 600;
  cursor: pointer;
}
.aa__send:disabled {
  opacity: 0.55;
  cursor: default;
}
</style>
