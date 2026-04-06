# Notifikations — Project Context

## Repo
GitHub repo: `buzagloidan/notifikations`

## Structure
- `ios/` — iOS app (Swift/SwiftUI, XcodeGen via `project.yml`)
- `website/` — Static marketing/docs site (HTML/CSS)
- `worker/` — Cloudflare Worker (TypeScript) serving `api.notifikations.com`

## Commit & Push Protocol
After every meaningful session or completed feature:
1. Stage relevant files (avoid secrets, `node_modules`, build artifacts)
2. Commit with a concise message describing *what changed and why*
3. Push to `main` on `origin`
4. Use the format:
   ```
   git commit -m "$(cat <<'EOF'
   <short summary>

   Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
   EOF
   )"
   ```

## Secrets (never commit)
Cloudflare Worker secrets are set via `wrangler secret put`. See comments in `worker/wrangler.toml`.

## Deploy
- Worker: `cd worker && npx wrangler deploy`
- iOS: archive via Xcode or `xcodebuild`
