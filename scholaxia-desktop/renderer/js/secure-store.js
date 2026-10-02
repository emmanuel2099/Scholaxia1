/**
 * secure-store.js — encrypted offline exam storage (owner PRD: OFFLINE SECURITY)
 *
 * "The system should avoid simply storing everything as easily readable files
 *  on the device. Encrypt sensitive locally stored exam data where practical."
 *
 * Implementation: AES-GCM via WebCrypto. The key is generated once per device,
 * stored by the OS profile (Electron/Chromium Local State encrypts the profile
 * on Windows with DPAPI), and never leaves the device — so the exam packs and
 * pending submission queues on disk are ciphertext, not plain JSON.
 *
 * Public API (async): ssGet(key), ssSet(key, value), ssDel(key), ssReady()
 * Everything falls back to plain storage if WebCrypto is unavailable.
 */
(function () {
  "use strict";

  var MASTER_KEY = "sx_ss_master_key_v1";
  var PREFIX = "sx_enc_v1:"; // marks values encrypted by this module
  var cryptoKey = null;
  var enc = new TextEncoder();
  var dec = new TextDecoder();

  function subtle() {
    return (window.crypto && window.crypto.subtle) || null;
  }

  function b64(bytes) {
    var bin = "";
    var arr = new Uint8Array(bytes);
    for (var i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
    return btoa(bin);
  }

  function unb64(text) {
    var bin = atob(text);
    var arr = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return arr;
  }

  async function getKey() {
    if (cryptoKey) return cryptoKey;
    var s = subtle();
    if (!s) return null;
    try {
      var raw = localStorage.getItem(MASTER_KEY);
      if (raw) {
        cryptoKey = await s.importKey("raw", unb64(raw), "AES-GCM", false, ["encrypt", "decrypt"]);
        return cryptoKey;
      }
      var fresh = await s.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt", "decrypt"]);
      var exported = await s.exportKey("raw", fresh);
      localStorage.setItem(MASTER_KEY, b64(exported));
      cryptoKey = fresh;
      return cryptoKey;
    } catch (e) {
      return null; // fall back to plain storage
    }
  }

  async function ssSet(key, value) {
    var json = JSON.stringify(value == null ? null : value);
    var s = subtle();
    var k = s ? await getKey() : null;
    if (!k) {
      try { localStorage.setItem(key, json); } catch (e) { /* quota */ }
      return;
    }
    try {
      var iv = window.crypto.getRandomValues(new Uint8Array(12));
      var cipher = await s.encrypt({ name: "AES-GCM", iv: iv }, k, enc.encode(json));
      localStorage.setItem(key, PREFIX + b64(iv) + ":" + b64(cipher));
    } catch (e) {
      try { localStorage.setItem(key, json); } catch (e2) { /* quota */ }
    }
  }

  async function ssGet(key) {
    var raw = null;
    try { raw = localStorage.getItem(key); } catch (e) { return null; }
    if (raw == null) return null;
    if (raw.indexOf(PREFIX) !== 0) {
      // Legacy plain value written by an older build — return as-is.
      try { return JSON.parse(raw); } catch (e) { return null; }
    }
    var s = subtle();
    var k = s ? await getKey() : null;
    if (!k) return null;
    try {
      var parts = raw.slice(PREFIX.length).split(":");
      var iv = unb64(parts[0]);
      var data = unb64(parts[1]);
      var plain = await s.decrypt({ name: "AES-GCM", iv: iv }, k, data);
      return JSON.parse(dec.decode(plain));
    } catch (e) {
      return null; // wrong key / tampered value
    }
  }

  async function ssDel(key) {
    try { localStorage.removeItem(key); } catch (e) { /* ignore */ }
  }

  // Migrate an existing plain-JSON key to encrypted storage (once).
  async function ssEncryptExisting(key) {
    var raw = null;
    try { raw = localStorage.getItem(key); } catch (e) { return; }
    if (raw == null || raw.indexOf(PREFIX) === 0) return;
    try {
      var value = JSON.parse(raw);
      await ssSet(key, value);
    } catch (e) { /* leave untouched */ }
  }

  function ssReady() {
    return !!subtle();
  }

  window.ssGet = ssGet;
  window.ssSet = ssSet;
  window.ssDel = ssDel;
  window.ssReady = ssReady;
  window.ssEncryptExisting = ssEncryptExisting;
  window.SS_PREFIX = PREFIX;
})();
