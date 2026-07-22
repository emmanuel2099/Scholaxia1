var SKILLS_PROGRAMS = [
  {
    id: "web-design",
    icon: "&#127760;",
    title: "Web Design",
    subtitle: "Frontend & Backend",
    duration: "6 months",
    fee: 400000,
    keywords: ["web", "html", "css", "javascript", "frontend", "backend", "react", "node"],
    phases: [
      { name: "Frontend Development", duration: "3 months", topics: ["HTML5 & semantic markup", "CSS3, Flexbox & Grid", "JavaScript fundamentals", "Responsive design", "UI/UX basics", "React or Vue introduction"] },
      { name: "Backend Development", duration: "3 months", topics: ["Node.js / Python APIs", "Databases (SQL & NoSQL)", "Authentication & security", "REST APIs", "Deployment & hosting", "Full-stack portfolio project"] },
    ],
    description: "Learn to build complete websites and web applications from scratch. The frontend track teaches you how users see and interact with the web — layouts, styling, animations, and modern JavaScript frameworks. The backend track covers servers, databases, APIs, and deployment so you can ship production-ready apps. Graduates can work as junior web developers, freelance site builders, or continue into advanced full-stack roles.",
    outcomes: ["Build responsive websites and web apps", "Create and consume REST APIs", "Deploy projects to the internet", "Portfolio of 3+ real projects"],
  },
  {
    id: "mobile-app",
    icon: "&#128241;",
    title: "Mobile App Development",
    subtitle: "Frontend, Backend & Project",
    duration: "9 months",
    fee: 300000,
    keywords: ["mobile", "android", "ios", "flutter", "react native", "app"],
    phases: [
      { name: "Mobile Frontend", duration: "3 months", topics: ["UI components & navigation", "Flutter / React Native basics", "State management", "Device APIs (camera, GPS)", "App store guidelines"] },
      { name: "Mobile Backend", duration: "3 months", topics: ["Firebase / custom APIs", "Push notifications", "Offline sync", "Payment integration", "User authentication"] },
      { name: "Capstone Project", duration: "3 months", topics: ["Team or solo app build", "Mentor reviews", "Testing & debugging", "Play Store / App Store prep", "Launch & presentation"] },
    ],
    description: "Master the full mobile development lifecycle. You will design beautiful interfaces, connect them to real backends, and ship a complete app as your final project. Live classes walk you through industry tools used by startups and agencies worldwide. This program is ideal if you want to build your own app idea or get hired as a mobile developer.",
    outcomes: ["Publish-ready mobile application", "Frontend + backend integration skills", "App store submission experience", "Professional capstone for your CV"],
  },
  {
    id: "gsm-repairs",
    icon: "&#128295;",
    title: "Computer / GSM Repairs",
    subtitle: "Hardware & Software",
    duration: "6 months",
    fee: 150000,
    keywords: ["repair", "gsm", "phone", "computer", "hardware", "laptop"],
    phases: [
      { name: "Hardware Repair", duration: "3 months", topics: ["Phone & laptop disassembly", "Screen & battery replacement", "Motherboard basics", "Soldering & micro-soldering intro", "Diagnostic tools & multimeters"] },
      { name: "Software & Troubleshooting", duration: "3 months", topics: ["OS installation & recovery", "Virus removal & optimization", "IMEI & firmware flashing", "Data recovery basics", "Customer service & pricing"] },
    ],
    description: "A practical, hands-on program for anyone who wants to earn from device repair. You will work on real phones and computers in live lab sessions — not just theory. Learn hardware fixes (screens, batteries, charging ports) and software solutions (OS issues, unlocking, data recovery). Perfect for opening a repair shop or working in a service center.",
    outcomes: ["Diagnose and fix common device faults", "Safe disassembly and reassembly", "Software troubleshooting toolkit", "Business basics for repair shops"],
  },
  {
    id: "graphics",
    icon: "&#127912;",
    title: "Graphics Design",
    subtitle: "Brand, Print & Digital",
    duration: "3 months",
    fee: 70000,
    keywords: ["graphics", "design", "photoshop", "illustrator", "canva", "brand"],
    phases: [
      { name: "Core Design", duration: "3 months", topics: ["Design principles & colour theory", "Typography & layout", "Adobe Photoshop & Illustrator", "Logo & brand identity", "Social media creatives", "Print design (flyers, banners)"] },
    ],
    description: "Turn your creativity into a marketable skill. This intensive program covers visual design from concept to finished artwork. Live classes include live demos in industry-standard tools plus critiques of your work. You will build a portfolio of logos, social posts, and print materials that you can show clients on day one after graduation.",
    outcomes: ["Professional design portfolio", "Brand identity packages", "Social media design templates", "Client-ready deliverables"],
  },
  {
    id: "data-analysis",
    icon: "&#128202;",
    title: "Data Analysis",
    subtitle: "Excel, SQL & Visualization",
    duration: "6 months",
    fee: 100000,
    keywords: ["data", "analysis", "excel", "sql", "python", "power bi"],
    phases: [
      { name: "Foundations", duration: "3 months", topics: ["Excel advanced (pivot, VLOOKUP)", "Data cleaning & validation", "Basic statistics", "SQL queries", "Introduction to Python for data"] },
      { name: "Analytics & Reporting", duration: "3 months", topics: ["Power BI / Tableau dashboards", "Data storytelling", "Business KPIs", "Real datasets & case studies", "Final analytics project"] },
    ],
    description: "Data drives every modern business. Learn to collect, clean, analyze, and present data so decision-makers can act on it. Live sessions use real spreadsheets and databases from Nigerian businesses. Whether you want a corporate analyst role or freelance reporting gigs, this program gives you the toolkit employers ask for.",
    outcomes: ["Interactive dashboards", "SQL & Excel proficiency", "Data cleaning workflows", "Business report portfolio"],
  },
  {
    id: "cyber-security",
    icon: "&#128274;",
    title: "Cyber Security",
    subtitle: "Defence & Ethical Hacking Basics",
    duration: "3 months",
    fee: 150000,
    keywords: ["cyber", "security", "hacking", "network", "firewall"],
    phases: [
      { name: "Security Fundamentals", duration: "3 months", topics: ["Network security basics", "Threats & vulnerabilities", "Firewalls & encryption", "Password & access management", "Ethical hacking introduction", "Incident response basics"] },
    ],
    description: "Protect systems and understand how attackers think — legally and ethically. This fast-track program introduces network security, common attack vectors, and defensive practices used in banks, schools, and tech companies. Live labs simulate real scenarios in a safe environment. A strong entry point into IT security careers or securing your own business.",
    outcomes: ["Security assessment checklist", "Network hardening skills", "Ethical hacking lab experience", "Foundation for advanced certs"],
  },
  {
    id: "digital-marketing",
    icon: "&#128226;",
    title: "Digital Marketing",
    subtitle: "Social, Ads & Growth",
    duration: "2 months",
    fee: 80000,
    keywords: ["marketing", "digital", "social media", "ads", "seo"],
    phases: [
      { name: "Growth Marketing", duration: "2 months", topics: ["Social media strategy", "Facebook & Instagram ads", "Google Ads basics", "Content marketing", "Email campaigns", "Analytics & ROI tracking"] },
    ],
    description: "Learn to grow brands online with proven digital marketing tactics. Short but intensive — perfect for entrepreneurs, influencers, or anyone managing social accounts for businesses. Live classes cover campaign setup, ad targeting, and measuring results in Naira. You will run a practice campaign before graduation.",
    outcomes: ["Complete marketing plan template", "Live ad campaign experience", "Content calendar system", "ROI reporting skills"],
  },
  {
    id: "scratch-robotics",
    icon: "&#129302;",
    title: "Scratch Coding & Robotics",
    subtitle: "Kids, Teens & Beginners",
    duration: "3 months",
    fee: 65000,
    keywords: ["scratch", "robotics", "coding", "arduino", "stem"],
    phases: [
      { name: "Coding & Robotics", duration: "3 months", topics: ["Scratch block programming", "Logic, loops & variables", "Arduino / micro:bit basics", "Building simple robots", "Sensors & motors", "STEM project showcase"] },
    ],
    description: "An engaging program for young learners and absolute beginners. Start with Scratch's visual blocks to understand programming logic, then move to physical robotics — wiring sensors, motors, and writing code that makes things move. Live classes are interactive and project-based. Great for students, parents who homeschool, or teachers adding STEM to their classroom.",
    outcomes: ["Scratch games & animations", "Working robot prototype", "STEM problem-solving skills", "Showcase project for school or competitions"],
  },
];

