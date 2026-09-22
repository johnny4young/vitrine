export const latestReleasePage = 'https://github.com/johnny4young/vitrine/releases/latest';
const repository = '/johnny4young/vitrine';

function repositoryURL(value, path) {
  try {
    const url = new URL(value);
    return url.origin === 'https://github.com' && !url.username && !url.password
      && !url.search && !url.hash && url.pathname === path ? url.href : null;
  } catch {
    return null;
  }
}

// Never infer a downloadable version from source metadata or a draft release.
export function publishedDownload(release) {
  if (!release || release.draft !== false || release.prerelease !== false
    || typeof release.tag_name !== 'string' || !/^v\d+\.\d+\.\d+$/.test(release.tag_name)) return null;
  const tag = release.tag_name;
  const page = repositoryURL(release.html_url, `${repository}/releases/tag/${tag}`);
  if (!page) return null;
  const asset = Array.isArray(release.assets) ? release.assets.find((candidate) =>
    candidate?.name === `Vitrine-${tag.slice(1)}.dmg` && candidate.state === 'uploaded'
    && candidate.size > 0 && repositoryURL(candidate.browser_download_url,
      `${repository}/releases/download/${tag}/${candidate.name}`)) : null;
  return { version: tag, url: asset?.browser_download_url ?? page };
}

export async function fetchPublishedDownload() {
  const response = await fetch('https://api.github.com/repos/johnny4young/vitrine/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('Published release unavailable');
  const download = publishedDownload(await response.json());
  if (!download) throw new Error('Invalid published release');
  return download;
}
