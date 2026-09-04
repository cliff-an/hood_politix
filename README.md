# hood_politix

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android Release-Signing

Release-Builds werden mit dem Upload-Keystore signiert. Dafür lokal (nicht
committen!) `android/key.properties` anlegen:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:\\Users\\<name>\\upload-keystore.jks
```

Fehlt die Datei, fällt der Release-Build automatisch auf den Debug-Keystore
zurück (baubar, aber nicht Play-Store-fähig) — siehe `android/app/build.gradle.kts`.
