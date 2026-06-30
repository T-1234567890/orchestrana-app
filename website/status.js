const STATUS_LABELS = {
  operational: 'Operational',
  limited: 'Limited',
  outage: 'Outage'
};

const BANNER_LABELS = {
  operational: 'All services are operational',
  limited: 'Some features are limited',
  outage: 'Service disruption'
};

const BANNER_ICONS = {
  operational: '✓',
  limited: '!',
  outage: '!'
};

const STATUS_ORDER = {
  operational: 0,
  limited: 1,
  outage: 2
};

const SEPARATOR_PATTERN = /^\s*-{40,}\s*$/m;
const OPENROUTER_RSS_URL = 'https://status.openrouter.ai/incidents.rss';
const OPENROUTER_PROXY_URL = `https://api.allorigins.win/get?url=${encodeURIComponent(OPENROUTER_RSS_URL)}`;
const XAI_RSS_URL = 'https://status.x.ai/feed.xml';
const GOOGLE_CLOUD_INCIDENTS_URL = 'https://status.cloud.google.com/incidents.json';
const FIREBASE_INCIDENTS_URL = 'https://status.firebase.google.com/incidents.json';

const SERVICE_DEFINITIONS = [
  {
    title: 'App',
    services: ['Local Mac app']
  },
  {
    title: 'Website',
    services: ['Website']
  },
  {
    title: 'Account',
    services: ['Sign-in', 'Subscription access']
  },
  {
    title: 'Cloud',
    services: ['Cloud functionality', 'Networking']
  },
  {
    title: 'AI',
    wide: true,
    services: ['AI features', 'Advanced AI features']
  }
];

const SERVICE_ALIASES = new Map([
  ['app', ['Local Mac app']],
  ['core app', ['Local Mac app']],
  ['local mac app', ['Local Mac app']],
  ['website', ['Website']],
  ['sign-in', ['Sign-in']],
  ['signin', ['Sign-in']],
  ['auth', ['Sign-in']],
  ['account', ['Sign-in']],
  ['subscription', ['Subscription access']],
  ['subscription access', ['Subscription access']],
  ['billing', ['Subscription access']],
  ['purchase', ['Subscription access']],
  ['cloud', ['Cloud functionality']],
  ['cloud functionality', ['Cloud functionality']],
  ['backend', ['Cloud functionality']],
  ['cloud backend', ['Cloud functionality']],
  ['networking', ['Networking']],
  ['network', ['Networking']],
  ['cloud networking', ['Networking']],
  ['regional networking', ['Networking']],
  ['ai', ['AI features', 'Advanced AI features']],
  ['ai features', ['AI features']],
  ['advanced ai', ['Advanced AI features']],
  ['advanced ai features', ['Advanced AI features']]
]);

const CLOUD_FUNCTIONALITY_PATTERNS = [
  'firebase',
  'identity platform',
  'firestore',
  'cloud firestore',
  'cloud functions',
  'cloud run',
  'cloud storage',
  'firebase hosting',
  'google cloud apis',
  'cloud apis'
];

const NETWORKING_PATTERNS = [
  'virtual private cloud',
  'vpc',
  'hybrid connectivity',
  'load balancing',
  'media cdn',
  'global networking',
  'google cloud networking',
  'packet loss',
  'elevated latency',
  'routing'
];

const REGIONAL_ADVISORY_PATTERNS = [
  'regional',
  'certain regions',
  'specific locations',
  'some users',
  'small group of customers',
  'intermittent',
  'elevated latency',
  'packet loss',
  'routing',
  'connectivity',
  'delhi',
  'chennai',
  'mumbai',
  'asia-south2'
];

const SIGN_IN_PATTERNS = [
  'firebase authentication',
  'identity platform',
  'oauth',
  'sign-in',
  'signin',
  'authentication'
];

const PRIMARY_SERVICES = new Set([
  'Local Mac app',
  'Website',
  'Sign-in',
  'Subscription access',
  'Cloud functionality',
  'AI features',
  'Advanced AI features'
]);

const NON_APP_WEBSITE_CORE_SERVICES = [
  'Sign-in',
  'Subscription access',
  'Cloud functionality',
  'AI features',
  'Advanced AI features'
];

