# Beluga Health

**AI-Powered Health Monitoring and Wellness Bot**.

An Android and macOS health tracking prototype with a Flutter client, Python API, and SQLite database stored on the server. The Flutter app is a native Android app and macOS desktop app; both connect to the same API and account database.

[Download the latest Android APK](https://github.com/Vish-nath/Beluga/releases/latest/download/app-release.apk) from GitHub Releases. Android may ask you to allow installs from your browser or file manager.

## What works

- Create an account, sign in, and save a personal profile.
- Use one Flutter client on Android and macOS, with its access token kept in platform secure storage.
- Record steps, active minutes, sleep, fasting glucose, and blood pressure.
- View recent measurements and cautious reference notes. These are not diagnoses.
- Create reminders and mark them complete for the day.
- Import the supplied CSV as aggregate statistics only. Individual dataset rows are not copied into the app database.

The provided dataset contains 500 rows and labels for diabetes and hypertension. It does not include location, medication, drug interactions, steps, or sleep, so those synopsis goals are not inferred from this dataset. Its labels are shown only as sample counts, not as a representative prevalence estimate or a prediction model.

## Build the Android and macOS clients

Install Flutter, then open a terminal in the `mobile` folder and run:

```powershell
py bootstrap.py
```

The bootstrap generates Flutter's Android and macOS runner projects while preserving the app source. On Windows, install Android Studio and its Android SDK, then connect the API address when running or building:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-API-HOST/api
```

The APK is written to `mobile/build/app/outputs/flutter-apk/app-release.apk`. `10.0.2.2` is the Android emulator's address for the Windows host; for a physical phone, use a reachable HTTPS API address. The debug runner permits HTTP for local development. Release builds should use HTTPS.

### Publish an Android APK

The GitHub Actions workflow builds and attaches an APK whenever you push a version tag such as `v1.0.0`. Before the first release, configure these repository settings under **Settings > Secrets and variables > Actions**.

Set the `API_BASE_URL` Actions variable to your deployed HTTPS API URL, including `/api` (for example, `https://api.example.com/api`). The local laptop server is not suitable for public installs.

Set the `ANDROID_DEBUG_KEYSTORE_BASE64` Actions secret to a base64-encoded Android keystore. Generate it once and keep it private; reusing the same key lets users install future APK updates over the existing app. In PowerShell, run:

```powershell
keytool -genkeypair -v -keystore beluga-release.jks -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Beluga Health"
[Convert]::ToBase64String([IO.File]::ReadAllBytes("beluga-release.jks"))
```

Save the command's output as the `ANDROID_DEBUG_KEYSTORE_BASE64` secret. Do not commit the keystore or its encoded contents.

Push a version tag to create the release and APK:

```sh
git tag v1.0.0
git push origin v1.0.0
```

This prototype is not a production health service. Do not use real health information; the API and database need a security review before public deployment.

To build the macOS desktop app, run the same bootstrap on a Mac with Flutter and Xcode installed, then:

```sh
flutter run -d macos --dart-define=API_BASE_URL=https://YOUR-API-HOST/api
flutter build macos --release --dart-define=API_BASE_URL=https://YOUR-API-HOST/api
```

The macOS app is written under `mobile/build/macos/Build/Products/Release/`. macOS builds cannot be produced on Windows; use a Mac with Xcode. Android APK builds cannot be produced by Xcode.

## Run the API server

Install Python 3.10 or newer, then in the project folder run:

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -r requirements.txt
py -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The Android emulator can reach the laptop API at `http://10.0.2.2:8000/api`. For a physical device on the same private Wi-Fi, use the laptop's local IP in `API_BASE_URL` and allow Python through Windows Firewall if prompted. macOS can use `http://127.0.0.1:8000/api` when the API runs on the same Mac. For users to access accounts when your laptop is off, deploy the API and database to cloud hosting and use its HTTPS URL in the build command. Do not expose this prototype directly to the public internet.

The database is created at `data/healthbot.sqlite3`. Set `HEALTHBOT_DB` to change its location. Back up that file securely; it contains personal health information.

## Import the supplied dataset summary

Copy the CSV to the laptop, then run this from the project folder:

```powershell
py scripts/import_dataset.py "C:\path\to\patient_health_dataset.csv"
```

The importer validates the expected columns and stores the total row count, label counts, and average age/BMI. It does not retain patient IDs or individual records.

## Prototype limits

This is an educational prototype, not a medical device or production service. It has no TLS, encrypted database, account recovery, clinician review, verified medication interaction source, location prevalence feed, or reliable background Android notifications. Reminders are stored and visible in the app; notification delivery while the app is closed is not implemented. Do not enter real patient data or use health notes to change treatment. Use a clinician for diagnosis, medication, diet, and activity decisions.









