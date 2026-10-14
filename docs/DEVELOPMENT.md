# For developers

How to build, sign and release Yaseen Screenshot. The guide for users is [here](GUIDE.md).

## Build

You need Xcode. The package has no outside dependency.

- `swift build`: build the app for development.
- `swift test`: run the unit tests. They open no window and need no permission.
- `scripts/bundle.sh`: make `build/Yaseen Screenshot.app` from a release build and sign it.
- `scripts/bundle.sh --dmg`: also make `build/Yaseen-Screenshot-<version>-arm64.dmg`.
- `scripts/install.sh`: put the app from `build/` in `/Applications` and open it. It quits the app that runs first. Run `scripts/bundle.sh` before it.
- `swift scripts/make-icon.swift`: draw the app icon again into `Support/AppIcon.icns`. Run it only after a change to the drawing.

The version is in one place: `CFBundleShortVersionString` in `Support/Info.plist`.

The app writes one log line for each capture, with the time from the hotkey to the frozen screens. Read the lines with the full path of the tool (in some shells, `log` is a different command):

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.yaseenarshad.yaseenscreenshot"'
```

## The signature

macOS ties the Screen Recording permission to the signature of the app. With a fixed certificate, the permission stays after an update. With an ad-hoc signature, each new build needs the permission again.

`scripts/bundle.sh` signs with the certificate "Yaseen Local Signing". Set `SIGN_IDENTITY` to use a different name. If the keychain does not have the certificate, the script signs ad-hoc and prints this:

```
WARNING: ad-hoc signature. macOS will not keep the Screen Recording permission after the next build.
```

### Make the certificate (one time)

Run this command on the Mac that builds the app:

```bash
scripts/make-signing-cert.sh
```

It makes a self-signed certificate "Yaseen Local Signing" in your login keychain. The certificate is free and is valid for 10 years. If the keychain has the certificate already, the script does nothing.

The other way is Keychain Access: in the menu, select Keychain Access, Certificate Assistant, Create a Certificate. Name: `Yaseen Local Signing`. Identity Type: Self-Signed Root. Certificate Type: Code Signing. Click Create.

Then check the result:

1. Check that the keychain has the certificate:

   ```bash
   security find-identity -p codesigning
   ```

   The list must show `"Yaseen Local Signing"`. The text `CSSMERR_TP_NOT_TRUSTED` next to it is normal for a self-signed certificate.
2. Run `scripts/bundle.sh`. If macOS asks if `codesign` can use the key, enter your login password and click "Always Allow".
3. Check the signature:

   ```bash
   codesign -d -r- "build/Yaseen Screenshot.app"
   ```

   The output must name a certificate (`certificate leaf = H"…"`). It must not show `cdhash`.

Keep this certificate. A new certificate is a new signature, and macOS asks for the permission again.

### Give the certificate to GitHub (one time)

The release workflow signs with the same certificate. It reads two repository secrets.

1. Select a password for the `.p12` file. Then export the certificate and its private key:

   ```bash
   security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P 'YOUR-P12-PASSWORD' -o ~/yaseen-local-signing.p12
   ```

   This command exports all the identities in the login keychain. If the keychain has other identities, use Keychain Access instead: select "Yaseen Local Signing" in "My Certificates", then File, Export Items, format "Personal Information Exchange (.p12)".
2. Add the two secrets with the GitHub CLI. Run these commands in the repository folder:

   ```bash
   base64 -i ~/yaseen-local-signing.p12 | gh secret set SIGN_CERT_P12_BASE64
   gh secret set SIGN_CERT_PASSWORD
   ```

   The second command asks for the value. Paste the password of the `.p12` file.
3. Delete the file:

   ```bash
   rm ~/yaseen-local-signing.p12
   ```

Without the two secrets, the release workflow signs ad-hoc and writes a warning in its log.

## Releases

- No release is cut automatically.
- Set the new version in `Support/Info.plist` (`CFBundleShortVersionString`) and merge it into `main`.
- Tag that commit `vX.Y.Z` and push the tag. `.github/workflows/release.yml` builds the `.dmg` and attaches it to the GitHub release of that tag. It makes the release if it does not exist.
- The workflow fails if the tag is not the version in `Support/Info.plist`.
- `.github/workflows/ci.yml` runs `swift build` and `swift test` on each pull request.
