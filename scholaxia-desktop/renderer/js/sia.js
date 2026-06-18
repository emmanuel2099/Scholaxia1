var siaHistory = [];

function loadSia() {
  if (!siaHistory.length) {
    document.getElementById("sia-messages").innerHTML =
      '<div class="sia-welcome"><div class="sia-orb">S</div><p>Hi! I\'m <strong>Sia</strong>, your AI tutor. Ask me anything.</p></div>';
  }
}

function appendSiaMessage(role, text) {
  var el = document.getElementById("sia-messages");
  var welcome = el.querySelector(".sia-welcome");
  if (welcome) welcome.remove();
  var div = document.createElement("div");
  div.className = "sia-msg " + role;
  div.innerHTML = role === "sia"
    ? '<div class="sia-avatar">S</div><div class="sia-bubble">' + escHtml(text) + '</div>'
    : '<div class="sia-bubble user">' + escHtml(text) + '</div>';
  el.appendChild(div);
  el.scrollTop = el.scrollHeight;
}

function siaSubject() {
  var subjects = getUser().subjects || [];
  return subjects.length ? subjects[0] : "General";
}

async function sendSiaMessage() {
  var input = document.getElementById("sia-input");
  var err = document.getElementById("sia-error");
  var question = input.value.trim();
  if (!question) return;
  err.textContent = "";
  input.value = "";
  appendSiaMessage("user", question);
  siaHistory.push({ role: "user", content: question });
  appendSiaMessage("sia", "Thinking…");
  var msgs = document.getElementById("sia-messages");
  var thinking = msgs.lastChild;

  try {
    var data = await api("/api/v1/sia/ask", {
      method: "POST",
      body: JSON.stringify({
        question: question,
        subject: siaSubject(),
        language: "english",
        conversation_history: siaHistory.slice(-6).map(function (m) {
          return { role: m.role === "user" ? "user" : "assistant", content: m.content };
        }),
      }),
    });
    var answer = (data && (data.sia || data.answer || data.result)) || "Sorry, I could not answer that.";
    thinking.remove();
    appendSiaMessage("sia", answer);
    siaHistory.push({ role: "sia", content: answer });
  } catch (e) {
    thinking.remove();
    err.textContent = e.message;
    appendSiaMessage("sia", "Something went wrong. Please try again.");
  }
}
