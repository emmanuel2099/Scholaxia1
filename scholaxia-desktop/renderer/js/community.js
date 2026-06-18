var communityChannelId = null;

async function loadCommunity() {
  var feed = document.getElementById("community-feed");
  feed.innerHTML = '<div class="loading">Loading posts…</div>';
  var err = document.getElementById("community-error");
  err.textContent = "";
  try {
    if (!communityChannelId) {
      var channels = await api("/api/v1/community/channels");
      var general = (channels || []).find(function (c) { return c.type === "general"; }) || (channels || [])[0];
      if (!general) {
        feed.innerHTML = '<div class="empty">Community is not set up yet.</div>';
        return;
      }
      communityChannelId = general.id;
      try {
        await api("/api/v1/community/join", {
          method: "POST",
          body: JSON.stringify({ channel_id: communityChannelId }),
        });
      } catch (e) { /* already joined */ }
    }
    var posts = await api("/api/v1/community/posts?channel_id=" + communityChannelId + "&limit=40");
    if (!posts || !posts.length) {
      feed.innerHTML = '<div class="empty">No posts yet. Be the first to share something!</div>';
      return;
    }
    feed.innerHTML = posts.map(function (p) {
      var media = p.media_url
        ? '<div class="post-media"><img src="' + escHtml(p.media_url) + '" alt="" /></div>'
        : "";
      return '<article class="community-post">' +
        '<div class="post-head"><strong>' + escHtml(p.author_name || "Student") + '</strong>' +
        '<span>' + formatDate(p.created_at) + '</span></div>' +
        '<p class="post-body">' + escHtml(p.content) + '</p>' + media +
        '<div class="post-meta">&#10084; ' + (p.like_count || 0) + '</div></article>';
    }).join("");
  } catch (e) {
    feed.innerHTML = '<div class="empty">' + escHtml(e.message) + '</div>';
  }
}

async function submitCommunityPost() {
  var input = document.getElementById("community-input");
  var err = document.getElementById("community-error");
  var content = input.value.trim();
  if (!content) { err.textContent = "Write something first."; return; }
  if (!communityChannelId) { await loadCommunity(); }
  if (!communityChannelId) return;
  err.textContent = "";
  try {
    await api("/api/v1/community/posts", {
      method: "POST",
      body: JSON.stringify({ channel_id: communityChannelId, content: content }),
    });
    input.value = "";
    loadCommunity();
  } catch (e) {
    err.textContent = e.message;
  }
}
