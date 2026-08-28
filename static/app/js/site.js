(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.querySelectorAll("video").forEach((video) => {
    const play = () => {
      const p = video.play();
      if (p && typeof p.catch === "function") p.catch(() => {});
    };
    if (video.readyState >= 2) play();
    else video.addEventListener("loadeddata", play, { once: true });
  });

  const topbar = document.getElementById("topbar");
  const onScroll = () => {
    if (!topbar) return;
    topbar.classList.toggle("is-scrolled", window.scrollY > 8);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  const menuBtn = document.getElementById("menuBtn");
  const mobileNav = document.getElementById("mobileNav");
  if (menuBtn && mobileNav) {
    menuBtn.addEventListener("click", () => {
      const open = mobileNav.classList.toggle("is-open");
      mobileNav.hidden = !open;
    });
    mobileNav.querySelectorAll("a").forEach((a) => {
      a.addEventListener("click", () => {
        mobileNav.classList.remove("is-open");
        mobileNav.hidden = true;
      });
    });
  }

  const autoSlide = (trackId, visibleDesktop, visibleTablet, visibleMobile, delayMs) => {
    const track = document.getElementById(trackId);
    if (!track) return;
    const cards = [...track.children];
    if (cards.length < 2 || reduce) return;

    let index = 0;
    const gap = 16;

    const visibleCount = () => {
      const w = window.innerWidth;
      if (w <= 640) return visibleMobile;
      if (w <= 980) return visibleTablet;
      return visibleDesktop;
    };

    const step = () => {
      const vis = visibleCount();
      const max = Math.max(0, cards.length - vis);
      index = index >= max ? 0 : index + 1;
      const card = cards[0];
      const width = card.getBoundingClientRect().width;
      track.style.transform = `translateX(-${index * (width + gap)}px)`;
    };

    setInterval(step, delayMs);
    window.addEventListener(
      "resize",
      () => {
        index = 0;
        track.style.transform = "translateX(0)";
      },
      { passive: true }
    );
  };

  // Hero banner
  const heroTrack = document.getElementById("heroTrack");
  const heroSlides = heroTrack ? [...heroTrack.querySelectorAll(".hero-slide")] : [];
  if (heroTrack && heroSlides.length > 1 && !reduce) {
    let index = 0;
    setInterval(() => {
      index = (index + 1) % heroSlides.length;
      heroTrack.style.transform = `translateX(-${index * 100}%)`;
      heroSlides.forEach((slide, i) => slide.classList.toggle("is-active", i === index));
    }, 5000);
  }

  const demoSlides = document.querySelectorAll("#demoSlideTrack .demo-slide");
  if (demoSlides.length > 1 && !reduce) {
    let demoIndex = 0;
    setInterval(() => {
      demoIndex = (demoIndex + 1) % demoSlides.length;
      demoSlides.forEach((slide, i) => slide.classList.toggle("is-active", i === demoIndex));
    }, 3200);
  }

  const demoVideo = document.querySelector("#demoMedia .demo-video");
  if (demoVideo) {
    const playDemo = () => {
      const p = demoVideo.play();
      if (p && typeof p.catch === "function") p.catch(() => {});
    };
    if (demoVideo.readyState >= 2) playDemo();
    else demoVideo.addEventListener("loadeddata", playDemo, { once: true });
    demoVideo.addEventListener("error", () => {
      demoVideo.style.display = "none";
    });
  }

  autoSlide("instructorTrack", 3, 2, 1, 3500);
  autoSlide("quoteTrack", 3, 2, 1, 4200);

  /* ------------------------------------------------------------------
     Repeatable scroll reveals (replay every time you scroll into view)
     ------------------------------------------------------------------ */
  const selectors = [
    "#about .section-head",
    "#product .section-head",
    "#product .feature-grid article",
    "#demo .showcase-frame",
    "#instructors .instructors-copy",
    "#instructors .instructor-slider",
    "#stories .section-head",
    "#stories .quote-slider",
    "#partners",
    "#affiliate .affiliate-copy",
    "#affiliate .affiliate-perks li",
    ".trust-strip .trust-inner article",
    "#get-app",
  ];

  const scrollItems = [];
  selectors.forEach((sel) => {
    document.querySelectorAll(sel).forEach((el) => {
      el.classList.add("scroll-reveal");
      scrollItems.push(el);
    });
  });

  document.querySelectorAll(".feature-grid").forEach((grid) => {
    [...grid.children].forEach((child, i) => {
      child.classList.add(i % 2 === 0 ? "reveal-left" : "reveal-right");
      child.dataset.d = String(i * 90);
    });
  });

  document.querySelectorAll(".trust-strip .trust-inner article").forEach((el, i) => {
    el.classList.add("reveal-pop");
    el.dataset.d = String(i * 80);
  });

  document.querySelectorAll("#affiliate .affiliate-perks li").forEach((el, i) => {
    el.classList.add("reveal-pop");
    el.dataset.d = String(120 + i * 100);
  });

  document.querySelectorAll("#demo .showcase-frame").forEach((el) => el.classList.add("reveal-pop"));
  document.querySelectorAll("#get-app").forEach((el) => el.classList.add("reveal-pop"));

  const delayTimers = new WeakMap();

  const show = (el) => {
    const prev = delayTimers.get(el);
    if (prev) window.clearTimeout(prev);
    const delay = Number(el.dataset.d || 0);
    const t = window.setTimeout(() => {
      el.classList.add("is-in");
      el.classList.add("is-animating");
      window.setTimeout(() => el.classList.remove("is-animating"), 1200);
    }, delay);
    delayTimers.set(el, t);
  };

  const hide = (el) => {
    const prev = delayTimers.get(el);
    if (prev) window.clearTimeout(prev);
    el.classList.remove("is-in", "is-animating");
  };

  if (reduce) {
    scrollItems.forEach((el) => el.classList.add("is-in"));
    document.querySelectorAll(".reveal-drop").forEach((el) => el.classList.add("is-in"));
    document.querySelectorAll(".partners-track").forEach((el) => {
      el.style.animation = "none";
    });
  } else if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) show(entry.target);
          else hide(entry.target);
        });
      },
      { threshold: 0.18, rootMargin: "0px 0px -8% 0px" }
    );
    scrollItems.forEach((el) => io.observe(el));
  } else {
    scrollItems.forEach((el) => el.classList.add("is-in"));
  }

  /* Hero entrance + replay when hero re-enters */
  const heroCopy = document.querySelectorAll(".hero-banner .reveal-drop");
  if (!reduce && heroCopy.length) {
    const heroIO = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            heroCopy.forEach((el, i) => {
              el.classList.remove("is-in");
              window.setTimeout(() => el.classList.add("is-in"), 180 + i * 160);
            });
          } else {
            heroCopy.forEach((el) => el.classList.remove("is-in"));
          }
        });
      },
      { threshold: 0.35 }
    );
    const hero = document.querySelector(".hero-banner");
    if (hero) heroIO.observe(hero);
  }

  /* Floating orbs behind page */
  if (!reduce) {
    const fx = document.createElement("div");
    fx.className = "page-fx";
    fx.setAttribute("aria-hidden", "true");
    fx.innerHTML =
      '<span class="fx-orb fx-a"></span><span class="fx-orb fx-b"></span><span class="fx-orb fx-c"></span>';
    document.body.appendChild(fx);
  }

  /* Parallax hero + trust strip tilt */
  if (!reduce) {
    const heroInner = document.querySelector(".hero-inner");
    const sparkle = document.querySelector(".hero-sparkle");
    window.addEventListener(
      "scroll",
      () => {
        const y = window.scrollY;
        if (heroInner && y < window.innerHeight) {
          heroInner.style.transform = `translate3d(0, ${y * 0.18}px, 0)`;
        }
        if (sparkle && y < window.innerHeight) {
          sparkle.style.transform = `translate3d(0, ${y * 0.08}px, 0) scale(${1 + y * 0.00015})`;
        }
      },
      { passive: true }
    );
  }

  /* Magnetic CTA buttons */
  if (!reduce) {
    document.querySelectorAll(".btn-join, .btn-gold, .btn-red, .btn-ending-solid").forEach((btn) => {
      btn.classList.add("btn-magnetic");
      btn.addEventListener("pointermove", (e) => {
        const r = btn.getBoundingClientRect();
        const x = e.clientX - r.left - r.width / 2;
        const y = e.clientY - r.top - r.height / 2;
        btn.style.transform = `translate(${x * 0.18}px, ${y * 0.22}px)`;
      });
      btn.addEventListener("pointerleave", () => {
        btn.style.transform = "";
      });
    });
  }

  /* Cursor glow trail on desktop */
  if (!reduce && window.matchMedia("(pointer:fine)").matches) {
    const glow = document.createElement("div");
    glow.className = "cursor-glow";
    glow.setAttribute("aria-hidden", "true");
    document.body.appendChild(glow);
    window.addEventListener(
      "pointermove",
      (e) => {
        glow.style.transform = `translate(${e.clientX - 90}px, ${e.clientY - 90}px)`;
        glow.classList.add("is-on");
      },
      { passive: true }
    );
  }
})();
