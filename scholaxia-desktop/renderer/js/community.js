var communityChannelId = null;
var communityDraftImage = null;
var communityVoiceRecorder = null;
var communityPendingPost = null;
var communityActiveTab = "feed";
var COMMUNITY_CHANNEL_KEY = "sia_community_channel_id";
var COMMUNITY_POSTS_CACHE_KEY = "sia_community_posts_cache";
var POST_COMMENT_RE = /^@post:([^\s]+)\s*([\s\S]*)$/;

function restoreCommunityChannelId() {
  if (communityChannelId) return;
  try {
    var cached = localStorage.getItem(COMMUNITY_CHANNEL_KEY);
    if (cached) communityChannelId = cached;
  } catch (e) { /* ignore */ }
}

function saveCommunityChannelId(id) {
  if (!id) return;
  communityChannelId = id;
  try { localStorage.setItem(COMMUNITY_CHANNEL_KEY, id); } catch (e) { /* ignore */ }
}

function saveCommunityCache(posts) {
  if (!posts || !posts.length) return;
  try {
    localStorage.setItem(COMMUNITY_POSTS_CACHE_KEY, JSON.stringify({
      saved_at: Date.now(),
      posts: posts,
    }));
  } catch (e) { /* ignore */ }
}

function loadCommunityCache() {
  try {
    var raw = localStorage.getItem(COMMUNITY_POSTS_CACHE_KEY);
    if (!raw) return null;
    var data = JSON.parse(raw);
    if (!data || !Array.isArray(data.posts)) return null;
    return data;
  } catch (e) { return null; }
}

function isPostComment(content) {
  return POST_COMMENT_RE.test(content || "");
}

function isRealPostId(id) {
  return id && String(id).indexOf("orphan") !== 0;
}

function parsePostComment(content) {
  var match = POST_COMMENT_RE.exec(content || "");
  if (!match) return null;
  return { parentId: match[1], text: (match[2] || "").trim() };
}

function displayPostContent(content) {
  var parsed = parsePostComment(content);
  return parsed ? parsed.text : (content || "");
}

function mapMessagesToPosts(messages) {
  return (messages || [])
    .filter(function (m) { return !isPostComment(m.content); })
    .map(function (m) {
      return {
        id: m.id,
        author_name: m.sender_name || "Student",
        content: m.content,
        media_url: m.media_url,
        created_at: m.created_at,
        like_count: 0,
        liked_by_me: false,
        comments: [],
      };
    });
}

async function fetchPostComments() {
  var commentsByPost = {};
  if (!communityChannelId) return commentsByPost;
  try {
    var messages = await api("/api/v1/community/messages?channel_id=" + communityChannelId + "&limit=100");
    (messages || []).forEach(function (m) {
      var parsed = parsePostComment(m.content || "");
      if (!parsed || !parsed.text) return;
      if (!commentsByPost[parsed.parentId]) commentsByPost[parsed.parentId] = [];
      commentsByPost[parsed.parentId].push({
        author_name: m.sender_name || "Student",
        content: parsed.text,
        created_at: m.created_at,
      });
    });
  } catch (e) { /* comments are optional */ }
  return commentsByPost;
}

function attachComments(posts, commentsByPost) {
  var result = (posts || []).map(function (p) {
    return Object.assign({}, p, { comments: commentsByPost[p.id] || [] });
  });
  var known = {};
  result.forEach(function (p) { known[p.id] = true; });

  Object.keys(commentsByPost).forEach(function (parentId) {
    if (known[parentId]) return;
    commentsByPost[parentId].forEach(function (c) {
      result.push({
        id: parentId,
        card_key: parentId + "-" + String(c.created_at || ""),
        author_name: c.author_name,
        content: c.content,
        created_at: c.created_at,
        like_count: 0,
        liked_by_me: false,
        comments: [],
        is_flat_comment: true,
      });
    });
  });

  result.sort(function (a, b) {
    return new Date(b.created_at || 0) - new Date(a.created_at || 0);
  });
  return result;
}

function postCardDomId(p) {
  return String(p.card_key || p.id || "");
}

function postInteractId(p) {
  return String(p.id || "");
}

