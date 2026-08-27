/**
 * Adapts website ScholaxiaAPI to the globals expected by desktop classroom.js.
 */
(function () {
  var S = window.ScholaxiaAPI;
  if (!S) {
    console.error("ScholaxiaAPI missing — load js/api.js first");
    return;
  }

  window.API_BASE = S.API_BASE || "https://scholaxia1.onrender.com";
  window.API_WS = "wss://scholaxia1.onrender.com";

  window.getToken = S.getToken;
  window.getUser = S.getUser;

  window.api = function (path, options) {
    return S.api(path, options);
  };

  window.apiUpload = async function (path, file) {
    var fd = new FormData();
    if (file instanceof FormData) {
      fd = file;
    } else {
      fd.append("file", file);
    }
    return S.apiUpload(path, fd);
  };

  window.parseUtcIso = function (iso) {
    if (!iso) return null;
    var s = String(iso).trim();
    if (!/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) s += "Z";
    var d = new Date(s);
    return isNaN(d.getTime()) ? null : d;
  };

  window.loadLiveSessionData = function () {
    try {
      return JSON.parse(localStorage.getItem("live_session") || "null");
    } catch (e) {
      return null;
    }
  };

  window.clearLiveSession = function () {
    localStorage.removeItem("live_session");
    sessionStorage.removeItem("live_session");
  };

  window.persistLiveSession = function (sess) {
    localStorage.setItem("live_session", JSON.stringify(sess || {}));
  };

  window.isClassroomPage = function () {
    return /classroom\.html/i.test(window.location.pathname || "") ||
      /classroom\.html/i.test(window.location.href || "");
  };
})();
