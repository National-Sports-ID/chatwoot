<script>
import { mapGetters } from 'vuex';
import { IFrameHelper, RNHelper } from 'widget/helpers/utils';
import { popoutChatWindow } from '../helpers/popoutHelper';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import configMixin from 'widget/mixins/configMixin';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

export default {
  name: 'HeaderActions',
  components: { FluentIcon },
  mixins: [configMixin],
  props: {
    showPopoutButton: {
      type: Boolean,
      default: false,
    },
    showEndConversationButton: {
      type: Boolean,
      default: true,
    },
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      canUserEndConversation: 'appConfig/getCanUserEndConversation',
      currentUser: 'contacts/getCurrentUser',
    }),
    // NSID: show a "Switch Role" action when the host page flagged the visitor as
    // having linked accounts (set via the `ace_can_switch` contact attribute).
    canSwitchRole() {
      const attrs = (this.currentUser && this.currentUser.custom_attributes) || {};
      const v = attrs.ace_can_switch;
      return v === true || v === 'true' || v === 1 || v === '1';
    },
    canLeaveConversation() {
      return [
        CONVERSATION_STATUS.OPEN,
        CONVERSATION_STATUS.SNOOZED,
        CONVERSATION_STATUS.PENDING,
      ].includes(this.conversationStatus);
    },
    isIframe() {
      return IFrameHelper.isIFrame();
    },
    isRNWebView() {
      return RNHelper.isRNWebView();
    },
    showHeaderActions() {
      return this.isIframe || this.isRNWebView || this.hasWidgetOptions;
    },
    conversationStatus() {
      return this.conversationAttributes.status;
    },
    hasWidgetOptions() {
      return this.showPopoutButton || this.conversationStatus === 'open';
    },
  },
  methods: {
    popoutWindow() {
      this.closeWindow();
      const {
        location: { origin },
        chatwootWebChannel: { websiteToken },
        authToken,
      } = window;
      popoutChatWindow(
        origin,
        websiteToken,
        this.$root.$i18n.locale,
        authToken
      );
    },
    closeWindow() {
      if (IFrameHelper.isIFrame()) {
        IFrameHelper.sendMessage({ event: 'closeWindow' });
      } else if (RNHelper.isRNWebView) {
        RNHelper.sendMessage({ type: 'close-widget' });
      }
    },
    resolveConversation() {
      this.$store.dispatch('conversation/resolveConversation');
    },
    // NSID: ask the host page to open its "Switch User" role modal.
    switchRole() {
      IFrameHelper.sendMessage({ event: 'ace-switch-role' });
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="showHeaderActions" class="actions flex items-center gap-3">
    <button
      v-if="canSwitchRole"
      class="ace-switch-role"
      title="Switch your NSID role"
      @click="switchRole"
    >
      <span class="ace-switch-role__icon">&#8645;</span>
      <span class="ace-switch-role__label">Switch Role</span>
    </button>
    <button
      v-if="
        canLeaveConversation &&
        canUserEndConversation &&
        hasEndConversationEnabled &&
        showEndConversationButton
      "
      class="button transparent compact"
      :title="$t('END_CONVERSATION')"
      @click="resolveConversation"
    >
      <FluentIcon icon="sign-out" size="22" class="text-n-slate-12" />
    </button>
    <button
      v-if="showPopoutButton"
      class="button transparent compact new-window--button"
      @click="popoutWindow"
    >
      <FluentIcon icon="open" size="22" class="text-n-slate-12" />
    </button>
    <button
      class="button transparent compact close-button"
      :class="{
        'rn-close-button': isRNWebView,
      }"
      @click="closeWindow"
    >
      <FluentIcon icon="dismiss" size="24" class="text-n-slate-12" />
    </button>
  </div>
</template>

<style scoped lang="scss">
.actions {
  .close-button {
    display: none;
  }

  .rn-close-button {
    display: block !important;
  }
}

// NSID "Switch Role" — native header pill, matches the app's green ↕ switch.
.ace-switch-role {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 3px 10px;
  border: 1px solid #e4e6eb;
  border-radius: 14px;
  background: #ffffff;
  color: #55585d;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.4;
  white-space: nowrap;
  cursor: pointer;

  &__icon {
    color: #6b7280; // gray up/down arrows
    font-size: 13px;
    font-weight: 700;
    line-height: 1;
  }

  &:hover {
    border-color: #6b7280;
  }
}

// Collapse to icon-only on mobile ONLY. A CSS media query can't be used here —
// the widget iframe is ~376px wide on desktop too, so `max-width` always matched
// and hid the label everywhere. Instead we key off the widget's own `is-mobile`
// class (set on the app root from the parent SDK), which is the real device
// signal. Desktop keeps the full "⇅ Switch Role" pill.
:global(.is-mobile) .ace-switch-role {
  padding: 4px 7px;
}
:global(.is-mobile) .ace-switch-role__label {
  display: none;
}
:global(.is-mobile) .ace-switch-role__icon {
  font-size: 15px;
}
</style>