function renderPostActions(p) {
  var interactId = postInteractId(p);
  var domId = postCardDomId(p);
  if (!interactId || interactId.indexOf("orphan") === 0) return "";
  var liked = p.liked_by_me ? " liked" : "";
  var safeInteract = interactId.replace(/'/g, "\\'");
  var safeDom = domId.replace(/'/g, "\\'");
  return '<div class="post-actions">' +
    '<button type="button" class="post-action-btn post-like-btn' + liked + '" data-like-id="' + escHtml(interactId) + '" onclick="toggleCommunityLike(\'' + safeInteract + '\')" title="Like">' +
    '<span class="action-icon" aria-hidden="true">&#10084;</span>' +
    '<span class="like-count">' + (p.like_count || 0) + '</span></button>' +
    '<button type="button" class="post-action-btn post-comment-btn" onclick="toggleCommentBox(\'' + safeDom + '\', \'' + safeInteract + '\')" title="Comment">' +
    '<span class="action-icon" aria-hidden="true">&#128172;</span>' +
    '<span class="comment-count">' + ((p.comments || []).length || "") + '</span></button>' +
    '</div>' +
    '<div class="comment-compose" id="comment-box-' + escHtml(domId) + '">' +
    '<input type="text" id="comment-input-' + escHtml(domId) + '" placeholder="Write a comment…" ' +
    'onkeydown="if(event.key===\'Enter\')submitCommunityComment(\'' + safeInteract + '\', \'' + safeDom + '\')" />' +
    '<button type="button" class="btn-action btn-comment" onclick="submitCommunityComment(\'' + safeInteract + '\', \'' + safeDom + '\')">Reply</button>' +
    '</div>';
}

function renderCommunityPosts(posts, targetEl) {
  var feed = targetEl || document.getElementById("community-feed");
  if (!feed) return;
  if (!posts || !posts.length) {
    feed.innerHTML = '<div class="empty">No posts yet. Tap the send button below to share something!</div>';
    return;
  }
  feed.innerHTML = posts.map(function (p) {
    var body = displayPostContent(p.content);
    var media = "";
    if (p.media_url && p.media_type === "audio") {
      media = '<audio controls class="post-audio" src="' + escHtml(p.media_url) + '"></audio>';
    } else if (p.media_url) {
      media = '<div class="post-media"><img src="' + escHtml(p.media_url) + '" alt="" /></div>';
    }
    var initial = (p.author_name || "S").charAt(0).toUpperCase();
    var commentsHtml = (p.comments || []).map(function (c) {
      return '<div class="post-comment">' +
        '<div class="comment-avatar">' + escHtml((c.author_name || "S").charAt(0).toUpperCase()) + '</div>' +
        '<div class="comment-body">' +
        '<strong>' + escHtml(c.author_name || "Student") + '</strong>' +
        '<p>' + escHtml(c.content) + '</p>' +
        '</div></div>';
    }).join("");
    var commentsBlock = commentsHtml
      ? '<div class="post-comments">' + commentsHtml + '</div>'
      : "";
    var bodyHtml = body
      ? '<p class="post-body">' + escHtml(body) + '</p>'
      : (p.media_type === "audio" ? '<p class="post-body voice-label">&#127908; Voice message</p>' : "");
    return '<article class="community-post">' +
      '<div class="post-top">' +
      '<div class="post-avatar">' + escHtml(initial) + '</div>' +
      '<div class="post-main">' +
      '<div class="post-head"><strong>' + escHtml(p.author_name || "Student") + '</strong>' +
      '<span>' + formatDate(p.created_at) + '</span></div>' +
      bodyHtml + media +
      renderPostActions(p) + commentsBlock +
      '</div></div></article>';
  }).join("");
}

async function ensureCommunityChannel() {
  restoreCommunityChannelId();
  if (communityChannelId) return communityChannelId;
  var channels = await api("/api/v1/community/channels");
  var general = (channels || []).find(function (c) { return c.type === "general"; }) || (channels || [])[0];
  if (!general) return null;
  saveCommunityChannelId(general.id);
  try {
    await api("/api/v1/community/join", {
      method: "POST",
      body: JSON.stringify({ channel_id: communityChannelId }),
    });
  } catch (joinErr) { /* already joined */ }
  return communityChannelId;
}

function normalizeCreatedPost(created, content, mediaUrl, mediaType) {
  return {
    id: created.id,
    author_name: created.author_name || getUser().name || "Student",
    content: created.content != null ? created.content : content,
    media_url: created.media_url || mediaUrl || null,
    media_type: created.media_type || mediaType || null,
    created_at: created.created_at || new Date().toISOString(),
    like_count: created.like_count || 0,
    liked_by_me: false,
    comments: [],
  };
}

function prependNewPost(posts, newPost) {
  if (!newPost || !newPost.id) return posts;
  var list = posts || [];
  if (list.some(function (p) { return p.id === newPost.id; })) return list;
  return [newPost].concat(list);
}

async function fetchCommunityPosts() {
  await ensureCommunityChannel();
  var posts = [];
  try {
    posts = await api("/api/v1/community/feed?limit=50") || [];
  } catch (e1) {
    if (!communityChannelId) return [];
    try {
      posts = await api("/api/v1/community/posts?channel_id=" + communityChannelId + "&limit=50") || [];
    } catch (e2) {
      var messages = await api("/api/v1/community/messages?channel_id=" + communityChannelId + "&limit=50");
      posts = mapMessagesToPosts(messages);
    }
  }

  if (communityChannelId) {
    try {
      var allPosts = await api("/api/v1/community/posts?channel_id=" + communityChannelId + "&limit=100") || [];
      var seen = {};
      posts.forEach(function (p) { seen[p.id] = true; });
      allPosts.forEach(function (p) {
        if (!seen[p.id] && !isPostComment(p.content)) {
          posts.push(p);
          seen[p.id] = true;
        }
      });
    } catch (e) { /* optional merge */ }
  }

  posts = posts.filter(function (p) { return !isPostComment(p.content); });
  var commentsByPost = await fetchPostComments();
  return attachComments(posts, commentsByPost);
}

function openCommunityCreate() {
  showPage("community-create");
}

function clearCommunityImage() {
  if (communityDraftImage && communityDraftImage.previewUrl) {
    URL.revokeObjectURL(communityDraftImage.previewUrl);
  }
  communityDraftImage = null;
  var preview = document.getElementById("community-image-preview");
  var clearBtn = document.getElementById("community-image-clear");
  var fileInput = document.getElementById("community-image-input");
  if (preview) {
    preview.innerHTML = "";
    preview.classList.add("hidden");
  }
  if (clearBtn) clearBtn.classList.add("hidden");
  if (fileInput) fileInput.value = "";
}

function onCommunityImagePick(input) {
  var err = document.getElementById("community-create-error");
  var file = input && input.files && input.files[0];
  if (!file) return;
  if (!/^image\/(jpeg|png|webp)$/i.test(file.type)) {
    if (err) err.textContent = "Please choose a JPG, PNG, or WebP image.";
    input.value = "";
    return;
  }
  if (file.size > 20 * 1024 * 1024) {
    if (err) err.textContent = "Image must be under 20 MB.";
    input.value = "";
    return;
  }
  if (err) err.textContent = "";
  clearCommunityImage();
  communityDraftImage = { file: file, previewUrl: URL.createObjectURL(file) };
  var preview = document.getElementById("community-image-preview");
  var clearBtn = document.getElementById("community-image-clear");
  if (preview) {
    preview.innerHTML = '<img src="' + communityDraftImage.previewUrl + '" alt="Selected image" />';
    preview.classList.remove("hidden");
  }
  if (clearBtn) clearBtn.classList.remove("hidden");
}

function initCommunityCreate() {
  var av = document.getElementById("community-create-avatar");
  if (av) av.textContent = (getUser().name || "S").charAt(0).toUpperCase();
  var input = document.getElementById("community-create-input");
  var err = document.getElementById("community-create-error");
  var postBtn = document.getElementById("community-post-btn");
  if (input) input.value = "";
  if (err) err.textContent = "";
  if (postBtn) { postBtn.disabled = false; postBtn.textContent = "Post"; }
  clearCommunityImage();
  clearCommunityVoice();
  initCommunityVoiceRecorder();
  if (input) input.focus();
}

async function loadCommunity(newPost) {
  if (communityActiveTab === "announcements") {
    return loadCommunityAnnouncements();
  }
  var feed = document.getElementById("community-feed");
  if (!feed) return;

  restoreCommunityChannelId();
  var cached = loadCommunityCache();
  var showingCache = false;
  if (cached && cached.posts && cached.posts.length) {
    renderCommunityPosts(newPost ? prependNewPost(cached.posts, newPost) : cached.posts);
    showingCache = true;
  } else if (newPost) {
    renderCommunityPosts([newPost]);
    showingCache = true;
  } else {
    feed.innerHTML = '<div class="loading">Loading posts…</div>';
  }

  try {
    var channelId = await ensureCommunityChannel();
    if (!channelId) {
      if (!showingCache) feed.innerHTML = '<div class="empty">Community is not set up yet.</div>';
      return;
    }
    var posts = await fetchCommunityPosts();
    if (newPost) posts = prependNewPost(posts, newPost);
    saveCommunityCache(posts);
    renderCommunityPosts(posts);
  } catch (e) {
    if (showingCache) return;
    if (newPost) {
      renderCommunityPosts([newPost]);
      saveCommunityCache([newPost]);
      return;
    }
    var msg = e.message === "Failed to fetch"
      ? "Could not reach the server. Check your internet and try Refresh."
      : e.message;
    feed.innerHTML = '<div class="empty">' + escHtml(msg) + '</div>';
  }
}

async function prefetchCommunityFeed() {
  restoreCommunityChannelId();
  try {
    await ensureCommunityChannel();
    var posts = await fetchCommunityPosts();
    if (posts && posts.length) saveCommunityCache(posts);
  } catch (e) { /* background warm-up */ }
}

async function submitCommunityPost() {
  var input = document.getElementById("community-create-input");
  var err = document.getElementById("community-create-error");
  var postBtn = document.getElementById("community-post-btn");
  var content = input.value.trim();
  if (!content && !communityDraftImage && !(communityVoiceRecorder && communityVoiceRecorder.hasRecording())) {
    err.textContent = "Write something, add an image, or record a voice note.";
    return;
  }
  if (communityVoiceRecorder && communityVoiceRecorder.isRecording()) {
    err.textContent = "Stop recording before you post.";
    return;
  }
  err.textContent = "";
  try {
    await ensureCommunityChannel();
  } catch (e) {
    err.textContent = e.message;
    return;
  }
  if (!communityChannelId) {
    err.textContent = "Community is not available right now.";
    return;
  }

  var mediaUrl = null;
  var mediaType = null;
  if (postBtn) { postBtn.disabled = true; postBtn.textContent = "Posting…"; }
  try {
    if (communityDraftImage) {
      var uploaded = await apiUpload("/api/v1/community/upload", communityDraftImage.file);
      mediaUrl = uploaded.file_url;
      mediaType = uploaded.file_type || "image";
    } else if (communityVoiceRecorder && communityVoiceRecorder.hasRecording()) {
      var voiceFile = communityVoiceRecorder.getFile();
      if (voiceFile) {
        var audioUp = await apiUpload("/api/v1/community/upload", voiceFile);
        mediaUrl = audioUp.file_url;
        mediaType = audioUp.file_type || "audio";
      }
    }
    var created = await api("/api/v1/community/posts", {
      method: "POST",
      body: JSON.stringify({
        channel_id: communityChannelId,
        content: content || (mediaType === "audio" ? "Voice note" : ""),
        media_url: mediaUrl,
        media_type: mediaType,
      }),
    });
    var newPost = normalizeCreatedPost(created, content, mediaUrl, mediaType);
    var cachedPosts = (loadCommunityCache() || {}).posts || [];
    saveCommunityCache(prependNewPost(cachedPosts, newPost));
    clearCommunityImage();
    clearCommunityVoice();
    if (input) input.value = "";
    communityPendingPost = newPost;
    showPage("community");
  } catch (e) {
    err.textContent = e.message;
    if (postBtn) { postBtn.disabled = false; postBtn.textContent = "Post"; }
  }
}

function toggleCommentBox(domId, interactId) {
  var box = document.getElementById("comment-box-" + domId);
  if (!box) return;
  var wasOpen = box.classList.contains("open");
  document.querySelectorAll(".comment-compose.open").forEach(function (el) {
    el.classList.remove("open");
  });
  if (!wasOpen) {
    box.classList.add("open");
    var input = document.getElementById("comment-input-" + domId);
    if (input) input.focus();
  }
}

async function submitCommunityComment(postId, domId) {
  if (!postId || String(postId).indexOf("orphan") === 0) return;
  var inputId = domId ? "comment-input-" + domId : "comment-input-" + postId;
  var input = document.getElementById(inputId);
  if (!input) return;
  var text = input.value.trim();
  if (!text) return;
  if (!communityChannelId) await loadCommunity();
  if (!communityChannelId) return;
  try {
    await api("/api/v1/community/messages", {
      method: "POST",
      body: JSON.stringify({
        channel_id: communityChannelId,
        content: "@post:" + postId + " " + text,
      }),
    });
    input.value = "";
    loadCommunity();
  } catch (e) {
    alert(e.message || "Could not post comment.");
  }
}

async function toggleCommunityLike(postId) {
  if (!postId || String(postId).indexOf("orphan") === 0) return;
  try {
    var data = await api("/api/v1/community/posts/" + postId + "/like", { method: "POST" });
    var btn = document.querySelector('[data-like-id="' + postId + '"]');
    if (btn) {
      btn.classList.toggle("liked", !!data.liked);
      var countEl = btn.querySelector(".like-count");
      if (countEl) countEl.textContent = data.like_count;
    }
  } catch (e) {
    alert(e.message || "Could not update like.");
  }
}

function showCommunityTab(tab) {
  communityActiveTab = tab;
  document.getElementById("community-tab-feed").classList.toggle("active", tab === "feed");
  document.getElementById("community-tab-announcements").classList.toggle("active", tab === "announcements");
  document.getElementById("community-feed").classList.toggle("hidden", tab !== "feed");
  document.getElementById("community-announcements").classList.toggle("hidden", tab !== "announcements");
  var fab = document.getElementById("community-fab");
  if (fab) fab.style.display = tab === "feed" ? "flex" : "none";
  if (tab === "announcements") loadCommunityAnnouncements();
  else loadCommunity();
}

async function loadCommunityAnnouncements() {
  var el = document.getElementById("community-announcements");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading announcements…</div>';
  try {
    var channels = await api("/api/v1/community/channels");
    var ann = (channels || []).find(function (c) { return c.type === "teacher_announcement"; });
    if (!ann) {
      el.innerHTML = '<div class="empty">No announcement channel yet.</div>';
      return;
    }
    var posts = await api("/api/v1/community/posts?channel_id=" + encodeURIComponent(ann.id) + "&limit=40");
    if (!posts || !posts.length) {
      el.innerHTML = '<div class="empty">No announcements from your teachers yet.</div>';
      return;
    }
    renderCommunityPosts(posts, el);
  } catch (e) {
    el.innerHTML = '<div class="empty">' + escHtml(e.message) + '</div>';
  }
}

function initCommunityVoiceRecorder() {
  if (communityVoiceRecorder) return;
  communityVoiceRecorder = createVoiceRecorder({
    buttonId: "community-voice-btn",
    statusId: "community-voice-status",
    previewId: "community-voice-preview",
    playbackId: "community-voice-playback",
    deleteButtonId: "community-voice-delete",
    idleLabel: "🎤 Tap to record voice",
    onError: function (e) {
      var err = document.getElementById("community-create-error");
      if (err) err.textContent = e.message || "Could not access microphone.";
    },
  });
}

function clearCommunityVoice() {
  if (communityVoiceRecorder) communityVoiceRecorder.cancel();
}

window.prefetchCommunityFeed = prefetchCommunityFeed;
window.showCommunityTab = showCommunityTab;
window.clearCommunityVoice = clearCommunityVoice;
window.initCommunityVoiceRecorder = initCommunityVoiceRecorder;
window.openCommunityCreate = openCommunityCreate;
window.submitCommunityPost = submitCommunityPost;
