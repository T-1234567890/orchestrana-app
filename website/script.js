const scrollToHash = (hash, behavior = 'auto') => {
  if (!hash || hash === '#') return;
  const target = document.querySelector(hash);
  if (target) target.scrollIntoView({ behavior, block: 'start' });
};

// IntersectionObserver for scroll reveals
const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.2 });

document.querySelectorAll('.reveal').forEach((el) => revealObserver.observe(el));

let currentLang = 'en';

const translations = {
  en: {
    project_status: 'Project status',
    view_github: 'View on GitHub',
    minutes_ago: '{n} minutes ago',
    hours_ago: '{n} hours ago',
    days_ago: '{n} days ago',
    weeks_ago: '{n} weeks ago',
    months_ago: '{n} months ago'
  },
  zh: {
    project_status: '项目状态',
    view_github: '在 GitHub 查看',
    minutes_ago: '{n} 分钟前',
    hours_ago: '{n} 小时前',
    days_ago: '{n} 天前',
    weeks_ago: '{n} 周前',
    months_ago: '{n} 月前'
  }
};

function translate(key, params = {}, lang = currentLang) {
  const localeTable = translations[lang] || translations.en;
  const fallback = translations.en[key] || '';
  const template = localeTable[key] || fallback;
  return template.replace(/\{(\w+)\}/g, (match, token) => {
    if (!(token in params)) return match;
    return String(params[token]);
  });
}

function applyLanguage(lang) {
  currentLang = lang;
  document.documentElement.lang = lang === 'zh' ? 'zh-Hans' : 'en';
  const elements = document.querySelectorAll('[data-en]');
  elements.forEach((el) => {
    const next = lang === 'zh' ? el.dataset.zh : el.dataset.en;
    if (next !== undefined) el.innerHTML = next;
  });
  const keyedElements = document.querySelectorAll('[data-i18n-key]');
  keyedElements.forEach((el) => {
    const key = el.dataset.i18nKey;
    if (!key) return;
    el.innerHTML = translate(key, {}, lang);
  });
  const titleElements = document.querySelectorAll('[data-title-en]');
  titleElements.forEach((el) => {
    const nextTitle = lang === 'zh' ? el.dataset.titleZh : el.dataset.titleEn;
    if (nextTitle !== undefined) el.title = nextTitle;
  });
  const tooltipElements = document.querySelectorAll('[data-tooltip-en]');
  tooltipElements.forEach((el) => {
    const nextTooltip = lang === 'zh' ? el.dataset.tooltipZh : el.dataset.tooltipEn;
    if (nextTooltip !== undefined) el.dataset.tooltip = nextTooltip;
  });
  localStorage.setItem('pomodoro-lang', lang);
}

function animateLanguageSwitch(nextLang) {
  const prefersReduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (prefersReduce) {
    applyLanguage(nextLang);
    return;
  }

  const root = document.body;
  const outDuration = 150; // within 120–160ms
  const inDuration = 210;  // within 180–240ms

  root.classList.remove('lang-switching-in');
  root.classList.add('lang-switching-out');

  window.setTimeout(() => {
    applyLanguage(nextLang);
    root.classList.remove('lang-switching-out');
    root.classList.add('lang-switching-in');

    window.setTimeout(() => {
      root.classList.remove('lang-switching-in');
    }, inDuration);
  }, outDuration);
}

// Language toggle button
const toggleBtn = document.getElementById('lang-toggle');
if (toggleBtn) {
  toggleBtn.addEventListener('click', () => {
    const next = currentLang === 'en' ? 'zh' : 'en';
    animateLanguageSwitch(next);
  });
}

// Smooth scroll for nav links
const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');
navLinks.forEach((link) => {
  link.addEventListener('click', (e) => {
    e.preventDefault();
    const hash = link.getAttribute('href');
    if (hash) history.pushState(null, '', hash);
    scrollToHash(hash, 'smooth');
  });
});

// Fade-in hero on load and only scroll when URL already has a hash
window.addEventListener('load', () => {
  document.querySelectorAll('.fade-on-load').forEach((el) => el.classList.add('visible'));

  if (location.hash) {
    const el = document.querySelector(location.hash);
    if (el) el.scrollIntoView();
  }
});

// Handle back/forward navigation between sections
window.addEventListener('popstate', () => {
  scrollToHash(window.location.hash, 'auto');
});

