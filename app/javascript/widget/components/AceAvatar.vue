<script setup>
// NSID/Ace: Ace's face with its moods, from Ace_Friendly_Assets_v2
// (animation/ace-animation-demo.html). Inline SVG + CSS, no images, so it is
// sharp at any size and adds no network requests.
defineProps({
  // default | hi | thinking | typing | done
  mood: {
    type: String,
    default: 'default',
  },
  size: {
    type: Number,
    default: 32,
  },
});
</script>

<template>
  <span
    class="ace-avatar"
    :data-mood="mood"
    :style="{ width: `${size}px`, height: `${size}px` }"
    role="img"
    aria-label="Ace, AI assistant"
  >
    <!-- keyed on mood so the one-shot hop/pop replay on every change -->
    <svg :key="mood" viewBox="0 0 64 64" aria-hidden="true">
      <g class="face">
        <circle cx="32" cy="32" r="30" fill="#00882A" />
        <g class="part m-default m-typing m-done">
          <g class="eyes-open">
            <ellipse cx="23" cy="27" rx="4.6" ry="6.4" fill="#fff" />
            <ellipse cx="41" cy="27" rx="4.6" ry="6.4" fill="#fff" />
            <circle cx="24.3" cy="28.5" r="1.9" fill="#0B1F3A" />
            <circle cx="42.3" cy="28.5" r="1.9" fill="#0B1F3A" />
          </g>
        </g>
        <path
          class="part m-default m-done"
          d="M25.5 41.5 Q32 47 38.5 41.5"
          fill="none"
          stroke="#fff"
          stroke-width="3.4"
          stroke-linecap="round"
        />
        <g class="part m-hi" fill="none" stroke="#fff" stroke-linecap="round">
          <path
            d="M18.5 28 Q23 21 27.5 28 M36.5 28 Q41 21 45.5 28"
            stroke-width="3.8"
          />
          <path d="M24.5 40.5 Q32 49 39.5 40.5" stroke-width="3.6" />
        </g>
        <g class="part m-thinking">
          <ellipse cx="23" cy="27" rx="4.6" ry="6.4" fill="#fff" />
          <ellipse cx="41" cy="27" rx="4.6" ry="6.4" fill="#fff" />
          <g class="pupils-up">
            <circle cx="25.2" cy="24.6" r="1.9" fill="#0B1F3A" />
            <circle cx="43.2" cy="24.6" r="1.9" fill="#0B1F3A" />
          </g>
          <path
            d="M27 43 H37"
            stroke="#fff"
            stroke-width="3.4"
            stroke-linecap="round"
          />
        </g>
        <g class="part m-typing" fill="#fff">
          <circle class="dot" cx="24.5" cy="43" r="2.5" />
          <circle class="dot" cx="32" cy="43" r="2.5" />
          <circle class="dot" cx="39.5" cy="43" r="2.5" />
        </g>
        <path
          class="part m-done sparkle"
          d="M49 8 C49.55 11.95 49.55 11.95 53.5 12.5 C49.55 13.05 49.55 13.05 49 17 C48.45 13.05 48.45 13.05 44.5 12.5 C48.45 11.95 48.45 11.95 49 8 Z"
          fill="#fff"
        />
      </g>
    </svg>
  </span>
</template>

<style lang="scss" scoped>
// Timings copied from the demo.
.ace-avatar {
  @apply block flex-shrink-0;

  svg {
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .part {
    display: none;
  }

  &[data-mood='default'] .m-default,
  &[data-mood='hi'] .m-hi,
  &[data-mood='thinking'] .m-thinking,
  &[data-mood='typing'] .m-typing,
  &[data-mood='done'] .m-done {
    display: inline;
  }

  .face {
    transform-origin: 32px 32px;
    animation: ace-breathe 4s ease-in-out infinite;
  }

  .eyes-open {
    transform-origin: 32px 27px;
    animation: ace-blink 5s infinite;
  }

  &[data-mood='hi'] .face {
    animation: ace-hop 0.6s ease-out 1;
  }

  .pupils-up {
    animation: ace-glance 2.4s ease-in-out infinite;
  }

  .dot {
    animation: ace-dot 1s ease-in-out infinite;

    &:nth-child(2) {
      animation-delay: 0.15s;
    }

    &:nth-child(3) {
      animation-delay: 0.3s;
    }
  }

  .sparkle {
    transform-origin: 49px 12.5px;
    animation:
      ace-pop 0.5s cubic-bezier(0.3, 1.6, 0.5, 1) 1,
      ace-twinkle 2.5s ease-in-out 0.5s infinite;
  }
}

@media (prefers-reduced-motion: reduce) {
  .ace-avatar * {
    animation: none !important;
  }
}

@keyframes ace-breathe {
  50% {
    transform: scale(1.03);
  }
}

@keyframes ace-blink {
  0%,
  94%,
  100% {
    transform: scaleY(1);
  }

  97% {
    transform: scaleY(0.1);
  }
}

@keyframes ace-hop {
  30% {
    transform: translateY(-4px);
  }

  60% {
    transform: translateY(0);
  }
}

@keyframes ace-glance {
  0%,
  100% {
    transform: translateX(-1px);
  }

  50% {
    transform: translateX(1.5px);
  }
}

@keyframes ace-dot {
  0%,
  60%,
  100% {
    transform: translateY(0);
  }

  30% {
    transform: translateY(-2.5px);
  }
}

@keyframes ace-pop {
  0% {
    transform: scale(0);
  }

  100% {
    transform: scale(1);
  }
}

@keyframes ace-twinkle {
  50% {
    transform: scale(0.75);
  }
}
</style>
