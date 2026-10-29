// NSID/Ace: state for Ace's animated avatar ("moods"). The host page turns it on
// per site with the `ace_avatar_moods` custom attribute (NSID Ace Controls);
// off, Ace keeps its normal static avatar everywhere.
import { ref } from 'vue';
import { MESSAGE_TYPE } from 'widget/helpers/constants';

const FRESH_MS = 2000;

export const aceMoodsEnabled = ref(false);

// The Ace message that just arrived over the websocket; it shows Hi/Done briefly.
export const aceFreshMessageId = ref(null);
let freshTimer = null;

export const isAceSender = sender => sender?.type === 'agent_bot';

export const setAceMoodsFromAttributes = (attributes = {}) => {
  if (!attributes || !('ace_avatar_moods' in attributes)) return;
  const value = attributes.ace_avatar_moods;
  aceMoodsEnabled.value = [true, 'true', 1, '1'].includes(value);
};

export const markAceMessageArrived = message => {
  if (!isAceSender(message?.sender)) return;
  aceFreshMessageId.value = message.id;
  clearTimeout(freshTimer);
  freshTimer = setTimeout(() => {
    aceFreshMessageId.value = null;
  }, FRESH_MS);
};

// Ace is handling the chat until a human agent replies: the newest outgoing
// message with a sender decides. Used for the typing bubble, whose typing
// event does not say who is typing.
export const isAceHandling = (messages = []) => {
  const lastReply = [...messages]
    .reverse()
    .find(m => m.message_type === MESSAGE_TYPE.OUTGOING && m.sender);
  return !lastReply || isAceSender(lastReply.sender);
};