const elements = {
  overallBanner: document.getElementById('overall-banner'),
  overallText: document.getElementById('overall-text'),
  heroUpdated: document.getElementById('hero-updated'),
  advisoryBanner: document.getElementById('advisory-banner'),
  statusMessage: document.getElementById('status-message'),
  noticesSection: document.getElementById('current-notices-section'),
  noticesList: document.getElementById('notices-list'),
  dailyStatus: document.getElementById('daily-status')
};

const appState = {
  manualOverrides: [],
  incidents: [],
  noIncidentBlock: null,
  hiddenStatuses: new Map(),
  advisories: [],
  statusLoadFailed: false,
  lastChecked: null
};

function escapeHTML(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[char]));
}

function normalizeText(value) {
  return String(value || '').trim().toLowerCase();
}

function stripQuotes(value) {
  const trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function formatCheckedTime(date = new Date()) {
  return date.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  });
}

function normalizeState(value) {
  const normalized = normalizeText(value);
  if (normalized === 'outage') return 'outage';
  if (normalized === 'downgrade' || normalized === 'limited') return 'limited';
  return 'operational';
}

function worstStatus(statuses) {
  return statuses.reduce((current, status) => {
    const normalized = normalizeState(status);
    return STATUS_ORDER[normalized] > STATUS_ORDER[current] ? normalized : current;
  }, 'operational');
}

function parseStatusMarkdown(markdown) {
  const blocks = String(markdown || '')
    .split(SEPARATOR_PATTERN)
    .map((block) => block.trim())
    .filter(Boolean);

  return blocks.map((block) => {
    const record = {};
    block.split(/\r?\n/).forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const match = trimmed.match(/^([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*)$/);
      if (!match) return;
      const key = match[1];
      const rawValue = stripQuotes(match[2]);
      const parsedValue = rawValue === 'true' ? true : rawValue;
      if (key === 'update') {
        record.update = Array.isArray(record.update) ? record.update : [];
        record.update.push(parsedValue);
        return;
      }
      record[key] = parsedValue;
    });
    return record;
  }).filter((block) => Object.keys(block).length > 0);
}

function blockStatus(block) {
  return normalizeState(block.status ?? block.overall);
}

function classifyBlocks(blocks) {
  const manualOverrides = [];
  const incidents = [];
  let noIncidentBlock = null;

  blocks.forEach((block, index) => {
    if (block.noIncident === true) {
      noIncidentBlock = block;
      return;
    }

    const type = normalizeText(block.type);
    const hasService = Boolean(block.service);
    const hasName = Boolean(block.name);

    if (type === 'override' || (!type && hasService)) {
      manualOverrides.push({
        service: block.service || '',
        status: blockStatus(block),
        lastUpdated: block.lastUpdated || ''
      });
      return;
    }

    if (type === 'incident' || (!type && hasName)) {
      const updates = Array.isArray(block.update)
        ? block.update
        : block.update
          ? [block.update]
          : [];

      incidents.push({
        name: block.name || `Service notice ${index + 1}`,
        service: block.service || '',
        status: blockStatus(block),
        started: block.started || '',
        lastUpdated: block.lastUpdated || '',
        summary: block.summary || 'No summary provided.',
        updates: updates.filter(Boolean)
      });
    }
  });

  return { manualOverrides, incidents, noIncidentBlock };
}

function statePill(status) {
  const normalized = normalizeState(status);
  return `
    <span class="status-pill status-${normalized}">
      <span class="status-dot"></span>
      <span>${STATUS_LABELS[normalized]}</span>
    </span>
  `;
}

function mappedServicesFromAlias(value) {
  return SERVICE_ALIASES.get(normalizeText(value)) || [];
}

function mappedServicesFromIncident(incident) {
  if (incident.service) {
    return mappedServicesFromAlias(incident.service);
  }

  const text = normalizeText(incident.name);
  const matches = [];
  SERVICE_ALIASES.forEach((services, alias) => {
    if (text.includes(alias)) {
      services.forEach((service) => {
        if (!matches.includes(service)) matches.push(service);
      });
    }
  });
  return matches;
}

