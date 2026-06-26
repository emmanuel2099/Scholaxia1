/**
 * Join live class — paste access code in a modal (codes copied from Access Code tab).
 */
(function () {
  function openJoinLiveModal() {
    var modal = document.getElementById("join-access-modal");
    var input = document.getElementById("join-access-modal-input");
    if (!modal) {
      if (typeof showPage === "function") showPage("access-code");
      return;
    }
    modal.classList.remove("hidden");
    if (input) {
      input.value = "";
      setTimeout(function () { input.focus(); }, 80);
    }
  }

  function closeJoinLiveModal() {
    var modal = document.getElementById("join-access-modal");
    if (modal) modal.classList.add("hidden");
  }

  async function submitJoinLiveModal() {
    var input = document.getElementById("join-access-modal-input");
    var btn = document.getElementById("btn-join-access-modal");
    var code = input ? input.value.trim().toUpperCase() : "";
    if (!code) {
      alert("Paste the access code from your Access Code tab.");
      return;
    }
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Joining…";
    }
    try {
      if (typeof joinClassWithAccessCode === "function") {
        await joinClassWithAccessCode(code);
      } else {
        throw new Error("Join is not available. Restart the app.");
      }
      closeJoinLiveModal();
    } catch (e) {
      alert(e.message || "Could not join with this code.");
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = "Enter class";
      }
    }
  }

  window.openJoinLiveModal = openJoinLiveModal;
  window.closeJoinLiveModal = closeJoinLiveModal;
  window.submitJoinLiveModal = submitJoinLiveModal;
})();
