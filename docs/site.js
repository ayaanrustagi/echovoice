document.documentElement.classList.add("js");

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* Stagger hero sticker entrances */
document.querySelectorAll(".stage .sticker").forEach((el, i) => el.style.setProperty("--i", i));

/* Hero demo: a finger taps a tile on the real board screenshot, and what it
   says pops out beside the phone. Positions are tile centres in the screenshot. */
const TAPS = [
  { x: 27, y: 38.5, say: "Can I have some water?" },
  { x: 73, y: 21, say: "No." },
  { x: 27, y: 56, say: "I'm in pain." },
  { x: 73, y: 56, say: "I'm hungry." },
  { x: 27, y: 21, say: "Yes." },
  { x: 73, y: 87, say: "I'm okay." },
];
const tap = document.getElementById("tap");
const said = document.getElementById("said");
const saidText = document.getElementById("saidText");
let tapIndex = 0;

function restart(el, cls) {
  el.classList.remove(cls);
  void el.offsetWidth; // reflow so the animation plays again
  el.classList.add(cls);
}

function playTap() {
  const { x, y, say } = TAPS[tapIndex % TAPS.length];
  tapIndex += 1;
  tap.style.setProperty("--tx", `${x}%`);
  tap.style.setProperty("--ty", `${y}%`);
  setTimeout(() => {
    restart(tap, "press");
    saidText.textContent = say;
    said.style.setProperty("--by", `${Math.max(4, y - 10)}%`);
    setTimeout(() => restart(said, "show"), 180);
  }, 700);
}

if (reduceMotion) {
  said.style.opacity = "1";
  said.style.scale = "1";
} else {
  setTimeout(() => {
    playTap();
    setInterval(playTap, 3200);
  }, 1900);
}

/* Scroll reveals */
const revealer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add("in");
    revealer.unobserve(entry.target);
  });
}, { rootMargin: "0px 0px -10% 0px" });

document.querySelectorAll(".pop, .slide-up").forEach((el) => {
  const siblings = [...el.parentElement.children].filter((c) => c.classList.contains("pop"));
  const index = siblings.indexOf(el);
  if (index > 0) el.style.setProperty("--delay", `${index * 0.08}s`);
  revealer.observe(el);
});

/* Header: the glass pill slides in once the plain top bar has scrolled away,
   and highlights the section in view */
const nav = document.querySelector(".nav");
const navLinks = [...document.querySelectorAll(".nav-links a")];
const setShown = () => nav.classList.toggle("shown", window.scrollY > 140);
setShown();
window.addEventListener("scroll", setShown, { passive: true });

const sectionSpy = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    navLinks.forEach((a) => a.classList.toggle("active", a.hash === `#${entry.target.id}`));
  });
}, { rootMargin: "-45% 0px -50% 0px" });
navLinks.forEach((a) => {
  const target = document.querySelector(a.hash);
  if (target) sectionSpy.observe(target);
});

/* Scroll-linked motion, all written in one rAF per scroll:
   --hp  hero phone flattens out of its tilt as you scroll (0 → 1)
   --p   device spreads fan apart as they cross the viewport (0 → 1)
   --sy  any [data-speed] element drifts at its own speed (none use it right now) */
const tilt = document.querySelector(".hero-tilt");
const scrubbed = [...document.querySelectorAll("[data-scrub]")];
const floaters = [...document.querySelectorAll("[data-speed]")];
let ticking = false;

function onScrollFrame() {
  const vh = window.innerHeight;
  tilt.style.setProperty("--hp", Math.min(1, window.scrollY / (vh * 0.6)).toFixed(3));
  scrubbed.forEach((el) => {
    const rect = el.getBoundingClientRect();
    const progress = Math.min(1, Math.max(0, (vh - rect.top) / (vh + rect.height * 0.5)));
    el.style.setProperty("--p", progress.toFixed(3));
  });
  floaters.forEach((el) => {
    const rect = el.getBoundingClientRect();
    const fromCentre = rect.top + rect.height / 2 - vh / 2;
    el.style.setProperty("--sy", `${(fromCentre * Number(el.dataset.speed)).toFixed(1)}px`);
  });
  ticking = false;
}

if (reduceMotion) {
  tilt.style.setProperty("--hp", "1");
} else {
  window.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(onScrollFrame);
  }, { passive: true });
  onScrollFrame();
}
