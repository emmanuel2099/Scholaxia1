const API = "https://scholaxia1.onrender.com";
const token = localStorage.getItem("sia_token") || "";
const userName = localStorage.getItem("sia_name") || "";

let feedData = null;
let joinClassId = null;

window.onload = () => {
  if (!token) { window.location.href = "auth.html"; return; }
  document.getElementById("header-user").textContent = firstName(userName);
  checkSetupThenLoad();
};

async function checkSetupThenLoad() {
  try {
    const res = await fetch(`${API}/api/v1/students/setup-status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 401) { window.location.href = "auth.html"; return; }
    const data = await res.json();
    if (!data.setup_complete) {
      window.location.href = "setup.html";
      return;
    }
    const hero = document.querySelector(".hero p");
    if (hero) {
      hero.textContent = `${data.exam_type} student · ${(data.selected_subjects || []).join(", ")}`;
    }
    loadFeed();
  } catch {
    window.location.href = "setup.html";
  }
}

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(options.headers || {}),
    },
  });
  if (res.status === 401) { window.location.href = "auth.html"; return null; }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`);
  return data;
}

async function loadFeed() {
  try {
    feedData = await api(`/api/v1/home/feed`);
    if (!feedData) return;
    renderLive(feedData.live_now || []);
    renderUpcoming(feedData.upcoming_sessions || []);
    renderRecommendations(feedData.recommended_for_you || {});
    renderSchoolExams(feedData.school_exams || []);
    renderRequests(feedData.my_session_requests || []);
  } catch (e) {
    document.getElementById("live-grid").innerHTML =
      `<div class="empty-state">Could not load feed. ${escHtml(e.message)}</div>`;
  }
}

function renderSchoolExams(exams) {
  const upcoming = document.getElementById("upcoming-grid");
  if (!exams.length) return;
  const schoolHtml = exams.map(s => `
    <article class="session-card school-card">
      <div class="time-badge">📷 School Exam</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${s.total_questions} questions</p>
      <a href="cbt.html" class="btn-join" style="display:inline-block;text-align:center;text-decoration:none;margin-top:12px">Go to CBT</a>
    </article>
  `).join("");
  upcoming.innerHTML = schoolHtml + upcoming.innerHTML;
}

function renderLive(sessions) {
  const el = document.getElementById("live-grid");
  document.getElementById("live-count").textContent = sessions.length;

  if (!sessions.length) {
    el.innerHTML = `<div class="empty-state-sm">No live classes right now. Check upcoming sessions or request one below.</div>`;
    return;
  }

  el.innerHTML = sessions.map(s => `
    <article class="session-card live">
      <div class="live-pill">LIVE</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${escHtml(s.teacher_name)}</p>
      <button class="btn-join" onclick="openJoin('${s.id}', '${escAttr(s.title)}', '${escAttr(s.teacher_name)}')">Join Class</button>
    </article>
  `).join("");
}

function renderUpcoming(sessions) {
  const el = document.getElementById("upcoming-grid");

  if (!sessions.length) {
    el.innerHTML = `<div class="empty-state-sm">No upcoming sessions scheduled.</div>`;
    return;
  }

  el.innerHTML = sessions.map(s => `
    <article class="session-card">
      <div class="time-badge">${formatTime(s.start_time)}</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${escHtml(s.teacher_name)}</p>
      ${s.description ? `<p class="desc">${escHtml(s.description.slice(0, 100))}</p>` : ""}
    </article>
  `).join("");
}

function renderRecommendations(rec) {
  const el = document.getElementById("rec-grid");
  const weakEl = document.getElementById("weak-topics");
  const items = [];

  (rec.admin_picks || []).forEach(b => items.push({ ...b, source: "Admin pick" }));
  (rec.library_books || []).forEach(b => items.push({
    id: b.id, title: b.title, author: b.author, subject: rec.primary_subject,
    type: "book", source: "Library", has_library_book: true,
  }));
  (rec.library_videos || []).forEach(v => items.push({
    id: v.id, title: v.title, subject: rec.primary_subject,
    type: "video", source: "Video", external_url: v.video_url,
  }));

  if (rec.weak_topics && rec.weak_topics.length) {
    weakEl.style.display = "block";
    weakEl.innerHTML = `<strong>Focus areas:</strong> ${rec.weak_topics.map(escHtml).join(", ")}`;
  } else {
    weakEl.style.display = "none";
  }

  if (!items.length) {
    el.innerHTML = `<div class="empty-state-sm">No recommendations yet. Complete a CBT exam to get personalised picks.</div>`;
    return;
  }

  el.innerHTML = items.map(item => `
    <article class="rec-card">
      <span class="rec-tag">${escHtml(item.source || item.type)}</span>
      <h3>${escHtml(item.title)}</h3>
      ${item.author ? `<p class="meta">${escHtml(item.author)}</p>` : ""}
      ${item.subject ? `<p class="meta">${escHtml(item.subject)}</p>` : ""}
      ${item.external_url
        ? `<a href="${escAttr(item.external_url)}" target="_blank" rel="noopener" class="link-btn">Open</a>`
        : item.has_library_book
          ? `<span class="link-btn muted">In Library</span>`
          : ""}
    </article>
  `).join("");
}

function renderRequests(requests) {
  const el = document.getElementById("requests-list");
  if (!requests.length) {
    el.innerHTML = `<div class="empty-state-sm">No requests yet.</div>`;
    return;
  }

  el.innerHTML = requests.map(r => `
    <div class="request-item status-${r.status}">
      <div class="request-top">
        <strong>${escHtml(r.subject)}</strong>
        <span class="status-pill">${escHtml(r.status)}</span>
      </div>
      ${r.topic ? `<p>${escHtml(r.topic)}</p>` : ""}
      ${r.message ? `<p class="meta">${escHtml(r.message)}</p>` : ""}
      <p class="meta">${formatTime(r.created_at)}</p>
    </div>
  `).join("");
}

function openJoin(classId, title, teacher) {
  joinClassId = classId;
  document.getElementById("join-title").textContent = title;
  document.getElementById("join-detail").textContent = `Teacher: ${teacher}`;
  document.getElementById("join-status").textContent = "";
  document.getElementById("join-modal").style.display = "flex";
}

function closeJoinModal() {
  joinClassId = null;
  document.getElementById("join-modal").style.display = "none";
}

async function confirmJoin() {
  if (!joinClassId) return;
  const statusEl = document.getElementById("join-status");
  const btn = document.getElementById("join-btn");
  btn.disabled = true;
  statusEl.textContent = "Joining…";

  try {
    const data = await api(`/api/v1/live-classes/${joinClassId}/join`, { method: "POST", body: "{}" });
    statusEl.textContent = "Joined! Opening classroom…";
    closeJoinModal();
    // Store join credentials for a future live room page
    localStorage.setItem("live_join", JSON.stringify(data));
    alert(`Joined successfully!\nRoom: ${data.room_id}\n\nLive video room integration coming soon.`);
  } catch (e) {
    statusEl.textContent = e.message;
  } finally {
    btn.disabled = false;
  }
}

async function submitRequest(e) {
  e.preventDefault();
  const btn = document.getElementById("req-btn");
  const statusEl = document.getElementById("req-status");
  btn.disabled = true;
  statusEl.textContent = "Sending…";

  const preferred = document.getElementById("req-time").value;
  const body = {
    subject: document.getElementById("req-subject").value,
    topic: document.getElementById("req-topic").value || null,
    message: document.getElementById("req-message").value || null,
    preferred_time: preferred ? new Date(preferred).toISOString() : null,
  };

  try {
    await api("/api/v1/live-classes/requests", { method: "POST", body: JSON.stringify(body) });
    statusEl.textContent = "Request sent! A teacher will review it soon.";
    document.getElementById("request-form").reset();
    loadFeed();
  } catch (err) {
    statusEl.textContent = err.message;
  } finally {
    btn.disabled = false;
  }
}

function logout() {
  localStorage.removeItem("sia_token");
  localStorage.removeItem("sia_name");
  window.location.href = "auth.html";
}

function firstName(name) {
  if (!name) return "Student";
  if (name.includes("@")) return name.split("@")[0];
  return name.split(" ")[0];
}

function formatTime(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

function escHtml(s) {
  return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escAttr(s) {
  return escHtml(s).replace(/"/g, "&quot;");
}
