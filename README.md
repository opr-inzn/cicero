# Point

**[Download the latest version](https://github.com/opr-inzn/point/releases/latest/download/Point.dmg)** · [All versions and release notes](https://github.com/opr-inzn/point/releases) · Requires macOS 26 on Apple silicon.

A font manager for macOS 26. Browse every font on your Mac and in your font folders, try them out, and turn them on only when you need them.

- **Customizable sidebar.** Click **Edit** next to Library and every sidebar item and group gets a checkbox; uncheck what you don't want and click **Done**. The same list lives in **Settings → Sidebar**, Finder-style. Right-click any row → *Hide from Sidebar* also works.
- **App-only folders.** A watched folder can be marked *Active in Adobe apps* (auto-detected for `…/Application Support/Adobe/Fonts`). Its fonts get an "Adobe" tag and stay out of Inactive; browse them through the folder's sidebar row. Set this per folder in **Settings → Fonts** or from the folder's right-click menu; other app names work too.
- **Reveal in Finder.** Right-click a font (or a selection), a style row in the detail view, or use ⇧⌘R. The inspector shows the file path with a Reveal button as well.
- **Folders group** in the sidebar, one row per watched folder, and a **System Fonts** item for the fonts that ship with macOS (which can also be kept out of All/Active).

Also: a grid/list browser with size, weight and color controls; a detail view with an editable preview, every style and a character grid; an Info/OpenType Features inspector; styles, collections (drag fonts onto them) and foundries; activation by copying to `~/Library/Fonts` or using the files where they are.

## Privacy

Point doesn't collect any data and never connects to the internet. Everything it knows about your fonts stays in local files on your Mac.

## Releasing

1. Add a `## 1.1` section to [CHANGELOG.md](CHANGELOG.md) describing the changes.
2. `./scripts/release.sh 1.1` sets the version, builds the app (Apple silicon only), signs it with your Developer ID, and notarizes and staples both the app and the DMG.
3. Commit and push, then `./scripts/publish.sh` creates the `v1.1` GitHub release with the changelog section as notes and the DMG attached as `Point.dmg`, so the README's download link always points at the newest version.

One-time setup:

1. **Developer ID certificate**: Xcode → Settings → Accounts → your team → Manage Certificates… → + → *Developer ID Application*.
2. **Notarization credentials**: create an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and Security → App-Specific Passwords), then run the following and paste the password when asked. It is stored in your keychain.

   ```sh
   xcrun notarytool store-credentials point-notary --apple-id <your Apple ID> --team-id <your team ID>
   ```
