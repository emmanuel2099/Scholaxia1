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

  autoSlide("instructorTrack", 3, 2, 1, 3500);
  autoSlide("quoteTrack", 3, 2, 1, 4200);

  /* ------------------------------------------------------------------
     Repeatable scroll reveals (replay every time you scroll into view)
     ------------------------------------------------------------------ */
  const selectors = [
    "#about .section-head",
    "#product .section-head",
    "#product .feature-grid article",
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

/* ─────────────────────────────────────────────────────────────
   TEACHERS — fetch from API and render into #teacherGrid
   GET https://scholaxia1.onrender.com/api/v1/profiles/teachers
   Response: [{ user_id, full_name, subjects[], bio, profile_picture }]
   ───────────────────────────────────────────────────────────── */
(() => {
  const API  = 'https://scholaxia1.onrender.com/api/v1/profiles/teachers';
  const grid = document.getElementById('teacherGrid');
  if (!grid) return;
  let teacherSlideTimer = null;

  function startTeacherSlider() {
    if (teacherSlideTimer) clearInterval(teacherSlideTimer);
    const cards = Array.from(grid.querySelectorAll('.instructor-card'));
    if (cards.length < 2 || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let index = 0;
    teacherSlideTimer = setInterval(() => {
      const first = cards[0];
      if (!first || !first.isConnected) return;
      const gap = parseFloat(getComputedStyle(grid).gap) || 20;
      const step = first.getBoundingClientRect().width + gap;
      const maxScroll = Math.max(0, grid.scrollWidth - grid.clientWidth);
      index += 1;
      const next = index * step;
      if (next >= maxScroll + step * 0.5) {
        index = 0;
        grid.scrollTo({ left: 0, behavior: 'smooth' });
      } else {
        grid.scrollTo({ left: Math.min(next, maxScroll), behavior: 'smooth' });
      }
    }, 3200);
  }

  /* initials from full name */
  function initials(name) {
    return (name || '').split(' ').filter(Boolean).slice(0, 2)
      .map(w => w[0].toUpperCase()).join('');
  }

  /* up to 3 subjects joined by · */
  function subjectLine(subjects) {
    if (!Array.isArray(subjects) || subjects.length === 0) return 'Instructor';
    return subjects.slice(0, 3).join(' · ') + (subjects.length > 3 ? ' …' : '');
  }

  /* build one <article> card */
  function buildCard(teacher) {
    const { user_id, full_name, subjects, bio, profile_picture } = teacher;
    const name = full_name || 'Scholaxia Teacher';
    const abbr = initials(name);
    const subs = subjectLine(subjects);

    const article = document.createElement('article');
    article.className = 'instructor-card';

    /* photo or placeholder initials */
    const photoDiv = document.createElement('div');
    if (profile_picture) {
      photoDiv.className = 'instructor-photo';
      const img = document.createElement('img');
      img.src     = profile_picture;
      img.alt     = name;
      img.loading = 'lazy';
      img.onerror = () => {
        photoDiv.className = 'instructor-photo placeholder';
        photoDiv.innerHTML = '<span>' + abbr + '</span>';
      };
      photoDiv.appendChild(img);
    } else {
      photoDiv.className = 'instructor-photo placeholder';
      photoDiv.innerHTML = '<span>' + abbr + '</span>';
    }

    const h3 = document.createElement('h3');
    h3.textContent = name;

    const subEl = document.createElement('p');
    subEl.className   = 'instructor-subjects';
    subEl.textContent = subs;

    const link = document.createElement('a');
    link.className   = 'btn btn-profile';
    link.href        = 'portal.html?teacher=' + encodeURIComponent(user_id || '');
    link.textContent = 'View Profile';

    article.appendChild(photoDiv);
    article.appendChild(h3);
    article.appendChild(subEl);
    article.appendChild(link);
    return article;
  }

  /* stagger card entrance animations */
  function animateCards(cards) {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    cards.forEach((card, i) => {
      if (reduce) return;
      card.style.opacity   = '0';
      card.style.transform = 'translateY(28px) scale(0.94)';
      card.style.transition = 'opacity 0.5s ease, transform 0.5s cubic-bezier(0.16,1,0.3,1)';
      setTimeout(() => {
        card.style.opacity   = '1';
        card.style.transform = 'translateY(0) scale(1)';
      }, 60 + i * 60);
    });
  }

  /* error state with retry button */
  function showError() {
    grid.innerHTML =
      '<div class="teachers-error">' +
        '<p>⚠️ Could not load instructors right now.</p>' +
        '<button type="button" id="retryTeachers">Try again</button>' +
      '</div>';
    const btn = document.getElementById('retryTeachers');
    if (btn) btn.addEventListener('click', loadTeachers);
  }

  /* main fetch function */
  function loadTeachers() {
    /* restore skeleton while retrying */
    grid.innerHTML = Array(8).fill(
      '<div class="teacher-skeleton" aria-hidden="true">' +
        '<div class="skel-avatar"></div>' +
        '<div class="skel-line"></div>' +
        '<div class="skel-line short"></div>' +
        '<div class="skel-btn"></div>' +
      '</div>'
    ).join('');

    fetch(API, { method: 'GET', headers: { 'Accept': 'application/json' } })
      .then(res => {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then(data => {
        const teachers = Array.isArray(data) ? data : (data.teachers || data.data || []);
        if (teachers.length === 0) {
          grid.innerHTML =
            '<div class="teachers-error"><p>No instructors found yet. Check back soon!</p></div>';
          return;
        }
        grid.innerHTML = '';
        const cards = teachers.map(buildCard);
        cards.forEach(c => grid.appendChild(c));
        animateCards(cards);
        startTeacherSlider();
      })
      .catch(() => showError());
  }

  /* kick off — use IntersectionObserver so we only fetch when section scrolls into view */
  const section = document.getElementById('instructors');
  if (section && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) {
        io.disconnect();
        loadTeachers();
      }
    }, { rootMargin: '200px' });
    io.observe(section);
  } else {
    loadTeachers();
  }
})();