// Init language from storage or default
const stored = localStorage.getItem('pomodoro-lang');
applyLanguage(stored === 'zh' ? 'zh' : 'en');

const REPO_OWNER = 'T-1234567890';
const REPO_NAME = 'pomodoro-app';
const LIVE_GITHUB_ENABLED = /^https?:$/.test(window.location.protocol)
  && !['127.0.0.1', 'localhost'].includes(window.location.hostname);
const RIBBON_INVITE_URL = `https://github.com/${REPO_OWNER}/${REPO_NAME}`;
const RIBBON_CACHE_KEY = 'pomodoro-ribbon-users-v1';
const RIBBON_MAX_USERS = 30;
const RIBBON_MIN_SEGMENT_ITEMS = 18;
const RIBBON_REFRESH_MS = 5 * 60 * 1000;
const RIBBON_INVITE_PLACEHOLDER = {
  login: '__you__',
  html_url: RIBBON_INVITE_URL,
  placeholder: true,
  kind: 'invite'
};
const RIBBON_PLACEHOLDERS = [
  { login: '__placeholder_1__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true },
  { login: '__placeholder_2__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true },
  { login: '__placeholder_3__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true },
  { login: '__placeholder_4__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true },
  { login: '__placeholder_5__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true },
  { login: '__placeholder_6__', avatar_url: 'screenshots/Orchestrana%20icon%201.png', html_url: '', placeholder: true }
];

const ribbonState = {
  track: null,
  fallback: null,
  error: null,
  primarySegment: null,
  mirrorSegment: null,
  users: new Map(),
  renderedCounts: new Map(),
  initialized: false,
  requestPending: false,
  loadingRemoved: false
};

function createAvatarNode(user) {
  if (user.kind === 'invite') {
    const node = document.createElement('a');
    node.className = 'contributor-avatar contributor-avatar-invite';
    node.href = user.html_url || RIBBON_INVITE_URL;
    node.target = '_blank';
    node.rel = 'noreferrer';
    node.dataset.placeholder = 'true';
    node.dataset.titleEn = 'You could be here';
    node.dataset.titleZh = '下一个就是你';
    node.title = currentLang === 'zh' ? node.dataset.titleZh : node.dataset.titleEn;
    node.setAttribute('aria-label', node.title);

    const label = document.createElement('span');
    label.className = 'contributor-invite-label';
    label.dataset.en = 'You';
    label.dataset.zh = '你';
    label.textContent = currentLang === 'zh' ? label.dataset.zh : label.dataset.en;
    node.appendChild(label);
    return node;
  }

  const node = user.html_url ? document.createElement('a') : document.createElement('div');
  node.className = 'contributor-avatar';
  if (user.placeholder) node.dataset.placeholder = 'true';

  if (user.html_url) {
    node.href = user.html_url;
    node.target = '_blank';
    node.rel = 'noreferrer';
    node.setAttribute('aria-label', `@${user.login} on GitHub`);
  } else {
    node.setAttribute('aria-hidden', 'true');
  }

  const img = document.createElement('img');
  img.src = user.avatar_url;
  img.alt = '';
  img.loading = 'lazy';
  img.decoding = 'async';
  node.appendChild(img);

  return node;
}

function ensureRibbonDom() {
  if (ribbonState.initialized) return true;
  const track = document.getElementById('contributors-track');
  const fallback = document.getElementById('contributors-fallback');
  const error = document.getElementById('contributors-error');
  if (!track) return false;

  ribbonState.track = track;
  ribbonState.fallback = fallback;
  ribbonState.error = error;

  const primary = document.createElement('div');
  primary.className = 'contributors-segment';
  primary.dataset.segment = 'primary';

  const mirror = document.createElement('div');
  mirror.className = 'contributors-segment';
  mirror.dataset.segment = 'mirror';
  mirror.setAttribute('aria-hidden', 'true');

  track.appendChild(primary);
  track.appendChild(mirror);

  ribbonState.primarySegment = primary;
  ribbonState.mirrorSegment = mirror;
  ribbonState.initialized = true;
  return true;
}

function ribbonHasRenderedAvatars() {
  return Boolean(ribbonState.primarySegment && ribbonState.primarySegment.children.length > 0);
}

function removeRibbonLoadingNode() {
  if (!ribbonState.fallback) return;
  ribbonState.fallback.remove();
  ribbonState.fallback = null;
  ribbonState.loadingRemoved = true;
}

function setRibbonErrorVisible(visible) {
  if (!ribbonState.error) return;
  ribbonState.error.hidden = !visible;
}

function updateRibbonLoadingState() {
  if (!ribbonState.fallback || ribbonState.loadingRemoved) return;
  const shouldShowLoading = ribbonState.requestPending && !ribbonHasRenderedAvatars();
  if (!shouldShowLoading) {
    removeRibbonLoadingNode();
    return;
  }
  ribbonState.fallback.hidden = false;
}

function getRibbonViewportWidth() {
  return ribbonState.track?.parentElement?.clientWidth || 0;
}

function updateRibbonAnimationDuration() {
  if (!ribbonState.track || !ribbonState.primarySegment) return;
  const segmentWidth = ribbonState.primarySegment.scrollWidth;
  if (!segmentWidth) return;
  const duration = Math.min(30, Math.max(18, segmentWidth / 60));
  ribbonState.track.style.setProperty('--contributors-loop-duration', `${duration.toFixed(2)}s`);
}

function buildLoopSeed(users) {
  const base = Array.isArray(users) && users.length > 0 ? users : RIBBON_PLACEHOLDERS;
  const withInvite = [...base, RIBBON_INVITE_PLACEHOLDER];
  const seed = [];
  while (seed.length < RIBBON_MIN_SEGMENT_ITEMS) {
    withInvite.forEach((user) => seed.push(user));
  }
  return seed;
}

function ensureRibbonCoverage(seed, baseMaxPerLogin = 1) {
  if (!ribbonState.primarySegment) return;
  appendUsers(seed, baseMaxPerLogin);
  let maxPerLogin = baseMaxPerLogin;
  let guard = 0;
  const viewport = getRibbonViewportWidth();
  while (viewport > 0 && ribbonState.primarySegment.scrollWidth < (viewport + 40) && guard < 14) {
    maxPerLogin += 1;
    appendUsers(seed, maxPerLogin);
    guard += 1;
  }
  updateRibbonAnimationDuration();
}

function appendUsers(users, maxPerLogin = 1) {
  if (!ribbonState.primarySegment || !ribbonState.mirrorSegment) return 0;
  let added = 0;

  users.forEach((user) => {
    if (!user.login) return;
    const isInvite = user.kind === 'invite';
    if (!isInvite && !user.avatar_url) return;

    if (!ribbonState.users.has(user.login)) {
      ribbonState.users.set(user.login, {
        login: user.login,
        avatar_url: user.avatar_url,
        html_url: user.html_url || '',
        placeholder: Boolean(user.placeholder),
        kind: user.kind || ''
      });
    }

    const source = ribbonState.users.get(user.login);
    let rendered = ribbonState.renderedCounts.get(user.login) || 0;

    if (rendered >= maxPerLogin) return;
    ribbonState.primarySegment.appendChild(createAvatarNode(source));
    ribbonState.mirrorSegment.appendChild(createAvatarNode(source));
    rendered += 1;
    added += 1;

    ribbonState.renderedCounts.set(user.login, rendered);
  });

  if (added > 0) updateRibbonLoadingState();
  return added;
}

function getCachedRibbonUsers() {
  try {
    const raw = localStorage.getItem(RIBBON_CACHE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item) => item?.login && item?.avatar_url);
  } catch {
    return [];
  }
}

function saveRibbonUsersToCache() {
  try {
    const values = Array.from(ribbonState.users.values())
      .filter((item) => !item.placeholder)
      .map((item) => ({
        login: item.login,
        avatar_url: item.avatar_url,
        html_url: item.html_url || ''
      }));
    localStorage.setItem(RIBBON_CACHE_KEY, JSON.stringify(values));
  } catch {
    // ignore cache write failures
  }
}

async function fetchCommunityUsers() {
  const contributorsApi = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contributors?per_page=100`;
  const issuesApi = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues?state=all&per_page=100`;
  const [contributorsRes, issuesRes] = await Promise.all([fetch(contributorsApi), fetch(issuesApi)]);
  if (!contributorsRes.ok || !issuesRes.ok) throw new Error('Request failed');

  const [contributorsPayload, issuesPayload] = await Promise.all([contributorsRes.json(), issuesRes.json()]);
  const merged = new Map();
  const seenIds = new Set();

  const putUser = (candidate) => {
    if (!candidate?.login || !candidate?.avatar_url) return;
    const id = Number.isFinite(candidate.id) ? candidate.id : null;
    if (id !== null && seenIds.has(id)) return;
    if (merged.has(candidate.login)) return;

    merged.set(candidate.login, {
      login: candidate.login,
      avatar_url: candidate.avatar_url,
      html_url: candidate.html_url || ''
    });
    if (id !== null) seenIds.add(id);
  };

  if (Array.isArray(contributorsPayload)) {
    contributorsPayload.forEach((item) => {
      putUser(item);
    });
  }

  if (Array.isArray(issuesPayload)) {
    issuesPayload.forEach((issue) => {
      putUser(issue?.user);
    });
  }

  return Array.from(merged.values()).slice(0, RIBBON_MAX_USERS);
}

async function refreshContributorRibbon() {
  if (!ensureRibbonDom()) return;
  ribbonState.requestPending = true;
  setRibbonErrorVisible(false);
  updateRibbonLoadingState();

  try {
    const fetchedUsers = await fetchCommunityUsers();
    if (fetchedUsers.length > 0) {
      ensureRibbonCoverage(buildLoopSeed(fetchedUsers), 1);
      saveRibbonUsersToCache();
    } else {
      if (!ribbonHasRenderedAvatars()) {
        ensureRibbonCoverage(buildLoopSeed([]), 1);
      }
    }
  } catch {
    const cachedUsers = getCachedRibbonUsers();
    if (cachedUsers.length > 0) {
      ensureRibbonCoverage(buildLoopSeed(cachedUsers), 1);
    } else if (!ribbonHasRenderedAvatars()) {
      ensureRibbonCoverage(buildLoopSeed([]), 1);
    }
    setRibbonErrorVisible(true);
  } finally {
    ribbonState.requestPending = false;
    updateRibbonLoadingState();
  }
}

function startContributorRibbon() {
  if (!ensureRibbonDom()) return;

  const cachedUsers = getCachedRibbonUsers();
  if (cachedUsers.length > 0) {
    ensureRibbonCoverage(buildLoopSeed(cachedUsers), 1);
  }

  if (!LIVE_GITHUB_ENABLED) {
    if (!ribbonHasRenderedAvatars()) {
      ensureRibbonCoverage(buildLoopSeed([]), 1);
    }
    return;
  }

  refreshContributorRibbon();
  window.setInterval(refreshContributorRibbon, RIBBON_REFRESH_MS);
  window.addEventListener('resize', () => {
    if (!ribbonState.primarySegment) return;
    const realUsers = Array.from(ribbonState.users.values()).filter((user) => !user.placeholder);
    ensureRibbonCoverage(buildLoopSeed(realUsers), 1);
  });
}

function parseLastPage(linkHeader) {
  if (!linkHeader) return null;
  const parts = linkHeader.split(',').map((part) => part.trim());
  const last = parts.find((part) => part.includes('rel="last"'));
  if (!last) return null;
  const match = last.match(/[?&]page=(\d+)/);
  if (!match) return null;
  return Number.parseInt(match[1], 10);
}

const FOOTER_REFRESH_MS = 5 * 60 * 1000;

function animateFooterNumbers() {
  const numbers = [
    document.getElementById('footer-stars'),
    document.getElementById('footer-commits'),
    document.getElementById('footer-issues')
  ].filter(Boolean);

  numbers.forEach((node, index) => {
    node.classList.remove('is-live');
    // Force reflow so the same animation can be replayed on refresh.
    void node.offsetWidth;
    window.setTimeout(() => {
      node.classList.add('is-live');
    }, 200 * index);
  });
}

async function loadFooterHeartbeat() {
  const starsEl = document.getElementById('footer-stars');
  const commitsEl = document.getElementById('footer-commits');
  const issuesEl = document.getElementById('footer-issues');
  if (!starsEl || !commitsEl || !issuesEl) return;
  if (!LIVE_GITHUB_ENABLED) return;

  const repoApi = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}`;

  try {
    const repoRes = await fetch(repoApi);
    if (!repoRes.ok) throw new Error('Request failed');
    const repo = await repoRes.json();

    const branch = repo?.default_branch || 'main';
    const commitsRes = await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits?sha=${encodeURIComponent(branch)}&per_page=1`);
    if (!commitsRes.ok) throw new Error('Request failed');
    const commitsPayload = await commitsRes.json();
    const commitPages = parseLastPage(commitsRes.headers.get('link'));
    const commits = Number.isInteger(commitPages) ? commitPages : (Array.isArray(commitsPayload) ? commitsPayload.length : 0);

    const stars = Number.isFinite(repo?.stargazers_count) ? repo.stargazers_count : 0;
    const issues = Number.isFinite(repo?.open_issues_count) ? repo.open_issues_count : 0;

    const format = new Intl.NumberFormat('en-US');
    starsEl.textContent = format.format(stars);
    commitsEl.textContent = format.format(commits);
    issuesEl.textContent = format.format(issues);

    animateFooterNumbers();
  } catch (err) {}
}

const PROJECT_STATUS_REFRESH_MS = 5 * 60 * 1000;
const PROJECT_STATUS_COMMITS_API = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits?per_page=100`;
const PROJECT_STATUS_UPDATED_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

function getProjectStatusDom() {
  const dot = document.getElementById('project-status-dot');
  const label = document.getElementById('project-status-label');
  const sub = document.getElementById('project-status-sub');
  const streak = document.getElementById('project-status-streak');
  const commits = document.getElementById('project-status-commits');
  if (!dot || !label || !sub || !streak || !commits) return null;
  return { dot, label, sub, streak, commits };
}

function getRelativeCommitTime(isoDate) {
  const timestamp = Date.parse(isoDate || '');
  if (!Number.isFinite(timestamp)) return { minutes: null, ageMs: Number.POSITIVE_INFINITY };

  const ageMs = Math.max(0, Date.now() - timestamp);
  const minutes = Math.max(1, Math.floor(ageMs / (60 * 1000)));
  return { minutes, ageMs };
}

function formatRelativeTime(relative, lang = currentLang) {
  const minuteMs = 60 * 1000;
  const hourMs = 60 * minuteMs;
  const dayMs = 24 * hourMs;
  const weekMs = 7 * dayMs;
  const monthMs = 30 * dayMs;

  const fallbackAgeMs = Number(relative?.minutes) * minuteMs;
  const ageMs = Number(relative?.ageMs);
  const normalizedAgeMs = Number.isFinite(ageMs) ? ageMs : fallbackAgeMs;
  if (!Number.isFinite(normalizedAgeMs) || normalizedAgeMs < 0) return '--';

  if (normalizedAgeMs < hourMs) {
    return translate('minutes_ago', { n: Math.max(1, Math.floor(normalizedAgeMs / minuteMs)) }, lang);
  }
  if (normalizedAgeMs < dayMs) {
    return translate('hours_ago', { n: Math.max(1, Math.floor(normalizedAgeMs / hourMs)) }, lang);
  }
  if (normalizedAgeMs < weekMs) {
    return translate('days_ago', { n: Math.max(1, Math.floor(normalizedAgeMs / dayMs)) }, lang);
  }
  if (normalizedAgeMs < monthMs) {
    return translate('weeks_ago', { n: Math.max(1, Math.floor(normalizedAgeMs / weekMs)) }, lang);
  }
  return translate('months_ago', { n: Math.max(1, Math.floor(normalizedAgeMs / monthMs)) }, lang);
}

function setLocalizedCopy(node, en, zh) {
  node.dataset.en = en;
  node.dataset.zh = zh;
  node.textContent = currentLang === 'zh' ? zh : en;
}

function setProjectStatusState(dom, { tone = 'live', labelEn, labelZh }) {
  dom.dot.classList.remove('is-updated', 'is-live');
  dom.dot.classList.add(tone === 'updated' ? 'is-updated' : 'is-live');
  setLocalizedCopy(dom.label, labelEn, labelZh);
}

function setProjectStatusStreakState(dom, state, days = 0, lastCommitTextEn = '--', lastCommitTextZh = '--') {
  if (state === 'unavailable') {
    setLocalizedCopy(dom.streak, 'Streak unavailable', '连续记录加载中');
    setLocalizedCopy(dom.sub, 'Waiting for streak data', '正在获取连续数据');
    return;
  }

  if (state === 'starting') {
    setLocalizedCopy(dom.streak, 'Starting streak', '连续记录开始');
    setLocalizedCopy(dom.sub, 'Streak begins today', '今天开始连续记录');
    return;
  }

  const normalizedDays = Number.isFinite(days) && days > 0 ? days : 1;
  setLocalizedCopy(dom.streak, `${normalizedDays} day streak`, `连续 ${normalizedDays} 天`);
  setLocalizedCopy(dom.sub, `Last commit: ${lastCommitTextEn}`, `最近提交：${lastCommitTextZh}`);
}

function createProjectStatusSkeletonCard() {
  const card = document.createElement('article');
  card.className = 'project-status-commit-card is-skeleton';
  card.setAttribute('aria-hidden', 'true');

  const line = document.createElement('span');
  line.className = 'project-status-skeleton project-status-skeleton-line';
  card.appendChild(line);

  const meta = document.createElement('div');
  meta.className = 'project-status-commit-meta';

  const time = document.createElement('span');
  time.className = 'project-status-skeleton project-status-skeleton-time';
  meta.appendChild(time);

  const icon = document.createElement('span');
  icon.className = 'project-status-skeleton project-status-skeleton-icon';
  meta.appendChild(icon);

  card.appendChild(meta);
  return card;
}

function renderProjectStatusSkeleton(dom) {
  dom.commits.textContent = '';
  for (let i = 0; i < 3; i += 1) {
    dom.commits.appendChild(createProjectStatusSkeletonCard());
  }
}

function createProjectStatusCommitCard(item, index) {
  const card = document.createElement('article');
  card.className = 'project-status-commit-card is-loaded';
  card.style.animationDelay = `${index * 60}ms`;

  const message = document.createElement('p');
  message.className = 'project-status-commit-message';
  message.textContent = item.message || 'Commit update';
  card.appendChild(message);

  const meta = document.createElement('div');
  meta.className = 'project-status-commit-meta';

  const time = document.createElement('p');
  time.className = 'project-status-commit-time';
  setLocalizedCopy(
    time,
    formatRelativeTime(item.relative, 'en'),
    formatRelativeTime(item.relative, 'zh')
  );
  meta.appendChild(time);

  const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  icon.setAttribute('viewBox', '0 0 24 24');
  icon.setAttribute('aria-hidden', 'true');
  icon.classList.add('project-status-commit-repo-icon');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', 'M12 2.7a9.3 9.3 0 00-2.94 18.13c.47.08.64-.2.64-.45 0-.22-.01-.96-.01-1.74-2.35.43-2.96-.58-3.15-1.12-.1-.27-.53-1.12-.9-1.34-.31-.17-.74-.6-.01-.61.69-.01 1.18.64 1.34.9.79 1.33 2.05.96 2.55.73.08-.58.31-.96.56-1.18-2.08-.24-4.26-1.04-4.26-4.62 0-1.02.36-1.86.96-2.52-.1-.24-.43-1.22.09-2.54 0 0 .78-.25 2.56.96a8.83 8.83 0 014.66 0c1.78-1.22 2.56-.96 2.56-.96.51 1.32.18 2.3.09 2.54.6.66.96 1.49.96 2.52 0 3.58-2.19 4.38-4.27 4.62.32.28.6.82.6 1.66 0 1.2-.01 2.16-.01 2.46 0 .24.17.53.64.45A9.3 9.3 0 0012 2.7z');
  icon.appendChild(path);
  meta.appendChild(icon);

  card.appendChild(meta);
  return card;
}

function resetProjectStatusToLive(dom) {
  setProjectStatusState(dom, {
    tone: 'live',
    labelEn: 'Live',
    labelZh: '正在运行'
  });
  setProjectStatusStreakState(dom, 'starting');
}

function normalizeProjectStatusCommit(entry) {
  const iso = entry?.commit?.author?.date || entry?.commit?.committer?.date || '';
  const relative = getRelativeCommitTime(iso);
  const firstLine = String(entry?.commit?.message || '').split('\n')[0].trim();
  const timestamp = Date.parse(iso);
  return {
    message: firstLine,
    relative,
    timestamp: Number.isFinite(timestamp) ? timestamp : null
  };
}

function toLocalDayKey(timestamp) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function calculateCommitStreakDays(commits) {
  const timestamps = commits
    .map((item) => item.timestamp)
    .filter((value) => Number.isFinite(value));
  if (timestamps.length === 0) return 0;

  const daySet = new Set(
    timestamps.map((value) => toLocalDayKey(value))
  );

  const latestTimestamp = Math.max(...timestamps);
  const latestDayKey = toLocalDayKey(latestTimestamp);
  const todayKey = toLocalDayKey(Date.now());
  if (latestDayKey !== todayKey) return 0;

  const cursor = new Date(latestTimestamp);
  cursor.setHours(0, 0, 0, 0);

  let streak = 0;
  let guard = 0;
  while (daySet.has(toLocalDayKey(cursor.getTime())) && guard < 3650) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
    guard += 1;
  }
  return streak;
}

async function loadProjectStatus({ showSkeleton = false } = {}) {
  const dom = getProjectStatusDom();
  if (!dom) return;
  if (showSkeleton) renderProjectStatusSkeleton(dom);

  try {
    const response = await fetch(PROJECT_STATUS_COMMITS_API, {
      headers: { Accept: 'application/vnd.github+json' }
    });
    if (!response.ok) throw new Error('Request failed');

    const payload = await response.json();
    if (!Array.isArray(payload) || payload.length === 0) throw new Error('Empty payload');

    const normalized = payload.map(normalizeProjectStatusCommit);
    const commits = normalized.slice(0, 3);
    const latest = commits[0]?.relative;
    const isUpdated = latest?.ageMs <= PROJECT_STATUS_UPDATED_WINDOW_MS;
    const streakDays = calculateCommitStreakDays(normalized);
    const latestTimestamp = payload[0]?.commit?.author?.date || payload[0]?.commit?.committer?.date || null;
    const computedStatus = isUpdated ? 'Updated' : 'Live';

    setProjectStatusState(dom, {
      tone: isUpdated ? 'updated' : 'live',
      labelEn: isUpdated ? 'Updated' : 'Live',
      labelZh: isUpdated ? '已更新' : '正在运行'
    });
    if (streakDays <= 0) {
      setProjectStatusStreakState(dom, 'starting');
    } else {
      setProjectStatusStreakState(
        dom,
        'active',
        streakDays,
        formatRelativeTime(latest, 'en'),
        formatRelativeTime(latest, 'zh')
      );
    }

    console.groupCollapsed('[Project Status] Diagnostics');
    console.log('last commit timestamp:', latestTimestamp);
    console.log('computed status:', computedStatus);
    console.log('computed streak value:', streakDays);
    console.log('API response raw data:', payload);
    console.groupEnd();

    dom.commits.textContent = '';
    for (let i = 0; i < 3; i += 1) {
      const commit = commits[i];
      if (!commit) continue;
      dom.commits.appendChild(createProjectStatusCommitCard(commit, i));
    }
  } catch {
    resetProjectStatusToLive(dom);
    setProjectStatusStreakState(dom, 'unavailable');
    renderProjectStatusSkeleton(dom);
    console.groupCollapsed('[Project Status] Diagnostics');
    console.log('last commit timestamp:', null);
    console.log('computed status:', 'Live');
    console.log('computed streak value:', 0);
    console.log('API response raw data:', null);
    console.groupEnd();
  }
}

function startProjectStatus() {
  const dom = getProjectStatusDom();
  if (!dom) return;
  resetProjectStatusToLive(dom);
  renderProjectStatusSkeleton(dom);
  if (!LIVE_GITHUB_ENABLED) {
    dom.commits.textContent = '';
    setLocalizedCopy(dom.sub, 'Live preview mode', '本地预览模式');
    return;
  }
  loadProjectStatus();
  window.setInterval(() => loadProjectStatus(), PROJECT_STATUS_REFRESH_MS);
}

startContributorRibbon();
loadFooterHeartbeat();
if (LIVE_GITHUB_ENABLED) {
  window.setInterval(loadFooterHeartbeat, FOOTER_REFRESH_MS);
}
startProjectStatus();

const sponsorImg = document.querySelector('.sponsor-link img');
if (sponsorImg) {
  sponsorImg.addEventListener('error', () => {
    console.error('Sponsor logo failed:', sponsorImg.src);
    sponsorImg.alt = 'Sponsor logo unavailable';
  });
}
