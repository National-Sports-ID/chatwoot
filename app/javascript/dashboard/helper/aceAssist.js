/* eslint-disable no-underscore-dangle */
// NSID: shared client for the Ace agent-assist endpoint (/ace/agent-assist/ask).
// Used by the "Ask Ace" modal (AskAce.vue) AND the reply-box AI actions
// (Summarize / Suggest a reply), so the endpoint host + optional shared secret
// live in ONE place instead of drifting across components. The window.__ACE_*__
// globals are deliberate runtime overrides, hence the file-level disable above.

// Optional shared secret guarding the endpoint. Resolved at CALL TIME (like the URL)
// so it can be changed from Super Admin → Settings with no rebuild:
//   1. window.__ACE_ASSIST_KEY__ — runtime override (rare)
//   2. Super Admin → Settings → "Ace Agent-Assist Shared Key" (ACE_ASSIST_KEY,
//      surfaced on window.globalConfig)
// Leave both blank to disable (origin + rate limit still apply). When set it MUST
// match the `ace_agent_assist_secret` simple_option on the NSID app. It reaches the
// browser (client-visible), so it only raises the bar past origin-spoofing — rotate
// it on both sides if it leaks.
export function aceAssistKey() {
  if (typeof window === 'undefined') return '';
  const override = window.__ACE_ASSIST_KEY__;
  const configured = window.globalConfig && window.globalConfig.ACE_ASSIST_KEY;
  return String(override || configured || '').trim();
}

// Base URL of the NSID app that serves /ace/agent-assist/ask. NO domain is
// hardcoded — it comes ONLY from configuration, set per Chatwoot deployment:
//   1. window.__ACE_ASSIST_BASE__  — runtime override (rare, e.g. a quick test)
//   2. Super Admin → Settings → "Ace Agent-Assist Base URL" (ACE_ASSIST_BASE_URL,
//      surfaced on window.globalConfig) — the normal way to point each deployment
//      (live / redesign / local) at its backend, with no rebuild
// If neither is set, there is no URL and the feature reports "not configured"
// rather than guessing a host.
function aceAssistBase() {
  if (typeof window === 'undefined') return '';
  const override = window.__ACE_ASSIST_BASE__;
  const configured =
    window.globalConfig && window.globalConfig.ACE_ASSIST_BASE_URL;
  const chosen = override || configured || '';
  return String(chosen).trim().replace(/\/+$/, '');
}

// Empty string when unconfigured — callers must treat that as "not set up yet".
export function aceAskUrl() {
  const base = aceAssistBase();
  return base ? `${base}/ace/agent-assist/ask` : '';
}

export function aceAssistHeaders() {
  const headers = { 'Content-Type': 'application/json' };
  const key = aceAssistKey();
  if (key) headers['X-Ace-Assist-Key'] = key;
  return headers;
}

/**
 * Call the agent-assist endpoint. Resolves to the answer string; throws an Error
 * (with `.status`) carrying the server's message on failure.
 *
 * @param {{mode?: string, question?: string, transcript?: string, history?: Array,
 *          text?: string, transform?: string, tone?: string}} opts
 * @returns {Promise<string>}
 */
export async function askAce({
  mode = 'ask',
  question = '',
  transcript = '',
  history = [],
  text = '',
  transform = '',
  tone = '',
} = {}) {
  const url = aceAskUrl();
  if (!url) {
    const err = new Error(
      'Ace is not configured yet. An admin needs to set the "Ace Agent-Assist Base URL" in Super Admin → Settings.'
    );
    err.status = 0;
    throw err;
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: aceAssistHeaders(),
    body: JSON.stringify({
      mode,
      question,
      transcript,
      history,
      text,
      transform,
      tone,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (res.ok && body.answer) return body.answer;
  const err = new Error(
    body.error || 'Ace could not answer just now. Please try again.'
  );
  err.status = res.status;
  throw err;
}
