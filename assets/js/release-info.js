const PRIMARY_RELEASE_METADATA_URL = 'assets/meta/sync-releases.json';
const LEGACY_RELEASE_METADATA_URL = 'assets/meta/releases.json';

const FALLBACK_RELEASES = Object.freeze({
  currentVersion: 'unknown',
  releasedAt: null,
  notes: 'Versiegegevens zijn momenteel niet beschikbaar.',
  latest5: [],
});

function normalizeVersionValue(value, fallback = 'unknown') {
  if (typeof value !== 'string') return fallback;
  const trimmed = value.trim();
  if (!trimmed) return fallback;
  return trimmed.toLowerCase() === 'onbekend' ? 'unknown' : trimmed;
}

function normalizeReleaseItem(item) {
  const version = normalizeVersionValue(item?.version);
  const releasedAt = typeof item?.releasedAt === 'string' && item.releasedAt.trim() ? item.releasedAt.trim() : null;
  const notes = typeof item?.notes === 'string' && item.notes.trim() ? item.notes.trim() : 'Geen release-opmerkingen.';
  return { version, releasedAt, notes };
}

function normalizeReleasePayload(payload) {
  const latest5 = Array.isArray(payload?.latest5)
    ? payload.latest5.map(normalizeReleaseItem).slice(0, 5)
    : [];

  const currentVersion = normalizeVersionValue(payload?.currentVersion, latest5[0]?.version || FALLBACK_RELEASES.currentVersion);

  const releasedAt = typeof payload?.releasedAt === 'string' && payload.releasedAt.trim()
    ? payload.releasedAt.trim()
    : (latest5[0]?.releasedAt || FALLBACK_RELEASES.releasedAt);

  const notes = typeof payload?.notes === 'string' && payload.notes.trim()
    ? payload.notes.trim()
    : (latest5[0]?.notes || FALLBACK_RELEASES.notes);

  return { currentVersion, releasedAt, notes, latest5 };
}

function formatReleaseDate(dateValue) {
  if (!dateValue) return 'Onbekende datum';
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return 'Onbekende datum';
  return date.toLocaleDateString('nl-BE', { year: 'numeric', month: 'long', day: 'numeric' });
}

async function fetchReleaseMetadata(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const payload = await response.json();
  return normalizeReleasePayload(payload);
}

export async function loadReleaseMetadata(url = PRIMARY_RELEASE_METADATA_URL) {
  const urls = url === PRIMARY_RELEASE_METADATA_URL
    ? [PRIMARY_RELEASE_METADATA_URL, LEGACY_RELEASE_METADATA_URL]
    : [url];

  for (const candidateUrl of urls) {
    try {
      return await fetchReleaseMetadata(candidateUrl);
    } catch {
      continue;
    }
  }

  return { ...FALLBACK_RELEASES };
}

export function renderReleaseInfo(metadata, elements = {}) {
  const data = normalizeReleasePayload(metadata || FALLBACK_RELEASES);

  if (elements.versionText) {
    elements.versionText.textContent = data.currentVersion === 'unknown'
      ? 'Versie onbekend'
      : `Versie: ${data.currentVersion}`;
  }

  if (elements.currentVersionText) {
    elements.currentVersionText.textContent = data.currentVersion;
  }

  if (elements.currentReleasedAtText) {
    elements.currentReleasedAtText.textContent = formatReleaseDate(data.releasedAt);
  }

  if (elements.currentNotesText) {
    elements.currentNotesText.textContent = data.notes;
  }

  if (elements.latestList) {
    elements.latestList.innerHTML = '';

    if (!data.latest5.length) {
      const empty = document.createElement('div');
      empty.className = 'muted';
      empty.textContent = 'Nog geen release-overzicht beschikbaar.';
      elements.latestList.appendChild(empty);
    } else {
      data.latest5.forEach((item) => {
        const row = document.createElement('div');
        row.className = 'item';

        const title = document.createElement('div');
        const version = document.createElement('strong');
        version.textContent = item.version;
        const date = document.createElement('span');
        date.className = 'muted';
        date.style.marginLeft = '8px';
        date.textContent = formatReleaseDate(item.releasedAt);
        title.append(version, date);

        const notes = document.createElement('p');
        notes.className = 'muted';
        notes.style.whiteSpace = 'pre-wrap';
        notes.style.margin = '8px 0 0';
        notes.textContent = item.notes;

        row.append(title, notes);
        elements.latestList.appendChild(row);
      });
    }
  }

  return data;
}
