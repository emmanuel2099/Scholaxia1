/**
 * Wires classroom.js to either website ScholaxiaAPI or desktop api.js globals.
 * Must load after js/api.js and before classroom-livekit.js / classroom.js.
 */
(function () {
  var S = window.ScholaxiaAPI;

  if (S) {
    window.API_BASE = S.API_BASE || window.API_BASE || "https://scholaxia1.onrender.com";
    window.getToken = S.getToken || window.getToken;
    window.getUser = S.getUser || window.getUser;
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
  } else if (typeof window.api !== "function") {
    console.error("classroom-bridge: api() missing — load js/api.js first");
  }

  // Desktop uses /api-proxy for HTTP; LiveKit WS always hits Render.
  if (!window.API_WS) {
    window.API_WS = "wss://scholaxia1.onrender.com";
  }

  if (typeof window.parseUtcIso !== "function") {
    window.parseUtcIso = function (iso) {
      if (!iso) return null;
      var s = String(iso).trim();
      if (!/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) s += "Z";
      var d = new Date(s);
      return isNaN(d.getTime()) ? null : d;
    };
  }

  if (typeof window.loadLiveSessionData !== "function") {
    window.loadLiveSessionData = function () {
      try {
        return JSON.parse(localStorage.getItem("live_session") || "null");
      } catch (e) {
        return null;
      }
    };
  }

  if (typeof window.clearLiveSession !== "function") {
    window.clearLiveSession = function () {
      localStorage.removeItem("live_session");
      sessionStorage.removeItem("live_session");
    };
  }

  if (typeof window.persistLiveSession !== "function") {
    window.persistLiveSession = function (sess) {
      localStorage.setItem("live_session", JSON.stringify(sess || {}));
    };
  }

  if (typeof window.isClassroomPage !== "function") {
    window.isClassroomPage = function () {
      return /classroom\.html/i.test(window.location.pathname || "") ||
        /classroom\.html/i.test(window.location.href || "");
    };
  }
})();
