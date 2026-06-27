var communityChannelId = null;
var communityDraftImage = null;
var communityVoiceRecorder = null;
var communityPendingPost = null;
var communityActiveTab = "feed";
var COMMUNITY_CHANNEL_KEY = "sia_community_channel_id";
var COMMUNITY_POSTS_CACHE_KEY = "sia_community_posts_cache";
var COMMUNITY_DRAFT_KEY = "sia_community_compose_draft";
var POST_COMMENT_RE = /^@post:([^\s]+)\s*([\s\S]*)$/;
var GROUP_POST_RE = /^@group:([^\s]+)(?:\s+([\s\S]*))?$/;

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

function updatePostInCache(postId, patch) {
  var cached = loadCommunityCache();
  if (!cached || !cached.posts) return;
  var pid = String(postId);
  var changed = false;
  var posts = cached.posts.map(function (p) {
    if (String(p.id) !== pid) return p;
    changed = true;
    return Object.assign({}, p, patch);
  });
  if (changed) saveCommunityCache(posts);
}

function showFeedSkeleton(targetEl) {
  var feed = targetEl || document.getElementById("community-feed");
  if (!feed) return;
  feed.innerHTML =
    '<div class="feed-skeleton" aria-busy="true" aria-label="Loading posts">' +
    '<div class="skel-card"></div><div class="skel-card skel-short"></div><div class="skel-card"></div>' +
    '<p class="skel-label">Loading community…</p></div>';
}

