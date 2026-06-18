var communityChannelId = null;

function renderCommunityPosts(posts) {
  var feed = document.getElementById("community-feed");
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
}

function mapMessagesToPosts(messages) {
  return (messages || []).map(function (m) {
    return {
      author_name: m.sender_name || "Student",
      content: m.content,
      media_url: m.media_url,
      created_at: m.created_at,
      like_count: 0,
    };
  });
}

async function fetchCommunityPosts() {
  try {
    return await api("/api/v1/community/feed?limit=50");
  } catch (e1) {
    if (!communityChannelId) {
      var channels = await api("/api/v1/community/channels");
      var general = (channels || []).find(function (c) { return c.type === "general"; }) || (channels || [])[0];
      if (!general) return [];
      communityChannelId = general.id;
    }
    try {
      return await api("/api/v1/community/posts?channel_id=" + communityChannelId + "&limit=50");
    } catch (e2) {
      var messages = await api("/api/v1/community/messages?channel_id=" + communityChannelId + "&limit=50");
      return mapMessagesToPosts(messages);
    }
  }
}

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
      } catch (joinErr) { /* already joined */ }
    }
    var posts = await fetchCommunityPosts();
    renderCommunityPosts(posts);
  } catch (e) {
    var msg = e.message === "Failed to fetch"
      ? "Could not reach the server. Check your internet and try Refresh."
      : e.message;
    feed.innerHTML = '<div class="empty">' + escHtml(msg) + '</div>';
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
