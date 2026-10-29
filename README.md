# Muse

A digital closet and outfit app for Android, built with Flutter.

- Closet: take or pick a photo of a clothing item, name it, tag it, save it
- Outfits: generate a random outfit from your closet
- Items are saved on the phone

## Get an Android app (APK) from GitHub, no installs needed

1. Upload all these files to a new GitHub repository (keep the folder structure).
2. Open the **Actions** tab and run **Build Android APK** (it also runs on every push).
3. When it finishes (a few minutes), open the run and download **muse-apk** from "Artifacts".
4. Unzip it, copy `app-release.apk` to your Android phone, and open it. You may need to allow "install unknown apps".

> If the `.github` folder did not upload, click **Add file > Create new file** on GitHub,
> type `.github/workflows/build.yml` as the name, and paste in the contents of that file.

## Run it on your computer

```
flutter create --project-name muse --platforms=android .
flutter pub get
flutter run
```

(`flutter create .` only adds the missing `android/` folder. Make sure `lib/main.dart` and `pubspec.yaml` are still the Muse versions afterwards.)

## Next steps

- Weather-based outfits
- AI tagging and background removal (needs a backend so the API key stays secret)
- Avatar and shopping suggestions