function showGroupsSkeleton(el) {
  if (!el) return;
  el.innerHTML =
    '<div class="feed-skeleton" aria-busy="true">' +
    '<div class="skel-card skel-group"></div><div class="skel-card skel-group"></div></div>';
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

function saveCommunityDraft(text) {
  try { localStorage.setItem(COMMUNITY_DRAFT_KEY, text || ""); } catch (e) { /* ignore */ }
}

function restoreCommunityDraft() {
  var input = document.getElementById("community-create-input");
  if (!input) return;
  try {
    var draft = localStorage.getItem(COMMUNITY_DRAFT_KEY);
    if (draft && !input.value) input.value = draft;
  } catch (e) { /* ignore */ }
}

function clearCommunityDraft() {
  try { localStorage.removeItem(COMMUNITY_DRAFT_KEY); } catch (e) { /* ignore */ }
}

function normalizePostId(id) {
  return String(id || "").trim().toLowerCase();
}

function isPostComment(content) {
  return POST_COMMENT_RE.test(content || "");
}

function isRealPostId(id) {
  return id && String(id).indexOf("orphan") !== 0;
}

function parseGroupPost(content) {
  var match = GROUP_POST_RE.exec(content || "");
  if (!match) return null;
  return { groupId: match[1], text: (match[2] || "").trim() };
}

function isGroupPost(p) {
  if (!p) return false;
  if (p.post_type === "group" && p.group_id) return true;
  return !!parseGroupPost(p.content);
}

function groupPostIdFromPost(p) {
  if (p.group_id) return p.group_id;
  var parsed = parseGroupPost(p.content);
  return parsed ? parsed.groupId : null;
}

function renderGroupFeedCard(p) {
  var gid = groupPostIdFromPost(p);
  if (!gid) return "";
  var safeGid = String(gid).replace(/'/g, "\\'");
  var name = p.group_name || "Study group";
  var desc = p.group_description || parseGroupPost(p.content || "");
  desc = typeof desc === "string" ? desc : (desc && desc.text) || "";
  var members = p.group_member_count != null ? p.group_member_count : 0;
  var initial = name.charAt(0).toUpperCase();
  var actions = "";
  if (p.group_is_member) {
    actions = '<button type="button" class="btn-action group-feed-btn" onclick="openGroupChat(\'' + safeGid + '\')">Open chat</button>';
    if (p.group_is_admin) {
      actions += '<button type="button" class="btn-sm" onclick="viewGroupRequests(\'' + safeGid + '\')">Manage requests</button>';
    }
  } else if (p.group_pending_request) {
    actions = '<span class="group-status-pill pending">Join request pending</span>';
  } else {
    actions = '<button type="button" class="btn-action group-feed-btn" onclick="requestJoinGroup(\'' + safeGid + '\')">Join group</button>';
  }
  return '<article class="community-post group-feed-post">' +
    '<div class="group-feed-banner"><span class="group-feed-tag">New group</span></div>' +
    '<div class="post-top">' +
    '<div class="post-avatar group-feed-avatar">' + escHtml(initial) + '</div>' +
    '<div class="post-main">' +
    '<div class="post-head"><strong>' + escHtml(name) + '</strong>' +
    '<span>' + formatDate(p.created_at) + '</span></div>' +
    '<p class="post-body group-feed-desc">' + escHtml(desc || "Tap join to request access — admin approves new members.") + '</p>' +
    '<p class="group-feed-meta">' + escHtml(p.author_name || "Student") + ' started this group · ' + members + ' member' + (members === 1 ? '' : 's') + '</p>' +
    '<div class="group-feed-actions">' + actions + '</div>' +
    '</div></div></article>';
}

function parsePostComment(content) {
  var match = POST_COMMENT_RE.exec(content || "");
  if (!match) return null;
  return { parentId: normalizePostId(match[1]), text: (match[2] || "").trim() };
}

function displayPostContent(content) {
  var parsed = parseGroupPost(content);
  if (parsed) return parsed.text;
  parsed = parsePostComment(content);
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

function ingestCommentItems(commentsByPost, items, nameKey) {
  (items || []).forEach(function (item) {
    var parsed = parsePostComment(item.content || "");
    if (!parsed || !parsed.text) return;
    var parentId = parsed.parentId;
    if (!commentsByPost[parentId]) commentsByPost[parentId] = [];
    var cid = String(item.id || "");
    if (cid && commentsByPost[parentId].some(function (c) { return c.id === cid; })) return;
    commentsByPost[parentId].push({
      id: cid,
      author_name: item[nameKey] || item.author_name || "Student",
      content: parsed.text,
      created_at: item.created_at || new Date().toISOString(),
    });
  });
  Object.keys(commentsByPost).forEach(function (pid) {
    commentsByPost[pid].sort(function (a, b) {
      return new Date(a.created_at) - new Date(b.created_at);
    });
  });
}

async function fetchPostComments() {
  var commentsByPost = {};
  if (!communityChannelId) return commentsByPost;

  try {
    var messages = await api(
      "/api/v1/community/messages?channel_id=" + encodeURIComponent(communityChannelId) + "&limit=200"
    );
    ingestCommentItems(commentsByPost, messages, "sender_name");
  } catch (e) {
    console.warn("Could not load comment messages", e);
  }

  try {
    var replyPosts = await api(
      "/api/v1/community/post-comments?channel_id=" + encodeURIComponent(communityChannelId) + "&limit=200"
    );
    ingestCommentItems(commentsByPost, replyPosts, "author_name");
  } catch (e) {
    console.warn("Could not load comment posts", e);
  }

  return commentsByPost;
}

function attachComments(posts, commentsByPost) {
  return (posts || []).map(function (p) {
    var pid = normalizePostId(p.id);
    return Object.assign({}, p, { comments: commentsByPost[pid] || [] });
  });
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
    if (isGroupPost(p)) return renderGroupFeedCard(p);
    var domId = postCardDomId(p);
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
      ? '<div class="post-comments" id="post-comments-' + escHtml(domId) + '">' + commentsHtml + '</div>'
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
  var apiFn = typeof apiRetry === "function" ? apiRetry : api;
  var channels = await apiFn("/api/v1/community/channels", { attempts: 2 });
  var general = (channels || []).find(function (c) { return c.type === "general"; });
  if (!general) return null;
  saveCommunityChannelId(general.id);
  try {
    await api("/api/v1/community/join", {
      method: "POST",
      body: JSON.stringify({ channel_id: general.id }),
    });
  } catch (joinErr) { /* already joined */ }
  return general.id;
}

function mergePostsWithCache(serverPosts, cachedPosts) {
  var cacheById = {};
  (cachedPosts || []).forEach(function (p) {
    if (p && p.id) cacheById[p.id] = p;
  });
  var merged = [];
  var seen = {};
  (serverPosts || []).forEach(function (p) {
    if (!p || !p.id) return;
    var cached = cacheById[p.id];
    var row = p;
    if (cached) {
      row = Object.assign({}, p, {
        liked_by_me: p.liked_by_me != null ? p.liked_by_me : cached.liked_by_me,
        like_count: p.like_count != null ? p.like_count : cached.like_count,
        comments: (p.comments && p.comments.length) ? p.comments : (cached.comments || []),
      });
    }
    merged.push(row);
    seen[p.id] = true;
  });
  (cachedPosts || []).forEach(function (p) {
    if (p && p.id && !seen[p.id]) merged.push(p);
  });
  merged.sort(function (a, b) {
    return new Date(b.created_at || 0) - new Date(a.created_at || 0);
  });
  return merged;
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
  var channelId = communityChannelId;
  var apiFn = typeof apiRetry === "function" ? apiRetry : api;

  var feedPromise = apiFn("/api/v1/community/feed?limit=50", { attempts: 3 }).catch(function (e1) {
    if (!channelId) return [];
    return apiFn("/api/v1/community/posts?channel_id=" + channelId + "&limit=50", { attempts: 2 }).catch(function () {
      return [];
    });
  });
  var commentsPromise = channelId ? fetchPostComments() : Promise.resolve({});
  var listedPromise = apiFn("/api/v1/student-groups/community-listed", { attempts: 2 }).catch(function () { return []; });

  var results = await Promise.all([feedPromise, commentsPromise, listedPromise]);
  var posts = results[0] || [];
  var commentsByPost = results[1] || {};
  var listed = results[2] || [];

  posts = (posts || []).filter(function (p) { return !isPostComment(p.content); });
  posts = attachComments(posts, commentsByPost);

  var seenGroups = {};
  posts.forEach(function (p) {
    var gid = groupPostIdFromPost(p);
    if (gid) seenGroups[gid] = true;
  });
  listed.forEach(function (g) {
    if (!g.id || seenGroups[g.id]) return;
    posts.push({
      id: "group-feed-" + g.id,
      card_key: "group-feed-" + g.id,
      post_type: "group",
      group_id: g.id,
      group_name: g.name,
      group_description: g.description,
      group_member_count: g.member_count,
      group_is_member: g.is_member,
      group_is_admin: g.is_admin,
      group_pending_request: g.pending_request,
      author_name: g.creator_name || "Student",
      created_at: g.created_at || new Date().toISOString(),
      content: "@group:" + g.id + (g.description ? " " + g.description : ""),
      like_count: 0,
      liked_by_me: false,
      comments: [],
    });
  });
  posts.sort(function (a, b) {
    return new Date(b.created_at || 0) - new Date(a.created_at || 0);
  });
  return posts;
}

function openCommunityCreate() {
  if (document.getElementById("discord-community-frame")) {
    if (typeof loadDiscordCommunity === "function") loadDiscordCommunity(false);
    return;
  }
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
  restoreCommunityDraft();
  if (err) err.textContent = "";
  if (postBtn) { postBtn.disabled = false; postBtn.textContent = "Post"; }
  clearCommunityImage();
  clearCommunityVoice();
  initCommunityVoiceRecorder();
  if (input) input.focus();
}

function appendCommentToPosts(posts, parentId, comment) {
  var pid = normalizePostId(parentId);
  return (posts || []).map(function (p) {
    if (normalizePostId(p.id) !== pid) return p;
    var existing = p.comments || [];
    if (comment.id && existing.some(function (c) { return c.id === comment.id; })) return p;
    return Object.assign({}, p, { comments: existing.concat([comment]) });
  });
}

async function refreshCommunityComments(posts) {
  var base = posts || (loadCommunityCache() || {}).posts || [];
  if (!base.length) return base;
  try {
    await ensureCommunityChannel();
    var commentsByPost = await fetchPostComments();
    var merged = attachComments(base, commentsByPost);
    saveCommunityCache(merged);
    if (communityActiveTab === "feed") renderCommunityPosts(merged);
    return merged;
  } catch (e) {
    return base;
  }
}

async function loadCommunity(newPost) {
  if (document.getElementById("discord-community-frame") && typeof loadDiscordCommunity === "function") {
    return loadDiscordCommunity(false);
  }
  return loadCommunityLegacy(newPost);
}

async function loadCommunityLegacy(newPost) {
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
    feed.classList.add("feed-refreshing");
  } else if (newPost) {
    renderCommunityPosts([newPost]);
    showingCache = true;
  } else {
    showFeedSkeleton(feed);
  }

  try {
    if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
    var channelId = await ensureCommunityChannel();
    if (!channelId) {
      feed.classList.remove("feed-refreshing");
      if (!showingCache) feed.innerHTML = '<div class="empty">Community is not set up yet.</div>';
      return;
    }
    var posts = await fetchCommunityPosts();
    if (newPost) posts = prependNewPost(posts, newPost);
    var cachedPosts = (cached && cached.posts) || [];
    posts = mergePostsWithCache(posts, cachedPosts);
    feed.classList.remove("feed-refreshing");
    if (posts.length) {
      saveCommunityCache(posts);
      renderCommunityPosts(posts);
    } else if (showingCache && cachedPosts.length) {
      renderCommunityPosts(cachedPosts);
    } else {
      renderCommunityPosts([]);
    }
  } catch (e) {
    feed.classList.remove("feed-refreshing");
    if (showingCache) {
      try { await refreshCommunityComments(cached && cached.posts); } catch (e2) { /* keep cache */ }
      return;
    }
    if (newPost) {
      renderCommunityPosts([newPost]);
      saveCommunityCache([newPost]);
      return;
    }
    var msg = /failed to fetch|timed out/i.test(e.message || "")
      ? "Could not reach the server yet. Tap Refresh — the server may be waking up."
      : e.message;
    feed.innerHTML = '<div class="empty">' + escHtml(msg) + '</div>';
  }
}

async function prefetchCommunityFeed() {
  restoreCommunityChannelId();
  try {
    if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
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
    clearCommunityDraft();
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
  var list = document.getElementById("post-comments-" + domId);
  if (!box) return;
  var wasOpen = box.classList.contains("open");
  document.querySelectorAll(".comment-compose.open").forEach(function (el) {
    el.classList.remove("open");
  });
  document.querySelectorAll(".post-comments.open").forEach(function (el) {
    el.classList.remove("open");
  });
  if (!wasOpen) {
    box.classList.add("open");
    if (list) list.classList.add("open");
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
  await ensureCommunityChannel();
  if (!communityChannelId) {
    alert("Community is not available right now.");
    return;
  }
  var parentId = normalizePostId(postId);
  var replyBtn = input.parentElement && input.parentElement.querySelector(".btn-comment");
  if (replyBtn) { replyBtn.disabled = true; replyBtn.textContent = "Sending…"; }
  try {
    var created = await api("/api/v1/community/posts", {
      method: "POST",
      body: JSON.stringify({
        channel_id: communityChannelId,
        content: "@post:" + parentId + " " + text,
      }),
    });
    input.value = "";
    var box = document.getElementById("comment-box-" + (domId || postId));
    if (box) box.classList.add("open");
    var list = document.getElementById("post-comments-" + (domId || postId));
    if (list) list.classList.add("open");
    var comment = {
      id: created.id || "",
      author_name: created.author_name || getUser().name || "Student",
      content: text,
      created_at: created.created_at || new Date().toISOString(),
    };
    var cachedPosts = (loadCommunityCache() || {}).posts || [];
    var updated = appendCommentToPosts(cachedPosts, parentId, comment);
    saveCommunityCache(updated);
    renderCommunityPosts(updated);
    refreshCommunityComments(updated).catch(function () { /* background sync */ });
  } catch (e) {
    alert(e.message || "Could not post comment.");
  } finally {
    if (replyBtn) { replyBtn.disabled = false; replyBtn.textContent = "Reply"; }
  }
}

async function toggleCommunityLike(postId) {
  if (!postId || String(postId).indexOf("orphan") === 0 || String(postId).indexOf("group-feed-") === 0) return;
  var btn = document.querySelector('[data-like-id="' + postId + '"]');
  var wasLiked = btn && btn.classList.contains("liked");
  var prevCount = btn ? parseInt(btn.querySelector(".like-count").textContent, 10) || 0 : 0;
  if (btn) {
    btn.classList.toggle("liked", !wasLiked);
    var countEl = btn.querySelector(".like-count");
    if (countEl) countEl.textContent = Math.max(0, prevCount + (wasLiked ? -1 : 1));
  }
  try {
    var apiFn = typeof apiRetry === "function" ? apiRetry : api;
    var data = await apiFn("/api/v1/community/posts/" + postId + "/like", { method: "POST", attempts: 2 });
    updatePostInCache(postId, { liked_by_me: !!data.liked, like_count: data.like_count });
    if (btn) {
      btn.classList.toggle("liked", !!data.liked);
      var countEl2 = btn.querySelector(".like-count");
      if (countEl2) countEl2.textContent = data.like_count;
    }
  } catch (e) {
    if (btn) {
      btn.classList.toggle("liked", wasLiked);
      var countEl3 = btn.querySelector(".like-count");
      if (countEl3) countEl3.textContent = prevCount;
    }
    alert(e.message || "Could not update like.");
  }
}

function showCommunityTab(tab) {
  if (document.getElementById("discord-community-frame") && typeof loadDiscordCommunity === "function") {
    loadDiscordCommunity(false);
    return;
  }
  communityActiveTab = tab;
  document.getElementById("community-tab-feed").classList.toggle("active", tab === "feed");
  document.getElementById("community-tab-announcements").classList.toggle("active", tab === "announcements");
  var groupsTab = document.getElementById("community-tab-groups");
  if (groupsTab) groupsTab.classList.toggle("active", tab === "groups");
  document.getElementById("community-feed").classList.toggle("hidden", tab !== "feed");
  document.getElementById("community-announcements").classList.toggle("hidden", tab !== "announcements");
  var groupsPanel = document.getElementById("community-groups-panel");
  if (groupsPanel) groupsPanel.classList.toggle("hidden", tab !== "groups");
  var fab = document.getElementById("community-fab");
  if (fab) fab.style.display = tab === "feed" ? "flex" : "none";
  if (tab === "announcements") loadCommunityAnnouncements();
  else if (tab === "groups") {
    if (typeof loadGroupsPage === "function") loadGroupsPage();
  } else {
    if (typeof markCommunityRead === "function") markCommunityRead();
    loadCommunity();
  }
}

async function loadCommunityAnnouncements() {
  var el = document.getElementById("community-announcements");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading announcements…</div>';
  try {
    var posts = await api("/api/v1/community/announcements?limit=40");
    if (!posts || !posts.length) {
      el.innerHTML = '<div class="empty">No announcements from your teachers yet.</div>';
      return;
    }
    renderCommunityPosts(posts, el);
  } catch (e) {
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
    } catch (e2) {
      el.innerHTML = '<div class="empty">' + escHtml(e2.message || e.message) + '</div>';
    }
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
window.showGroupsSkeleton = showGroupsSkeleton;
window.clearCommunityVoice = clearCommunityVoice;
window.initCommunityVoiceRecorder = initCommunityVoiceRecorder;
window.openCommunityCreate = openCommunityCreate;
window.submitCommunityPost = submitCommunityPost;

(function bindCommunityDraft() {
  function attach() {
    var input = document.getElementById("community-create-input");
    if (!input || input.dataset.draftBound) return;
    input.dataset.draftBound = "1";
    input.addEventListener("input", function () {
      saveCommunityDraft(input.value);
    });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", attach);
  } else {
    attach();
  }
})();
