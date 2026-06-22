function toggleAppSidebar() {
  var shell = document.querySelector(".app-shell");
  if (shell) shell.classList.toggle("sidebar-open");
}

function toggleAdminSidebar() {
  var shell = document.querySelector(".admin-shell");
  if (shell) shell.classList.toggle("sidebar-open");
}

function closeAppSidebar() {
  var shell = document.querySelector(".app-shell");
  if (shell) shell.classList.remove("sidebar-open");
}

function closeAdminSidebar() {
  var shell = document.querySelector(".admin-shell");
  if (shell) shell.classList.remove("sidebar-open");
}

function initResponsiveShell() {
  document.querySelectorAll(".app-shell .nav-item").forEach(function (btn) {
    btn.addEventListener("click", closeAppSidebar);
  });

  document.querySelectorAll(".admin-shell .nav-btn").forEach(function (btn) {
    btn.addEventListener("click", closeAdminSidebar);
  });

  document.querySelectorAll(".sidebar-backdrop").forEach(function (backdrop) {
    backdrop.addEventListener("click", function () {
      closeAppSidebar();
      closeAdminSidebar();
    });
  });

  window.addEventListener("resize", function () {
    if (window.innerWidth > 1100) {
      closeAppSidebar();
      closeAdminSidebar();
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initResponsiveShell);
} else {
  initResponsiveShell();
}