var skillsLiveCache = null;
var skillsExpandedId = null;

function formatNaira(amount) {
  return "₦" + Number(amount || 0).toLocaleString("en-NG");
}

function installmentBreakdown(fee) {
  var half = Math.round(fee / 2);
  return formatNaira(half) + " at enrollment + " + formatNaira(fee - half) + " at midpoint (or pay full once)";
}

function selectedSkillPayMode() {
  var el = document.querySelector('input[name="skill-pay-mode"]:checked');
  return (el && el.value) || "half";
}

function updateSkillEnrollFeeCopy(skill) {
  if (!skill) return;
  var half = Math.round(skill.fee / 2);
  var mode = selectedSkillPayMode();
  var feeEl = document.getElementById("skill-enroll-fee");
  var subEl = document.getElementById("skill-enroll-sub");
  if (mode === "once") {
    if (subEl) subEl.textContent = "Complete this form, then pay the full program fee (" + formatNaira(skill.fee) + ").";
    if (feeEl) feeEl.textContent = "Paying once: " + formatNaira(skill.fee) + " · unlocks enrollment + live classes for the full program.";
  } else {
    if (subEl) subEl.textContent = "Complete this form, then pay half now (" + formatNaira(half) + "). Balance is due at midpoint or access shuts down.";
    if (feeEl) {
      feeEl.textContent =
        "Total " + formatNaira(skill.fee) + " · half now " + formatNaira(half) +
        " + balance " + formatNaira(skill.fee - half) + " by midpoint.";
    }
  }
}