function visibleServiceStatuses() {
  const statuses = new Map();
  SERVICE_DEFINITIONS.flatMap((group) => group.services).forEach((service) => {
    statuses.set(service, ['operational']);
  });

  appState.manualOverrides.forEach((override) => {
    mappedServicesFromAlias(override.service).forEach((service) => {
      statuses.get(service)?.push(override.status);
    });
  });

  appState.incidents.forEach((incident) => {
    mappedServicesFromIncident(incident).forEach((service) => {
      statuses.get(service)?.push(incident.status);
    });
  });

  appState.hiddenStatuses.forEach((status, service) => {
    statuses.get(service)?.push(status);
  });

  return new Map(Array.from(statuses.entries()).map(([service, serviceStatuses]) => [
    service,
    worstStatus(serviceStatuses)
  ]));
}

function overallStatus() {
  const statuses = visibleServiceStatuses();
  const primaryStatus = Array.from(statuses.entries())
    .filter(([service]) => PRIMARY_SERVICES.has(service))
    .map(([, status]) => status);
  const incidentStatus = appState.incidents.map((incident) => incident.status);
  if (appState.statusLoadFailed) incidentStatus.push('limited');

  const manualIncidentOutage = appState.incidents.some((incident) => incident.status === 'outage');
  const appUnavailable = statuses.get('Local Mac app') === 'outage';
  const broadCoreOutage = NON_APP_WEBSITE_CORE_SERVICES.every((service) => statuses.get(service) === 'outage');

  if (manualIncidentOutage || appUnavailable || broadCoreOutage) {
    return 'outage';
  }

  const worstPrimary = worstStatus([...primaryStatus, ...incidentStatus]);
  return worstPrimary === 'outage' ? 'limited' : worstPrimary;
}

function updateHero() {
  const overall = overallStatus();
  elements.overallBanner.className = `overall-banner banner-${overall}`;
  elements.overallBanner.querySelector('.banner-icon').textContent = BANNER_ICONS[overall];
  elements.overallText.textContent = overall === 'operational' && hasAdvisoryImpact()
    ? 'All core services are operational'
    : BANNER_LABELS[overall];
  elements.heroUpdated.textContent = appState.lastChecked || 'Checking...';
}

function renderStatusMessage() {
  if (!appState.statusLoadFailed) {
    elements.statusMessage.hidden = true;
    elements.statusMessage.textContent = '';
    return;
  }
  elements.statusMessage.hidden = false;
  elements.statusMessage.textContent = 'Service status could not be loaded.';
}

function renderAdvisoryBanner() {
  if (!hasAdvisoryImpact() || overallStatus() !== 'operational') {
    elements.advisoryBanner.hidden = true;
    elements.advisoryBanner.textContent = '';
    return;
  }

  elements.advisoryBanner.hidden = false;
  elements.advisoryBanner.textContent = 'Some features may be slower or limited for users in certain regions.';
}

function parseTimelineUpdate(update) {
  const [timestamp, ...messageParts] = String(update || '').split('|');
  return {
    timestamp: timestamp.trim(),
    message: messageParts.join('|').trim() || timestamp.trim(),
    raw: String(update || '')
  };
}

function timelineSortValue(update) {
  const time = Date.parse(update.timestamp);
  return Number.isNaN(time) ? null : time;
}

function sortedTimelineUpdates(updates) {
  const parsed = updates.map(parseTimelineUpdate);
  const canSort = parsed.every((update) => timelineSortValue(update) !== null);
  if (!canSort) return parsed;
  return parsed.sort((a, b) => timelineSortValue(b) - timelineSortValue(a));
}

function renderTimeline(updates) {
  if (!updates || updates.length === 0) return '';

  return `
    <details class="notice-timeline">
      <summary class="notice-timeline-title">Updates</summary>
      <ul class="notice-timeline-list">
        ${sortedTimelineUpdates(updates).map((update) => `
          <li class="notice-update">
            <span class="notice-update-time">${escapeHTML(update.timestamp)}</span>
            <span class="notice-update-text">${escapeHTML(update.message)}</span>
          </li>
        `).join('')}
      </ul>
    </details>
  `;
}

