# Mwifi project instructions

- Discuss unclear requirements with the user before modifying code.
- Use semantic versions in `MAJOR.MINOR.PATCH` format.
- Before finalizing any user-visible bug fix or small UI change, increment the `PATCH` version (for example, `1.5.0` to `1.5.1`) and complete the normal release-version updates without waiting for a separate request.
- Never reuse an existing released version number or Git tag for a newly rebuilt distributable.
- For every release, update `CFBundleShortVersionString` in `Resources/Info.plist`.
- Increment `CFBundleVersion` for every release build.
- Keep the current version shown in `README.md` synchronized with `Resources/Info.plist`.
- Release builds must be named `dist/Mwifi-<version>.app`; do not create ZIP packages.
- Keep `dist/`, build caches, credentials, logs, and user databases out of Git. Publish the DMG and SHA-256 file as GitHub Release assets.
- Use `scripts/package-release.sh` to package the verified app as `dist/Mwifi-<version>-arm64.dmg`. Never overwrite a published release asset.
- Scan source, commit metadata, and packaged files for local paths, private email addresses, credentials, and real network names before public publication. Use synthetic test fixtures and a GitHub noreply commit email.
- Create an annotated Git tag named `v<version>` only after tests, build, and code-signature verification pass.
- Document user-visible changes in `README.md` before releasing.
- Treat `traffic.sqlite` as user data. Any schema change must use a non-destructive migration and include migration tests.