function openSkillEnrollment(id, opts) {
  var skill = SKILLS_PROGRAMS.find(function (s) { return s.id === id; });
  if (!skill) return;
  opts = opts || {};
  var modal = document.getElementById("skill-enroll-modal");
  document.getElementById("skill-enroll-id").value = skill.id;
  document.getElementById("skill-enroll-title").textContent =
    opts.installment === 2 ? ("Pay balance — " + skill.title) : ("Enroll — " + skill.title);
  document.getElementById("skill-enroll-error").textContent = "";
  var user = typeof getUser === "function" ? getUser() : {};
  document.getElementById("skill-enroll-name").value = user.name || localStorage.getItem("sia_name") || "";
  document.getElementById("skill-enroll-email").value = localStorage.getItem("sia_email") || "";
  document.getElementById("skill-enroll-phone").value = "";
  document.getElementById("skill-enroll-start").value = "";
  document.getElementById("skill-enroll-notes").value = "";

  var onceRadio = document.querySelector('input[name="skill-pay-mode"][value="once"]');
  var halfRadio = document.querySelector('input[name="skill-pay-mode"][value="half"]');
  var fieldset = document.querySelector(".skill-pay-mode");
  if (opts.installment === 2) {
    if (fieldset) fieldset.style.display = "none";
    if (halfRadio) halfRadio.checked = true;
    document.getElementById("skill-enroll-sub").textContent =
      "Pay the remaining balance (" + formatNaira(skill.fee - Math.round(skill.fee / 2)) + ") to keep your enrollment.";
    document.getElementById("skill-enroll-fee").textContent = "Balance installment due now.";
  } else {
    if (fieldset) fieldset.style.display = "";
    if (halfRadio) halfRadio.checked = true;
    updateSkillEnrollFeeCopy(skill);
  }
  modal.dataset.installment = opts.installment === 2 ? "2" : "1";
  if (modal) modal.classList.remove("hidden");
}

document.addEventListener("change", function (ev) {
  if (ev.target && ev.target.name === "skill-pay-mode") {
    var id = (document.getElementById("skill-enroll-id") || {}).value;
    var skill = SKILLS_PROGRAMS.find(function (s) { return s.id === id; });
    updateSkillEnrollFeeCopy(skill);
  }
});

function closeSkillEnrollment() {
  var modal = document.getElementById("skill-enroll-modal");
  if (modal) modal.classList.add("hidden");
}

async function submitSkillEnrollment(ev) {
  if (ev) ev.preventDefault();
  var skillId = document.getElementById("skill-enroll-id").value;
  var errEl = document.getElementById("skill-enroll-error");
  var btn = document.getElementById("skill-enroll-submit");
  var modal = document.getElementById("skill-enroll-modal");
  var installment = Number((modal && modal.dataset.installment) || 1);
  var paymentMode = installment === 2 ? "half" : selectedSkillPayMode();
  var form = {
    full_name: document.getElementById("skill-enroll-name").value.trim(),
    phone: document.getElementById("skill-enroll-phone").value.trim(),
    email: document.getElementById("skill-enroll-email").value.trim(),
    preferred_start: document.getElementById("skill-enroll-start").value.trim(),
    notes: document.getElementById("skill-enroll-notes").value.trim(),
    payment_mode: paymentMode,
    installment: installment,
  };
  if (!form.full_name || !form.phone || !form.email) {
    if (errEl) errEl.textContent = "Name, phone, and email are required.";
    return;
  }
  if (!getToken || !getToken()) {
    if (errEl) errEl.textContent = "Please sign in first.";
    return;
  }
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Opening payment…";
  }
  try {
    if (typeof payForSkillEnrollment !== "function") {
      throw new Error("Payment is not available. Refresh and try again.");
    }
    await payForSkillEnrollment(skillId, form, btn);
    closeSkillEnrollment();
  } catch (e) {
    if (errEl) errEl.textContent = e.message || "Could not start enrollment payment.";
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = "Continue to payment";
    }
  }
}