function renderNotices() {
  if (appState.incidents.length === 0) {
    elements.noticesSection.hidden = true;
    elements.noticesList.innerHTML = '';
    return;
  }

  elements.noticesSection.hidden = false;
  elements.noticesList.innerHTML = appState.incidents.map((incident) => `
    <article class="notice-card">
      <div class="notice-card-head">
        <h3>${escapeHTML(incident.name)}</h3>
        ${statePill(incident.status)}
      </div>
      ${incident.started ? `<p class="notice-meta">Started: ${escapeHTML(incident.started)}</p>` : ''}
      <p class="notice-meta">Last updated: ${escapeHTML(incident.lastUpdated || 'Not specified')}</p>
      <p class="notice-summary">${escapeHTML(incident.summary)}</p>
      ${renderTimeline(incident.updates)}
    </article>
  `).join('');
}

function renderDailyStatus() {
  const statuses = visibleServiceStatuses();
  elements.dailyStatus.innerHTML = SERVICE_DEFINITIONS.map((group) => `
    <article class="service-group${group.wide ? ' service-group-wide' : ''}">
      <h3>${escapeHTML(group.title)}</h3>
      ${group.services.map((service) => `
        <div class="service-row">
          <span class="service-name">${escapeHTML(service)}</span>
          ${statePill(statuses.get(service) || 'operational')}
        </div>
      `).join('')}
    </article>
  `).join('');
}

function renderPage() {
  updateHero();
  renderAdvisoryBanner();
  renderStatusMessage();
  renderNotices();
  renderDailyStatus();
}

function htmlToPlainText(html) {
  const doc = new DOMParser().parseFromString(String(html || ''), 'text/html');
  return doc.body.textContent.replace(/\s+/g, ' ').trim();
}

function activeTextFromIncident(incident) {
  return JSON.stringify(incident || {}).toLowerCase();
}

function isResolvedText(text) {
  return /\b(resolved|completed|fixed|closed|postmortem|resolved_status)\b/.test(text);
}

function incidentSeverityFromText(text) {
  if (/\b(outage|unavailable|failure|failed|down|major)\b/.test(text)) {
    return 'outage';
  }
  if (/\b(degraded|disruption|elevated errors|errors|intermittent|packet loss|latency|slow|timeout|timeouts|minor)\b/.test(text)) {
    return 'limited';
  }
  return 'limited';
}

function incidentMentions(text, patterns) {
  return patterns.some((pattern) => text.includes(pattern));
}

function hasAdvisoryImpact() {
  const statuses = visibleServiceStatuses();
  return appState.advisories.length > 0 || statuses.get('Networking') !== 'operational';
}

function isRegionalAdvisoryText(text) {
  return incidentMentions(text, REGIONAL_ADVISORY_PATTERNS);
}

function addAdvisory(kind) {
  if (!appState.advisories.includes(kind)) {
    appState.advisories.push(kind);
  }
}

function setHiddenStatus(service, statuses) {
  appState.hiddenStatuses.set(service, worstStatus([
    appState.hiddenStatuses.get(service) || 'operational',
    ...statuses
  ]));
}

function fetchWithTimeout(url, options = {}, timeoutMs = 6000) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs);
  return fetch(url, {
    ...options,
    signal: controller.signal
  }).finally(() => window.clearTimeout(timeout));
}

function isActiveStatusIncident(incident) {
  const status = normalizeText(incident.status || incident.most_recent_update?.status || incident.state || incident.incident_state);
  if (/\b(resolved|closed|completed|fixed)\b/.test(status)) return false;
  if (incident.end || incident.end_time || incident.endTime || incident.resolved_time || incident.resolvedTime) return false;
  return true;
}

async function checkWebsiteHealth() {
  if (!['http:', 'https:'].includes(window.location.protocol)) return;

  async function checkURL(path) {
    const response = await fetchWithTimeout(path, { cache: 'no-store' });
    if (response.status >= 500) return 'outage';
    if (!response.ok) return 'limited';
    return 'operational';
  }

  try {
    const status = await checkURL('/');
    if (status !== 'operational') {
      setHiddenStatus('Website', [status]);
      renderPage();
    }
  } catch {
    if (!['localhost', '127.0.0.1', '::1'].includes(window.location.hostname)) {
      setHiddenStatus('Website', ['limited']);
      renderPage();
    }
  }
}

async function fetchJSON(url) {
  const response = await fetchWithTimeout(url, { cache: 'no-store' });
  if (!response.ok) return null;
  return response.json();
}

