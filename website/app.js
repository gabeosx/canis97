const releaseLinks = document.querySelectorAll("[data-release-link]");
const downloadLabels = document.querySelectorAll("[data-download-label]");
const releaseNav = document.querySelector("[data-release-nav]");
const releaseStatuses = document.querySelectorAll("[data-release-status]");

const releasesPage = "https://github.com/gabeosx/canis97/releases";
const latestReleaseApi = "https://api.github.com/repos/gabeosx/canis97/releases/latest";

async function pointToLatestDownload() {
  try {
    const response = await fetch(latestReleaseApi, {
      headers: { Accept: "application/vnd.github+json" },
    });

    if (response.status === 404) {
      downloadLabels.forEach((label) => {
        label.textContent = "First release coming soon";
      });
      if (releaseNav) releaseNav.textContent = "Coming soon";
      releaseStatuses.forEach((status) => {
        status.textContent = "The first signed release is on the way / macOS 26 or later / Apple silicon";
      });
      return;
    }

    if (!response.ok) return;

    const release = await response.json();
    const diskImage = release.assets?.find((asset) =>
      /^Canis97-\d+\.\d+\.\d+-arm64\.dmg$/.test(asset.name),
    );

    if (!diskImage?.browser_download_url) return;

    releaseLinks.forEach((link) => {
      link.href = diskImage.browser_download_url;
    });

    downloadLabels.forEach((label) => {
      label.textContent = `Download ${release.tag_name ?? "Canis97"}`;
    });

    releaseStatuses.forEach((status) => {
      status.textContent = "Free and open source / macOS 26 or later / Apple silicon";
    });
  } catch {
    releaseLinks.forEach((link) => {
      link.href = releasesPage;
    });
  }
}

document.querySelectorAll("[data-year]").forEach((year) => {
  year.textContent = String(new Date().getFullYear());
});

pointToLatestDownload();
