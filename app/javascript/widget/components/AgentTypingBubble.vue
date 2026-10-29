<script>
import AceAvatar from 'widget/components/AceAvatar.vue';
import { aceMoodsEnabled, isAceHandling } from 'widget/helpers/aceMoods';

// NSID/Ace: while Ace (not a human agent) is answering, the typing bubble shows
// Ace's face: nothing for the first 0.3s (a fast reply skips Thinking), then
// Thinking, then Typing. Ace's reply is posted in one piece, so "typing" means
// the typing indicator is on, not text streaming in.
const THINKING_AFTER_MS = 300;
const TYPING_AFTER_MS = 1500;

export default {
  name: 'AgentTypingBubble',
  components: { AceAvatar },
  data() {
    return { aceMood: null, timers: [] };
  },
  computed: {
    showAceAvatar() {
      return (
        aceMoodsEnabled.value &&
        isAceHandling(
          Object.values(this.$store.getters['conversation/getConversation'])
        )
      );
    },
  },
  mounted() {
    this.timers = [
      setTimeout(() => {
        this.aceMood = 'thinking';
      }, THINKING_AFTER_MS),
      setTimeout(() => {
        this.aceMood = 'typing';
      }, TYPING_AFTER_MS),
    ];
  },
  beforeUnmount() {
    this.timers.forEach(clearTimeout);
  },
};
</script>

<template>
  <div class="agent-message-wrap sticky bottom-1">
    <div class="agent-message">
      <div class="avatar-wrap" :class="{ 'is-ace': showAceAvatar }">
        <AceAvatar v-if="showAceAvatar && aceMood" :mood="aceMood" :size="32" />
      </div>
      <div class="message-wrap mt-2">
        <div
          class="chat-bubble agent typing-bubble bg-n-background dark:bg-n-solid-3"
        >
          <img
            src="assets/images/typing.gif"
            alt="Agent is typing a message"
            class="!w-full"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.typing-bubble {
  @apply max-w-[2.4rem] p-2 ltr:rounded-bl-[1.25rem] rtl:rounded-br-[1.25rem] ltr:rounded-tl-lg rtl:rounded-tr-lg;
}
</style>
