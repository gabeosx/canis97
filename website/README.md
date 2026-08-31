# Canis97 landing page

This is a dependency-free static site for `canis97.com`. It is deliberately isolated from the macOS app and the animated-skins release work.

## Local preview

From the repository root:

```sh
python3 -m http.server 4173 --directory website
```

Then open <http://localhost:4173>.

## Cloudflare Pages

Create a Pages project connected to `gabeosx/canis97` with:

- Production branch: `main`
- Framework preset: `None`
- Build command: leave blank
- Build output directory: `website`
- Root directory: repository root

Add `canis97.com` as the primary custom domain. Add `www.canis97.com` separately and redirect it to the apex domain in Cloudflare.

The download buttons ask GitHub for the latest public release and link directly to the signed and notarized `Canis97-VERSION-arm64.dmg`. Before the first release, they automatically say that it is coming soon; if GitHub is temporarily unavailable, they fall back to the releases page.
