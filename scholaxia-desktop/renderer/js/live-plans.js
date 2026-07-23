/**
 * Scholaxia One-on-One Live Class Plans UI
 */
var _livePlansCache = null;
var _pendingJoinClassId = null;
var _plansFetchPromise = null;
var PLANS_CACHE_KEY = "sia_live_plans_cache";
var PLANS_CACHE_MS = 10 * 60 * 1000;

function readPlansCache() {
  if (_livePlansCache) return _livePlansCache;
  try {
    var raw = sessionStorage.getItem(PLANS_CACHE_KEY);
    if (!raw) return null;
    var o = JSON.parse(raw);
    if (!o || !o.data || Date.now() - o.at > PLANS_CACHE_MS) return null;
    _livePlansCache = o.data;
    return o.data;
  } catch (e) {
    return null;
  }
}

function writePlansCache(data) {
  _livePlansCache = data;
  try {
    sessionStorage.setItem(PLANS_CACHE_KEY, JSON.stringify({ at: Date.now(), data: data }));
  } catch (e) { /* ignore */ }
}

function clearPlansCache() {
  _livePlansCache = null;
  try { sessionStorage.removeItem(PLANS_CACHE_KEY); } catch (e) { /* ignore */ }
}

function formatPlanPrice(amount) {
  return "₦" + Number(amount).toLocaleString("en-NG");
}

function sessionLabel(plan) {
  var mins = plan.session_minutes >= 60
    ? (plan.session_minutes === 60 ? "1 Hour" : (plan.session_minutes / 60) + " Hours")
    : plan.session_minutes + " Minutes";
  var subs = plan.max_subjects === "All core subjects" || plan.max_subjects >= 99
    ? "All core subjects"
    : "Up to " + plan.max_subjects + " subjects";
  var cat = String(plan.category || "");
  var billing = String(plan.billing || "");
  var isHoliday = billing === "holiday" || /holiday/i.test(cat);
  var isNursery = /nursery/i.test(cat);
  if (isHoliday) {
    return plan.sessions + " live sessions weekly · " + mins + " each · " + subs;
  }
  if (isNursery) {
    return plan.sessions + " sessions weekly · " + mins + " each · " + subs;
  }
  return plan.sessions + " live sessions · " + mins + " each · " + subs;
}

function renderLivePlanCard(plan, suggested, pendingClassId) {
  var suggestedCls = suggested ? " live-plan-card-suggested" : "";
  var features = (plan.features || []).slice(0, 5).map(function (f) {
    return "<li>" + escHtml(f) + "</li>";
  }).join("");
  return (
    '<article class="live-plan-card' + suggestedCls + '">' +
      '<div class="live-plan-head">' +
        '<span class="live-plan-cat">' + escHtml(plan.category) + "</span>" +
        (suggested ? '<span class="live-plan-badge">Recommended</span>' : "") +
      "</div>" +
      "<h3>" + escHtml(plan.name) + "</h3>" +
      '<p class="live-plan-meta">' + escHtml(sessionLabel(plan)) + "</p>" +
      '<ul class="live-plan-features">' + features + "</ul>" +
      '<div class="live-plan-foot">' +
        '<strong class="live-plan-price">' + formatPlanPrice(plan.price) + '<span>/month</span></strong>' +
        '<button type="button" class="btn-action live-plan-pay" data-plan-id="' + escHtml(plan.id) + '" data-class-id="' + escHtml(pendingClassId || "") + '">Choose plan</button>' +
      "</div>" +
    "</article>"
  );
}

function groupPlansByCategory(plans) {
  var groups = {};
  (plans || []).forEach(function (p) {
    if (!groups[p.category]) groups[p.category] = [];
    groups[p.category].push(p);
  });
  return groups;
}

function renderLivePlansPage(data, pendingClassId) {
  var statusEl = document.getElementById("live-plan-status");
  var gridEl = document.getElementById("live-plans-grid");
  if (!gridEl) return;

  var active = data && data.active_plan;
  if (statusEl) {
    if (active) {
      statusEl.innerHTML =
        '<div class="live-plan-active">' +
        "<strong>Active plan:</strong> " + escHtml(active.plan_name) +
        " · <strong>" + escHtml(String(active.sessions_left)) + "</strong> sessions left" +
        (active.expires_at ? " · renews/ends " + escHtml(new Date(active.expires_at).toLocaleDateString()) : "") +
        "</div>";
    } else if (data && (data.paid || data.can_join)) {
      statusEl.innerHTML =
        '<div class="live-plan-active"><strong>Subscription active.</strong> You can join live classes.</div>';
    } else {
      statusEl.innerHTML =
        '<p class="live-plan-hint">Pick a monthly plan below. One payment covers your live classes for 30 days.</p>';
    }
  }

  var plans = (data && data.plans) || [];
  var suggested = (data && data.suggested_plan_ids) || [];
  if (!plans.length) {
    gridEl.innerHTML = '<div class="empty">Plans could not be loaded. Tap Refresh above.</div>';
    return;
  }

  var groups = groupPlansByCategory(plans);
  var html = "";
  Object.keys(groups).forEach(function (cat) {
    html += '<div class="live-plan-group"><h3 class="live-plan-group-title">' + escHtml(cat) + "</h3><div class=\"live-plans-row\">";
    groups[cat].forEach(function (plan) {
      html += renderLivePlanCard(plan, suggested.indexOf(plan.id) >= 0, pendingClassId);
    });
    html += "</div></div>";
  });
  gridEl.innerHTML = html;
}

function fetchLivePlansFromApi() {
  if (_plansFetchPromise) return _plansFetchPromise;
  _plansFetchPromise = api("/api/v1/payments/live-class/plans")
    .then(function (data) {
      writePlansCache(data);
      return data;
    })
    .finally(function () {
      _plansFetchPromise = null;
    });
  return _plansFetchPromise;
}

async function loadLivePlans(pendingClassId, quiet) {
  _pendingJoinClassId = pendingClassId || null;
  var gridEl = document.getElementById("live-plans-grid");
  var forceRefresh = !quiet && pendingClassId;
  var cached = forceRefresh ? null : readPlansCache();

  if (cached) {
    renderLivePlansPage(cached, pendingClassId);
  } else if (!quiet && gridEl) {
    gridEl.innerHTML = '<div class="loading">Loading plans…</div>';
  }

  try {
    var data = await fetchLivePlansFromApi();
    renderLivePlansPage(data, pendingClassId);
  } catch (e) {
    if (!cached && gridEl) {
      gridEl.innerHTML = '<div class="empty">' + escHtml(e.message) + "</div>";
    }
  }
}

function scrollToLivePlans() {
  var el = document.getElementById("live-plans-section");
  if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
}

window.loadLivePlans = loadLivePlans;
window.fetchLivePlansFromApi = fetchLivePlansFromApi;
window.scrollToLivePlans = scrollToLivePlans;
window.readPlansCache = readPlansCache;
window.clearPlansCache = clearPlansCache;
window.getPendingJoinClassId = function () { return _pendingJoinClassId; };

(function paintPlansFromCacheEarly() {
  var cached = readPlansCache();
  if (cached) renderLivePlansPage(cached, null);
})();

if (typeof getToken === "function" && getToken()) {
  fetchLivePlansFromApi()
    .then(function (data) { renderLivePlansPage(data, _pendingJoinClassId); })
    .catch(function () { /* warm cache */ });
}
