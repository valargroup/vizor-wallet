# macOS fastlane

GitHub Actions 기준 macOS 외부 배포용 fastlane 설정입니다.

실행:

```bash
bundle exec fastlane mac build
bundle exec fastlane mac package
bundle exec fastlane mac release
```

`release` lane 순서:

1. Developer ID 인증서 import
2. `fvm flutter build macos --release`
3. `.app` notarize + staple
4. `.zip` / `.dmg` 생성
5. `.dmg` notarize + staple
6. GitHub Release asset 업로드

## Required environment variables

`release` lane은 아래 값이 없으면 해당 단계에서 바로 실패합니다.

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_JSON`
- `GITHUB_TOKEN`
- `GITHUB_REPOSITORY`
- `GITHUB_SHA`

태그 기반 워크플로우가 아니면 아래도 필요합니다.

- `RELEASE_TAG`

## Optional environment variables

- `MACOS_KEYCHAIN_NAME`
- `RELEASE_NAME`
- `GITHUB_RELEASE_DRAFT`
- `GITHUB_RELEASE_PRERELEASE`

## Notes

- `APP_STORE_CONNECT_API_KEY_JSON`은 fastlane `notarize` 액션이 읽을 수 있는 App Store Connect API key JSON 전체 문자열을 기대합니다.
- 인증서 import와 keychain 설정은 fastlane이 처리하지만, `Developer ID Application` 인증서 자체는 GitHub Actions secret로 제공돼야 합니다.
- 산출물은 `/Users/junghwanyun/zcash-wallet/dist/macos` 아래에 생성됩니다.
