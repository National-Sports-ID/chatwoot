<script setup>
// NSID custom component (#3797) — "Create ticket" modal. Ace reads the open chat and
// fills in the ticket (AceAgentAssistController::ticket, action=prefill); the agent
// checks it and creates it (action=create), which emails the customer, tells them the
// reference in the chat and closes the chat. Self-contained (own markup + scoped
// styles) like AskAce.vue, so a Chatwoot upgrade only needs the hook in
// ReplyTopPanel.vue re-applied.
import { ref, computed, nextTick, onMounted } from 'vue';
import { aceTicket } from 'dashboard/helper/aceAssist';

const props = defineProps({
  conversationId: { type: Number, default: null },
});
const emit = defineEmits(['close', 'created']);

// Which fields each request type shows, and which of them are required. The required
// sets mirror AceTicketService::REQUIRED_FIELDS — the server checks them again.
const TYPES = [
  {
    value: 'pg_link',
    label: 'Perfect Game link',
    fields: [
      'athlete_name',
      'nsid_id',
      'pg_id',
      'organization_or_event',
      'details',
    ],
    required: ['athlete_name', 'nsid_id', 'organization_or_event'],
  },
  {
    value: 'urgent_review',
    label: 'Urgent review',
    fields: ['athlete_name', 'nsid_id', 'organization_or_event', 'details'],
    required: ['athlete_name'],
  },
  {
    value: 'document_review',
    label: 'Document review',
    fields: ['athlete_name', 'nsid_id', 'document_type', 'details'],
    required: ['athlete_name', 'document_type'],
  },
  {
    value: 'general',
    label: 'Something else',
    fields: ['details'],
    required: ['details'],
  },
];
const FIELD_META = {
  athlete_name: { label: 'Full name', placeholder: 'e.g. Jordan Reed' },
  nsid_id: { label: 'NSID ID', placeholder: 'e.g. 123456' },
  pg_id: { label: 'Perfect Game ID', placeholder: 'If the customer has it' },
  document_type: {
    label: 'Document to review',
    placeholder: 'e.g. Physical, Medical',
  },
  organization_or_event: {
    label: 'Organization or event',
    placeholder: 'e.g. Perfect Game',
  },
  details: {
    label: 'Details',
    placeholder: 'What does the customer need?',
  },
};
// Short fields sit two to a row; details always takes the full width.
const WIDE_FIELDS = ['details', 'organization_or_event'];
const ROLE_LABELS = {
  director: 'Tournament Director / League Admin',
  coach: 'Coach / Team Admin',
  parent: 'Parent / Guardian',
  partner: 'Partner',
  visitor: 'Visitor',
};

const form = ref({
  type: 'general',
  athlete_name: '',
  nsid_id: '',
  pg_id: '',
  document_type: '',
  organization_or_event: '',
  details: '',
});
const loading = ref(true);
const saving = ref(false);
const loadError = ref('');
const requester = ref({ name: '', role: '', email: '' });
const existing = ref(null);
const errors = ref({}); // field key → message
const formError = ref('');
const created = ref(null);
const bodyRef = ref(null);

const currentType = computed(
  () => TYPES.find(t => t.value === form.value.type) || TYPES[3]
);
const isRequired = key => currentType.value.required.includes(key);
const fieldLabel = key => FIELD_META[key].label;
const initials = computed(
  () =>
    (requester.value.name || requester.value.email || '?')
      .split(/\s+/)
      .map(w => w[0])
      .join('')
      .slice(0, 2)
      .toUpperCase() || '?'
);
const locked = computed(
  () =>
    loading.value || saving.value || !!existing.value || !requester.value.email
);

const selectType = value => {
  form.value.type = value;
  errors.value = {};
};
const clearError = key => {
  if (errors.value[key]) {
    const next = { ...errors.value };
    delete next[key];
    errors.value = next;
  }
};

// Highlight every missing required field and bring the first one into view.
const showMissing = async keys => {
  const next = {};
  keys.forEach(k => {
    next[k] = `${FIELD_META[k] ? fieldLabel(k) : k} is required.`;
  });
  errors.value = next;
  await nextTick();
  const first =
    bodyRef.value && bodyRef.value.querySelector('.ct__input--error');
  if (first) {
    first.scrollIntoView({ behavior: 'smooth', block: 'center' });
    first.focus({ preventScroll: true });
  }
};