function sessionMatchesSkill(session, keywords) {
  var hay = ((session.title || "") + " " + (session.subject || "") + " " + (session.description || "")).toLowerCase();
  return keywords.some(function (kw) { return hay.indexOf(kw) >= 0; });
}

async function fetchSkillLiveSessions() {
  try {
    var live = await api("/api/v1/live-classes/?status=live") || [];
    var upcoming = await api("/api/v1/live-classes/?status=upcoming") || [];
    return (live || []).concat(upcoming || []);
  } catch (e) {
    return [];
  }
}

function renderSkillLiveClasses(skill, sessions) {
  var matched = (sessions || []).filter(function (s) { return sessionMatchesSkill(s, skill.keywords); });
  if (!matched.length) {
    return '<div class="skill-live-empty">' +
      '<p>No live sessions scheduled for this skill yet. New classes are added regularly — check back or request one from the <button type="button" class="skill-link-btn" onclick="showPage(\'live\')">Live Class</button> tab.</p>' +
      '</div>';
  }
  return '<div class="skill-live-grid">' + matched.map(function (s) {
    var badge = s.is_live || s.status === "live" ? '<span class="live-pill">LIVE</span>' : '<span class="time-badge">Upcoming</span>';
    return '<div class="skill-live-card">' +
      badge +
      '<h4>' + escHtml(s.title) + '</h4>' +
      '<p class="meta">' + escHtml(s.subject) + ' · ' + escHtml(s.teacher_name || "Instructor") + '</p>' +
      (s.start_time ? '<p class="schedule-meta">&#128197; ' + formatDate(s.start_time) + '</p>' : '') +
      '<button type="button" class="btn-join" data-id="' + escHtml(s.id) + '" data-title="' + escHtml(s.title) + '" data-subject="' + escHtml(s.subject) + '" data-teacher="' + escHtml(s.teacher_name || "") + '">Join live class</button>' +
      '</div>';
  }).join("") + '</div>';
}

function renderHomeSkillsPreview() {
  var el = document.getElementById("dash-skills-preview");
  if (!el || typeof SKILLS_PROGRAMS === "undefined") return;
  el.innerHTML = SKILLS_PROGRAMS.slice(0, 4).map(function (skill) {
    return '<article class="dash-skill-card">' +
      '<span class="dash-skill-icon" aria-hidden="true">' + skill.icon + '</span>' +
      '<div><h4>' + escHtml(skill.title) + '</h4>' +
      '<p>' + escHtml(skill.subtitle) + ' · ' + escHtml(skill.duration) + '</p>' +
      '<strong class="dash-skill-fee">' + formatNaira(skill.fee) + '</strong></div>' +
      '<button type="button" class="dash-skill-btn" onclick="openSkillEnrollment(\'' + skill.id + '\')">Enroll</button>' +
      '</article>';
  }).join("") +
    '<button type="button" class="dash-skills-all" onclick="showPage(\'skills\')">View all skills programs &rarr;</button>';
}

