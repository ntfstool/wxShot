# Mac App Store submission (what is ready, what needs the account owner)

Ready in the repo: `scripts/build.sh --mas` (compile flag `MAS`: sandbox entitlements in `scripts/mas.entitlements`, no self-update, chat-app names neutralised in the UI, only needs Screen Recording).

Needs the Apple account owner (cannot be done from code):
1. New "3rd Party Mac Developer Application" and "Mac Installer Distribution" certificates. The ones in the keychain expired.
2. App Store Connect record: bundle id `com.ntfstool.wxshot`, SKU `wxshot`, category Utilities, price free.
3. A Mac App Store provisioning profile for the bundle id, embedded as `Contents/embedded.provisionprofile`.
4. Build with `scripts/build.sh --mas --sign "<3rd Party Mac Developer Application identity>"`, package with `productbuild --component dist/mas/wxShot.app /Applications --sign "<installer identity>" wxShot.pkg`, upload with Transporter or `xcrun altool`.

Listing text (does NOT mention WeChat; the in-app UI also says "Chat app" in the MAS build):
- Name: wxShot. Subtitle: Fast screenshots, long capture, OCR.
- Description: A tiny native screenshot tool that stays in the background. Press ⌥A, drag to select, annotate with shapes, arrows, mosaic, text and numbers, then press Return or double-click to copy. Capture long scrolling pages, extract text offline with Apple Vision, and pin images on top of other windows. No account, no upload, free.
- Keywords: screenshot,capture,OCR,long screenshot,annotate,pin,screen,clip
- Privacy: collects anonymous usage data (install id, version, OS, language), not linked to identity, not used for tracking. Privacy policy URL: https://ntfstool.com/wxshot/faq/
- Review note: the app needs Screen Recording permission to capture the user's selected area; it never records video.