onMounted(async () => {
  try {
    const r = await aceTicket({
      conversationId: props.conversationId,
      action: 'prefill',
    });
    existing.value = r.existing || null;
    const who = r.requester || {};
    requester.value = {
      name: who.requester_name || '',
      role: ROLE_LABELS[who.requester_role] || who.requester_role || '',
      email: who.requester_email || '',
    };
    Object.assign(form.value, r.fields || {});
  } catch (e) {
    loadError.value =
      e && e.status === 404
        ? 'Tickets are switched off.'
        : (e && e.message) || 'Could not read the chat.';
  } finally {
    loading.value = false;
  }
});

const create = async () => {
  if (locked.value) return;
  formError.value = '';
  const missing = currentType.value.required.filter(
    k => !String(form.value[k] || '').trim()
  );
  if (missing.length) {
    await showMissing(missing);
    return;
  }

  saving.value = true;
  try {
    // Send only the fields this request type uses.
    const fields = { type: form.value.type };
    currentType.value.fields.forEach(k => {
      fields[k] = form.value[k];
    });
    const r = await aceTicket({
      conversationId: props.conversationId,
      action: 'create',
      fields,
    });
    created.value = r;
    emit('created', r);
  } catch (e) {
    const body = (e && e.body) || {};
    if (body.error === 'missing_fields') {
      await showMissing(body.missing || []);
    } else if (body.error === 'no_requester_email') {
      formError.value = 'This customer has no email address.';
    } else {
      formError.value = 'Could not create the ticket. Please try again.';
    }
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template --
       NSID internal agent tool — its labels are intentionally not i18n'd. -->
  <div class="ct__overlay" @click.self="emit('close')">
    <div class="ct__card" role="dialog" aria-label="Create ticket">
      <header class="ct__head">
        <span class="ct__icon"><span class="i-ph-ticket-fill" /></span>
        <div class="ct__titles">
          <strong class="ct__title">Create ticket</strong>
          <span class="ct__sub">Turn this chat into an email ticket</span>
        </div>
        <button
          type="button"
          class="ct__close"
          aria-label="Close"
          @click="emit('close')"
        >
          ×
        </button>
      </header>

      <!-- Created -->
      <div v-if="created" class="ct__done">
        <span class="ct__done-icon i-ph-check-circle-fill" />
        <p class="ct__done-title">
          {{
            created.duplicate
              ? `Already on ticket #${created.reference}`
              : `Ticket #${created.reference} created`
          }}
        </p>
        <p class="ct__done-text">
          {{
            created.duplicate
              ? 'This chat already has an open ticket.'
              : `${requester.email} has been emailed and this chat is closed.`
          }}
        </p>
      </div>

      <div v-else ref="bodyRef" class="ct__body">
        <!-- Requester -->
        <section class="ct__requester">
          <span class="ct__avatar">{{ initials }}</span>
          <div class="ct__who">
            <span class="ct__who-name">{{
              requester.name || 'Unknown requester'
            }}</span>
            <span v-if="requester.role" class="ct__badge">{{
              requester.role
            }}</span>
            <span class="ct__who-email">{{
              requester.email || 'No email address'
            }}</span>
          </div>
        </section>

        <div v-if="loading" class="ct__notice">
          <span class="ct__spinner" /> Ace is reading the chat…
        </div>
        <div v-else-if="loadError" class="ct__notice ct__notice--error">
          {{ loadError }}
        </div>
        <div v-else-if="existing" class="ct__notice ct__notice--warn">
          This chat already has ticket #{{ existing }} open.
        </div>
        <div v-else-if="!requester.email" class="ct__notice ct__notice--error">
          This customer has no email address, so a ticket can't be raised.
        </div>

        <fieldset class="ct__fields" :disabled="locked">
          <span class="ct__label">Request</span>
          <div class="ct__tabs" role="tablist">
            <button
              v-for="t in TYPES"
              :key="t.value"
              type="button"
              role="tab"
              class="ct__tab"
              :class="{ 'ct__tab--active': form.type === t.value }"
              :aria-selected="form.type === t.value"
              @click="selectType(t.value)"
            >
              {{ t.label }}
            </button>
          </div>

          <div class="ct__grid">
            <label
              v-for="key in currentType.fields"
              :key="key"
              class="ct__field"
              :class="{ 'ct__field--wide': WIDE_FIELDS.includes(key) }"
            >
              <span class="ct__label">
                {{ fieldLabel(key) }}
                <span v-if="isRequired(key)" class="ct__req">*</span>
              </span>
              <textarea
                v-if="key === 'details'"
                v-model="form[key]"
                maxlength="2000"
                class="ct__input ct__input--area reset-base"
                :class="{ 'ct__input--error': errors[key] }"
                :placeholder="FIELD_META[key].placeholder"
                @input="clearError(key)"
              />
              <input
                v-else
                v-model="form[key]"
                type="text"
                maxlength="255"
                class="ct__input reset-base"
                :class="{ 'ct__input--error': errors[key] }"
                :placeholder="FIELD_META[key].placeholder"
                @input="clearError(key)"
              />
              <span v-if="errors[key]" class="ct__error">{{
                errors[key]
              }}</span>
            </label>
          </div>
        </fieldset>
        <p v-if="formError" class="ct__notice ct__notice--error">
          {{ formError }}
        </p>
      </div>

      <footer class="ct__foot">
        <span v-if="!created" class="ct__foot-note">
          The customer is emailed and this chat closes.
        </span>
        <button type="button" class="ct__btn" @click="emit('close')">
          {{ created ? 'Done' : 'Cancel' }}
        </button>
        <button
          v-if="!created"
          type="button"
          class="ct__btn ct__btn--primary"
          :disabled="locked"
          @click="create"
        >
          {{ saving ? 'Creating…' : 'Create ticket' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.ct__overlay {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 32, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  font:
    14px/1.5 -apple-system,
    BlinkMacSystemFont,
    'Segoe UI',
    Roboto,
    Arial,
    sans-serif;
  color: #1f2733;
}
.ct__card {
  width: 520px;
  max-width: 94vw;
  max-height: 88vh;
  background: #fff;
  border-radius: 14px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.3);
}

/* Header */
.ct__head {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 20px;
  border-bottom: 1px solid #eef1f5;
}
.ct__icon {
  width: 34px;
  height: 34px;
  border-radius: 9px;
  background: #1f9d55;
  color: #fff;
  font-size: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex: none;
}
.ct__titles {
  display: flex;
  flex-direction: column;
  line-height: 1.25;
  margin-right: auto;
}
.ct__title {
  font-size: 16px;
}
.ct__sub {
  font-size: 12px;
  color: #8b95a1;
}
.ct__close {
  border: 0;
  background: none;
  font-size: 24px;
  line-height: 1;
  color: #8b95a1;
  cursor: pointer;
  padding: 0 4px;
}
.ct__close:hover {
  color: #1f2733;
}

/* Body */
.ct__body {
  flex: 1;
  overflow-y: auto;
  padding: 18px 20px 8px;
}
.ct__requester {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid #e6ebf0;
  border-radius: 10px;
  background: #f7f9fb;
  margin-bottom: 14px;
}
.ct__avatar {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: #e8f5ee;
  color: #1f7a45;
  font-weight: 700;
  font-size: 13px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex: none;
}
.ct__who {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 2px 8px;
  min-width: 0;
}
.ct__who-name {
  font-weight: 600;
}
.ct__badge {
  font-size: 11px;
  padding: 1px 8px;
  border-radius: 999px;
  background: #e8f5ee;
  color: #1f7a45;
}
.ct__who-email {
  flex-basis: 100%;
  font-size: 12.5px;
  color: #6b7684;
  overflow: hidden;
  text-overflow: ellipsis;
}

.ct__notice {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 0 14px;
  padding: 9px 12px;
  border-radius: 8px;
  font-size: 12.5px;
  background: #f4f6f8;
  color: #6b7684;
}
.ct__notice--warn {
  background: #fff7e6;
  color: #92590a;
}
.ct__notice--error {
  background: #fdf3f3;
  color: #b4232a;
}
.ct__spinner {
  width: 14px;
  height: 14px;
  border: 2px solid #cfd6de;
  border-top-color: #1f9d55;
  border-radius: 50%;
  animation: ct-spin 0.8s linear infinite;
}
@keyframes ct-spin {
  to {
    transform: rotate(360deg);
  }
}

.ct__fields {
  border: 0;
  margin: 0;
  padding: 0;
  min-width: 0;
}
.ct__label {
  display: block;
  margin-bottom: 5px;
  font-size: 12px;
  font-weight: 600;
  color: #4b5563;
}
.ct__req {
  color: #d92d20;
}

/* Request type tabs */
.ct__tabs {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 4px;
  padding: 4px;
  margin-bottom: 16px;
  background: #f1f3f5;
  border-radius: 10px;
}
.ct__tab {
  border: 0;
  background: none;
  border-radius: 7px;
  padding: 7px 4px;
  font: inherit;
  font-size: 12px;
  color: #4b5563;
  cursor: pointer;
}
.ct__tab:hover:not(:disabled) {
  color: #1f2733;
}
.ct__tab--active {
  background: #fff;
  color: #1f2733;
  font-weight: 600;
  box-shadow: 0 1px 3px rgba(15, 23, 32, 0.12);
}

/* Fields */
.ct__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px 14px;
}
.ct__field {
  display: block;
  min-width: 0;
}
.ct__field--wide {
  grid-column: 1 / -1;
}
.ct__input {
  display: block;
  width: 100%;
  margin: 0;
  padding: 9px 11px;
  border: 1px solid #d5dce4;
  border-radius: 8px;
  font: inherit;
  color: #1f2733;
  background: #fff;
  transition:
    border-color 0.12s,
    box-shadow 0.12s;
}
.ct__input::placeholder {
  color: #a3acb6;
}
.ct__input--area {
  height: 84px;
  resize: vertical;
}
.ct__input:focus {
  outline: none;
  border-color: #1f9d55;
  box-shadow: 0 0 0 3px rgba(31, 157, 85, 0.14);
}
.ct__input--error,
.ct__input--error:focus {
  border-color: #d92d20;
  box-shadow: 0 0 0 3px rgba(217, 45, 32, 0.12);
  background: #fffafa;
}
.ct__error {
  display: block;
  margin-top: 4px;
  font-size: 12px;
  color: #d92d20;
}
.ct__fields:disabled .ct__input,
.ct__fields:disabled .ct__tab {
  cursor: not-allowed;
}
.ct__fields:disabled .ct__input {
  background: #f4f6f8;
  color: #8b95a1;
}

/* Created */
.ct__done {
  padding: 36px 24px;
  text-align: center;
}
.ct__done-icon {
  display: inline-block;
  font-size: 48px;
  color: #1f9d55;
}
.ct__done-title {
  margin: 10px 0 4px;
  font-size: 17px;
  font-weight: 700;
}
.ct__done-text {
  margin: 0;
  color: #6b7684;
}

/* Footer */
.ct__foot {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  border-top: 1px solid #eef1f5;
}
.ct__foot-note {
  margin-right: auto;
  font-size: 12px;
  color: #8b95a1;
}
.ct__foot .ct__btn:first-child {
  margin-left: auto;
}
.ct__btn {
  border: 1px solid #e3e8ee;
  background: #fff;
  border-radius: 8px;
  padding: 8px 16px;
  font: inherit;
  color: #1f2733;
  cursor: pointer;
}
.ct__btn:hover:not(:disabled) {
  background: #f4f6f8;
}
.ct__btn--primary {
  background: #1f9d55;
  border-color: #1f9d55;
  color: #fff;
  font-weight: 600;
}
.ct__btn--primary:hover:not(:disabled) {
  background: #1f7a45;
}
.ct__btn:disabled {
  opacity: 0.55;
  cursor: default;
}

@media (max-width: 520px) {
  .ct__grid,
  .ct__tabs {
    grid-template-columns: 1fr 1fr;
  }
  .ct__field {
    grid-column: 1 / -1;
  }
}
</style>
