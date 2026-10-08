<script>
import { ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { aceControl, aceTicket } from 'dashboard/helper/aceAssist';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useTrack, useAlert } from 'dashboard/composables';
import { vOnClickOutside } from '@vueuse/components';
import { REPLY_EDITOR_MODES, CHAR_LENGTH_WARNING } from './constants';
import { CAPTAIN_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import NextButton from 'dashboard/components-next/button/Button.vue';
import EditorModeToggle from './EditorModeToggle.vue';
import CopilotMenuBar from './CopilotMenuBar.vue';
import AskAce from './AskAce.vue';
import CreateTicket from './CreateTicket.vue';

export default {
  name: 'ReplyTopPanel',
  components: {
    NextButton,
    EditorModeToggle,
    CopilotMenuBar,
    AskAce,
    CreateTicket,
  },
  directives: {
    OnClickOutside: vOnClickOutside,
  },
  props: {
    mode: {
      type: String,
      default: REPLY_EDITOR_MODES.REPLY,
    },
    isReplyRestricted: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
    conversationId: {
      type: Number,
      default: null,
    },
    isMessageLengthReachingThreshold: {
      type: Boolean,
      default: () => false,
    },
    charactersRemaining: {
      type: Number,
      default: () => 0,
    },
    editorContent: {
      type: String,
      default: undefined,
    },
    hasContent: {
      type: Boolean,
      default: false,
    },
  },
  emits: [
    'setReplyMode',
    'toggleEditorSize',
    'executeCopilotAction',
    'insertIntoReply',
  ],
  setup(props, { emit }) {
    const setReplyMode = mode => {
      emit('setReplyMode', mode);
    };
    const handleReplyClick = () => {
      if (props.isReplyRestricted) return;
      setReplyMode(REPLY_EDITOR_MODES.REPLY);
    };
    const handleNoteClick = () => {
      setReplyMode(REPLY_EDITOR_MODES.NOTE);
    };
    const handleModeToggle = () => {
      const newMode =
        props.mode === REPLY_EDITOR_MODES.REPLY
          ? REPLY_EDITOR_MODES.NOTE
          : REPLY_EDITOR_MODES.REPLY;
      setReplyMode(newMode);
    };

    const { captainTasksEnabled } = useCaptain();
    const showCopilotMenu = ref(false);
    const copilotToggleRef = ref(null);

    const handleCopilotAction = (actionKey, data) => {
      emit('executeCopilotAction', actionKey, data || props.editorContent);
      showCopilotMenu.value = false;
    };

    const toggleCopilotMenu = () => {
      const isOpening = !showCopilotMenu.value;
      if (isOpening) {
        useTrack(CAPTAIN_EVENTS.EDITOR_AI_MENU_OPENED, {
          conversationId: props.conversationId,
          entryPoint: 'top_panel',
        });
      }
      showCopilotMenu.value = isOpening;
    };

    const handleClickOutside = () => {
      showCopilotMenu.value = false;
    };

    // NSID: "Ask Ace" — open the agent-assist modal and close the menu. Owned HERE
    // (not in the transient menu) so clicks inside the modal can't be treated as an
    // outside-click that unmounts it.
    const showAskAce = ref(false);
    const handleAskAce = () => {
      showCopilotMenu.value = false;
      showAskAce.value = true;
    };
    // NSID: bubble the "Insert into reply" up to ReplyBox, which owns the editor.
    const handleInsertReply = text => {
      emit('insertIntoReply', text);
    };

    // NSID: "Take over chat / Hand back to Ace" (ACE #8) — stops Ace's CUSTOMER
    // auto-replies on THIS conversation so the agent answers manually; hand back turns
    // them on again. Distinct from "Ask Ace" (the internal Q&A). Taking over ALSO does
    // Chatwoot's native handoff (open + assign to me) so the "handled by a bot" banner
    // clears; handing back returns it to the bot (pending + unassign). The Chatwoot
    // parts run via the store — with the agent's own session/permissions — reliable
    // where a server token might be refused.
    const store = useStore();
    const currentUser = useMapGetter('getCurrentUser');
    const aceStopped = ref(false);
    const aceBusy = ref(false);
    const applyChatwootTakeover = async takingOver => {
      const id = props.conversationId;
      if (takingOver) {
        await store.dispatch('toggleStatus', {
          conversationId: id,
          status: wootConstants.STATUS_TYPE.OPEN,
        });
        const me = currentUser.value || {};
        const { avatar_url, ...rest } = me;
        await store.dispatch('setCurrentChatAssignee', {
          conversationId: id,
          assignee: { ...rest, thumbnail: avatar_url },
        });
        await store.dispatch('assignAgent', {
          conversationId: id,
          agentId: me.id || null,
        });
      } else {
        // Hand back to Ace: just unassign. We do NOT set status to 'pending' — that
        // re-triggers Chatwoot's Agent Bot routing, which surfaced a "error with the
        // agent bot" system message. Ace resumes on its own: our webhook answers the
        // next customer message once the stop flag is cleared, regardless of status.
        await store.dispatch('setCurrentChatAssignee', {
          conversationId: id,
          assignee: null,
        });
        await store.dispatch('assignAgent', {
          conversationId: id,
          agentId: null,
        });
      }
    };
    const refreshAceState = async () => {
      if (!props.conversationId) return;
      try {
        const r = await aceControl({
          conversationId: props.conversationId,
          action: 'status',
        });
        aceStopped.value = r.stopped;
      } catch (e) {
        /* non-fatal — leave the button as-is */
      }
    };
    const handleToggleAce = async () => {
      if (aceBusy.value || !props.conversationId) return;
      const takingOver = !aceStopped.value;
      aceBusy.value = true;
      try {
        const r = await aceControl({
          conversationId: props.conversationId,
          action: takingOver ? 'stop' : 'resume',
        });
        aceStopped.value = r.stopped;
        // Mirror the change in Chatwoot (status + assignment) so the UI is consistent
        // — this is what clears the "handled by a bot" banner. Non-fatal if it fails.
        try {
          await applyChatwootTakeover(r.stopped);
        } catch (e) {
          /* Chatwoot-side sync failed — the Ace flag still changed */
        }
        // Plain-language confirmation so the agent knows exactly what changed.
        useAlert(
          r.stopped
            ? "You've taken over — Ace will not auto-reply to this customer until you hand it back."
            : 'Ace is now auto-replying to this customer again.'
        );
      } catch (e) {
        useAlert(
          e && e.message
            ? e.message
            : 'Could not update Ace for this conversation. Please try again.'
        );
      } finally {
        aceBusy.value = false;
      }
    };
    // Sync the button to the live state when the open conversation changes.
    watch(() => props.conversationId, refreshAceState, { immediate: true });

    // NSID (#3797): "Create ticket" — Ace turns this chat into an email ticket in the
    // ticket inbox (the agent checks the details first). Shown only while tickets are
    // switched on in the NSID app (the status call answers 404 when they're off).
    const ticketsEnabled = ref(false);
    const showCreateTicket = ref(false);
    const refreshTicketsEnabled = async () => {
      if (!props.conversationId) return;
      try {
        const r = await aceTicket({
          conversationId: props.conversationId,
          action: 'status',
        });
        ticketsEnabled.value = !!r.enabled;
      } catch (e) {
        ticketsEnabled.value = false;
      }
    };
    watch(() => props.conversationId, refreshTicketsEnabled, {
      immediate: true,
    });

    const keyboardEvents = {
      'Alt+KeyP': {
        action: () => handleNoteClick(),
        allowOnFocusedInput: false,
      },
      'Alt+KeyL': {
        action: () => handleReplyClick(),
        allowOnFocusedInput: false,
      },
      // NSID: Alt+A opens the Ask Ace popup instantly (works while typing a reply).
      'Alt+KeyA': {
        action: () => handleAskAce(),
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);

    return {
      handleModeToggle,
      handleReplyClick,
      handleNoteClick,
      REPLY_EDITOR_MODES,
      captainTasksEnabled,
      handleCopilotAction,
      showCopilotMenu,
      copilotToggleRef,
      toggleCopilotMenu,
      handleClickOutside,
      showAskAce,
      handleAskAce,
      handleInsertReply,
      aceStopped,
      aceBusy,
      handleToggleAce,
      ticketsEnabled,
      showCreateTicket,
    };
  },
  computed: {
    replyButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.REPLY,
      };
    },
    noteButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.NOTE,
      };
    },
    charLengthClass() {
      return this.charactersRemaining < 0 ? 'text-n-ruby-9' : 'text-n-slate-11';
    },
    characterLengthWarning() {
      return this.charactersRemaining < 0
        ? `${-this.charactersRemaining} ${CHAR_LENGTH_WARNING.NEGATIVE}`
        : `${this.charactersRemaining} ${CHAR_LENGTH_WARNING.UNDER_50}`;
    },
  },
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template --
       NSID: the "Ask Ace" button title below is an internal-tool label, not i18n'd. -->
  <div
    class="flex justify-between gap-2 h-[3.25rem] items-center ltr:pl-3 ltr:pr-2 rtl:pr-3 rtl:pl-2"
  >
    <EditorModeToggle
      :mode="mode"
      :disabled="disabled"
      :is-reply-restricted="isReplyRestricted"
      @toggle-mode="handleModeToggle"
    />
    <div class="flex items-center mx-4 my-0">
      <div v-if="isMessageLengthReachingThreshold" class="text-xs">
        <span :class="charLengthClass">
          {{ characterLengthWarning }}
        </span>
      </div>
    </div>
    <div v-if="captainTasksEnabled" class="flex items-center gap-2">
      <!-- NSID: one-click Ask Ace — opens the same popup as the dropdown item. -->
      <NextButton
        ghost
        sm
        label="Ask Ace"
        icon="i-ph-sparkle-fill"
        class="text-n-violet-9 hover:enabled:!bg-n-violet-3 font-medium"
        :disabled="disabled || isEditorDisabled"
        title="Ask Ace (Alt+A)"
        @click="handleAskAce"
      />
      <!-- NSID (ACE #8): Take over / hand back — stops Ace's CUSTOMER auto-replies on
           this conversation so the agent answers manually; toggles to hand back. -->
      <NextButton
        ghost
        sm
        :label="aceStopped ? 'Hand back to Ace' : 'Take over chat'"
        :icon="aceStopped ? 'i-ph-play-fill' : 'i-ph-pause-fill'"
        :class="
          aceStopped
            ? 'text-n-teal-9 hover:enabled:!bg-n-teal-3 font-medium'
            : 'text-n-ruby-9 hover:enabled:!bg-n-ruby-3 font-medium'
        "
        :disabled="disabled || isEditorDisabled || aceBusy || !conversationId"
        :title="
          aceStopped
            ? 'Let Ace auto-reply to this customer again'
            : 'Stop Ace from auto-replying and answer this customer yourself'
        "
        @click="handleToggleAce"
      />
      <!-- NSID (#3797): turn this chat into an email ticket. -->
      <NextButton
        v-if="ticketsEnabled"
        ghost
        sm
        label="Create ticket"
        icon="i-ph-ticket-fill"
        class="text-n-blue-9 hover:enabled:!bg-n-blue-3 font-medium"
        :disabled="disabled || !conversationId"
        title="Turn this chat into an email ticket — the customer is emailed and the chat closes"
        @click="showCreateTicket = true"
      />
      <div class="relative">
        <NextButton
          ref="copilotToggleRef"
          ghost
          :disabled="disabled || isEditorDisabled"
          :class="{
            'text-n-violet-9 hover:enabled:!bg-n-violet-3': !showCopilotMenu,
            'text-n-violet-9 bg-n-violet-3': showCopilotMenu,
          }"
          sm
          icon="i-ph-sparkle-fill"
          @click="toggleCopilotMenu"
        />
        <CopilotMenuBar
          v-if="showCopilotMenu"
          v-on-click-outside="[
            handleClickOutside,
            { ignore: [copilotToggleRef] },
          ]"
          :has-selection="false"
          :has-content="hasContent"
          :conversation-id="conversationId"
          class="right-0 left-auto bottom-full mb-2"
          @execute-copilot-action="handleCopilotAction"
          @ask-ace="handleAskAce"
        />
      </div>
      <!-- NSID: Ask Ace modal — owned by this persistent panel + teleported to body,
           so it isn't tied to the menu's lifecycle or click-outside. -->
      <Teleport to="body">
        <AskAce
          v-if="showAskAce"
          :conversation-id="conversationId"
          @close="showAskAce = false"
          @insert="handleInsertReply"
        />
        <CreateTicket
          v-if="showCreateTicket"
          :conversation-id="conversationId"
          @close="showCreateTicket = false"
        />
      </Teleport>
      <NextButton
        ghost
        class="text-n-slate-11"
        sm
        icon="i-lucide-maximize-2"
        @click="$emit('toggleEditorSize')"
      />
    </div>
  </div>
</template>