function renderSkillCard(skill, sessions, expanded) {
  var isOpen = expanded === skill.id;
  var phasesHtml = (skill.phases || []).map(function (ph) {
    return '<div class="skill-phase">' +
      '<div class="skill-phase-head"><strong>' + escHtml(ph.name) + '</strong><span>' + escHtml(ph.duration) + '</span></div>' +
      '<ul>' + (ph.topics || []).map(function (t) { return '<li>' + escHtml(t) + '</li>'; }).join("") + '</ul>' +
      '</div>';
  }).join("");

  var outcomesHtml = (skill.outcomes || []).map(function (o) {
    return '<li>' + escHtml(o) + '</li>';
  }).join("");

  return '<article class="skill-card' + (isOpen ? " open" : "") + '" data-skill-id="' + escHtml(skill.id) + '">' +
    '<button type="button" class="skill-card-toggle" onclick="toggleSkillCard(\'' + skill.id + '\')">' +
    '<span class="skill-card-icon" aria-hidden="true">' + skill.icon + '</span>' +
    '<div class="skill-card-summary">' +
    '<h3>' + escHtml(skill.title) + '</h3>' +
    '<p class="skill-subtitle">' + escHtml(skill.subtitle) + '</p>' +
    '<div class="skill-meta-row">' +
    '<span>&#9201; ' + escHtml(skill.duration) + '</span>' +
    '<span class="skill-fee">' + formatNaira(skill.fee) + '</span>' +
    '</div></div>' +
    '<span class="skill-chevron" aria-hidden="true">' + (isOpen ? "&#9650;" : "&#9660;") + '</span>' +
    '</button>' +
    (isOpen ? '<div class="skill-card-body">' +
      '<p class="skill-description">' + escHtml(skill.description) + '</p>' +
      '<div class="skill-installment">' +
      '<strong>Payment options:</strong> pay once (full) or ' + escHtml(installmentBreakdown(skill.fee)) +
      '</div>' +
      (function () {
        var enroll = (window.skillsEnrollmentMap || {})[skill.id];
        if (!enroll) return "";
        if (enroll.status === "suspended") {
          return '<div class="skill-enroll-status is-suspended">Shut down — balance was not paid by the due date. Contact support.</div>';
        }
        if (enroll.status === "completed" || enroll.payment_mode === "once") {
          return '<div class="skill-enroll-status is-active">Enrolled · live classes unlocked</div>';
        }
        if (enroll.status === "active" && Number(enroll.installments_paid || 0) === 1) {
          return '<div class="skill-enroll-status is-pending">Half paid · balance due' +
            (enroll.balance_due_at ? " by " + escHtml(String(enroll.balance_due_at).slice(0, 10)) : "") +
            " or access shuts down</div>";
        }
        return "";
      })() +
      '<h4>Program structure</h4>' +
      '<div class="skill-phases">' + phasesHtml + '</div>' +
      '<h4>What you will achieve</h4>' +
      '<ul class="skill-outcomes">' + outcomesHtml + '</ul>' +
      '<h4>Live classes for this skill</h4>' +
      renderSkillLiveClasses(skill, sessions) +
      '<div class="skill-enroll-row">' +
      (function () {
        var enroll = (window.skillsEnrollmentMap || {})[skill.id];
        if (enroll && (enroll.status === "completed" || enroll.payment_mode === "once" || enroll.status === "suspended")) {
          return "";
        }
        if (enroll && enroll.status === "active" && Number(enroll.installments_paid || 0) === 1) {
          return '<button type="button" class="btn-enroll" onclick="openSkillEnrollment(\'' + skill.id + '\', { installment: 2 })">Pay balance</button>';
        }
        return '<button type="button" class="btn-enroll" onclick="openSkillEnrollment(\'' + skill.id + '\')">Enroll now</button>';
      })() +
      '<button type="button" class="btn-secondary" onclick="showPage(\'live\')">View live classes</button>' +
      '</div>' +
      '</div>' : '') +
    '</article>';
}

async function loadSkillEnrollmentBadges() {
  window.skillsEnrollmentMap = {};
  if (!getToken || !getToken()) return;
  try {
    var data = await api("/api/v1/payments/flutterwave/skills/enrollments");
    var list = (data && data.enrollments) || [];
    list.forEach(function (e) {
      if (e && e.skill_id) window.skillsEnrollmentMap[e.skill_id] = e;
    });
    renderSkillsPrograms(skillsLiveCache || []);
  } catch (e) { /* ignore */ }
}

function toggleSkillCard(id) {
  skillsExpandedId = skillsExpandedId === id ? null : id;
  renderSkillsPrograms(skillsLiveCache || []);
}

function showSkillEnrollInfo(id) {
  openSkillEnrollment(id);
}

function renderSkillsPrograms(sessions) {
  var el = document.getElementById("skills-programs");
  if (!el) return;
  el.innerHTML = SKILLS_PROGRAMS.map(function (skill) {
    return renderSkillCard(skill, sessions, skillsExpandedId);
  }).join("");
}

async function loadSkillsTraining() {
  var el = document.getElementById("skills-programs");
  if (!el) return;
  renderSkillsPrograms(skillsLiveCache || []);
  var sessions = await fetchSkillLiveSessions();
  skillsLiveCache = sessions;
  renderSkillsPrograms(sessions);
  if (typeof loadSkillEnrollmentBadges === "function") loadSkillEnrollmentBadges();
}

window.toggleSkillCard = toggleSkillCard;
window.openSkillEnrollment = openSkillEnrollment;
window.closeSkillEnrollment = closeSkillEnrollment;
window.submitSkillEnrollment = submitSkillEnrollment;
window.showSkillEnrollInfo = showSkillEnrollInfo;
window.loadSkillsTraining = loadSkillsTraining;
window.renderHomeSkillsPreview = renderHomeSkillsPreview;