function incidentsFromJSON(data) {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.incidents)) return data.incidents;
  return [];
}

async function checkCloudStatus(url) {
  try {
    const data = await fetchJSON(url);
    const cloudFunctionalityStates = [];
    const networkingStates = [];
    const signInStates = [];

    incidentsFromJSON(data).filter(isActiveStatusIncident).forEach((incident) => {
      const text = activeTextFromIncident(incident);
      const severity = incidentSeverityFromText(text);
      const regionalAdvisory = isRegionalAdvisoryText(text);
      if (regionalAdvisory) {
        networkingStates.push(severity);
        addAdvisory('regional-networking');
        return;
      }
      if (incidentMentions(text, CLOUD_FUNCTIONALITY_PATTERNS)) {
        cloudFunctionalityStates.push(severity);
      }
      if (incidentMentions(text, NETWORKING_PATTERNS)) {
        networkingStates.push(severity);
      }
      if (incidentMentions(text, SIGN_IN_PATTERNS)) {
        signInStates.push(severity);
      }
    });

    if (cloudFunctionalityStates.length > 0) {
      setHiddenStatus('Cloud functionality', cloudFunctionalityStates);
    }

    if (networkingStates.length > 0) {
      setHiddenStatus('Networking', networkingStates);
    }

    if (signInStates.length > 0) {
      setHiddenStatus('Sign-in', signInStates);
    }

    if (
      cloudFunctionalityStates.length > 0 ||
      networkingStates.length > 0 ||
      signInStates.length > 0
    ) {
      renderPage();
    }
  } catch {
    // External status checks are silent.
  }
}

function isResolvedRSSItem(item) {
  const text = [
    item.querySelector('title')?.textContent,
    item.querySelector('description')?.textContent,
    item.querySelector('category')?.textContent
  ].join(' ').toLowerCase();
  return isResolvedText(text);
}

function rssItemSeverity(item) {
  const text = [
    item.querySelector('title')?.textContent || '',
    htmlToPlainText(item.querySelector('description')?.textContent || ''),
    item.querySelector('category')?.textContent || ''
  ].join(' ').toLowerCase();
  return incidentSeverityFromText(text);
}

async function fetchRSSXML(url) {
  const response = await fetchWithTimeout(url, { cache: 'no-store' });
  if (!response.ok) return null;
  return response.text();
}

async function checkRSSStatus(url, targetService, useProxy = false) {
  try {
    const xml = useProxy
      ? (await fetchJSON(OPENROUTER_PROXY_URL))?.contents
      : await fetchRSSXML(url);

    if (!xml) return;
    const rss = new DOMParser().parseFromString(xml, 'application/xml');
    if (rss.querySelector('parsererror')) return;

    const states = Array.from(rss.querySelectorAll('item'))
      .filter((item) => !isResolvedRSSItem(item))
      .map(rssItemSeverity);

    if (states.length === 0) return;
    setHiddenStatus(targetService, states);
    renderPage();
  } catch {
    // External status checks are silent.
  }
}

async function loadStatus() {
  try {
    const response = await fetchWithTimeout('status.md', { cache: 'no-store' });
    if (!response.ok) throw new Error('Status unavailable');
    const markdown = await response.text();
    const { manualOverrides, incidents, noIncidentBlock } = classifyBlocks(parseStatusMarkdown(markdown));
    appState.manualOverrides = manualOverrides;
    appState.incidents = incidents;
    appState.noIncidentBlock = noIncidentBlock;
    appState.statusLoadFailed = false;
  } catch {
    appState.manualOverrides = [];
    appState.incidents = [];
    appState.noIncidentBlock = null;
    appState.statusLoadFailed = true;
  }
  renderPage();
}

async function initializeStatusPage() {
  renderPage();
  await loadStatus();
  await Promise.allSettled([
    checkWebsiteHealth(),
    checkCloudStatus(GOOGLE_CLOUD_INCIDENTS_URL),
    checkCloudStatus(FIREBASE_INCIDENTS_URL),
    checkRSSStatus(OPENROUTER_RSS_URL, 'AI features', true),
    checkRSSStatus(XAI_RSS_URL, 'Advanced AI features')
  ]);
  appState.lastChecked = formatCheckedTime();
  renderPage();
}

initializeStatusPage();
