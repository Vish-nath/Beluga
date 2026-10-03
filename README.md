# Beluga Health

**AI-Powered Health Monitoring & Patient Database Management System**.

Beluga Health is a health-record prototype with an Android APK, web client, FastAPI server, and SQLite database. Accounts use email and password. The administrator can view all account health records; ordinary accounts are restricted to their own records.

[View Android releases](https://github.com/Vish-nath/Beluga/releases)

No APK release is published yet. Download the APK from that page after a tagged Android release has been built successfully.

**Do not expose this prototype to public users or enter real health data yet.** It still needs a production security review and controls such as verified account recovery, abuse protection, encrypted backups, and operational monitoring.

---

## Key Features

- **Laptop server and database**:
  - FastAPI serves the clients and API; SQLite persists data in `data/healthbot.sqlite3`.
  - Local network testing is supported. Public internet access requires a stable HTTPS endpoint and a security review first.
- **Account access**:
  - Users create accounts or sign in with email and password.
  - Server-side ownership checks keep ordinary users within their own records.
  - The admin account can read all users' profiles, health logs, reminders, and patient records. Admin record views are logged.
- **Patient Database Management**:
  - Add patients with custom or auto-generated clinical IDs (`PAT-1001`, `PAT-1002`, ...).
  - Modify patient demographics, contact details, emergency contacts, chronic conditions, allergies, and current medications at any time.
  - Real-time search by patient name, ID, phone number, or condition.
- **Medical History & Checkup Tracking (For Future Reference)**:
  - Log past and ongoing patient visits: Chief complaint, clinical diagnosis, vitals (systolic/diastolic blood pressure, fasting blood glucose, heart rate, temperature, body weight), prescriptions, doctor's notes, and follow-up dates.
  - Chronological visit timeline for reviewing patient trends over time.
- **Android APK with Dynamic Server Switching**:
  - Install the APK on any Android phone.
  - Built-in **Server Settings** modal allows switching the API address and testing connectivity.

---

## 1. Run the Laptop Server

For same-Wi-Fi testing, use the default launcher from PowerShell in the project root:

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -r requirements.txt
py scripts/start_server.py
```

For remote access through an HTTPS tunnel, start the API bound to localhost instead:

```powershell
py scripts/start_server.py --host 127.0.0.1
```

The database is created at `data/healthbot.sqlite3`. Keep the server running and prevent the laptop from sleeping while users need access. The laptop must stay powered on and connected to the internet.

---

## 2. Connect Mobile APK to Your PC Server

### Same Wi-Fi

1. Connect the phone and laptop to the same private Wi-Fi network.
2. Run `ipconfig` on Windows and find the laptop's IPv4 address.
3. In the APK's server settings, enter:

   ```text
   http://192.168.X.X:8000/api
   ```

4. Test the connection. If Windows Firewall prompts, allow Python on private networks only.

### Public Access

Use Cloudflare Tunnel to give the laptop API an HTTPS address without opening router ports. Install `cloudflared` on the laptop. Keep the API running with `py scripts/start_server.py --host 127.0.0.1`, then test with a temporary tunnel in a second PowerShell window:

```powershell
cloudflared tunnel --url http://127.0.0.1:8000
```

Cloudflare prints a temporary `https://...trycloudflare.com` URL. Enter that URL with `/api` in the APK's **Server Settings**. Temporary URLs change and are for testing only; don't use them for a published APK.

For a stable address, use a domain managed by Cloudflare and create a named tunnel:

```powershell
cloudflared tunnel login
cloudflared tunnel create beluga-health
cloudflared tunnel route dns beluga-health api.yourdomain.com
```

Create `%USERPROFILE%\.cloudflared\config.yml` using the tunnel UUID and credentials file created by the previous commands:

```yaml
tunnel: YOUR-TUNNEL-UUID
credentials-file: C:\Users\YOUR-WINDOWS-USER\.cloudflared\YOUR-TUNNEL-UUID.json
ingress:
  - hostname: api.yourdomain.com
    service: http://127.0.0.1:8000
  - service: http_status:404
```

With the API running, start the named tunnel:

```powershell
cloudflared tunnel run beluga-health
```

Set the APK server address to `https://api.yourdomain.com/api`. Set the GitHub Actions `API_BASE_URL` variable to the same value before building a release. The server and tunnel both need to stay running. Do not configure router port forwarding for port 8000.

**This makes the prototype reachable from anywhere; it does not make it production-safe.** Use synthetic/test data only until the app has an independent security review, abuse protection, account recovery, secure backups, and an always-on hosting plan. The administrator can view all users' health records. Do not collect real health information from public users yet.

---

## 3. Account Creation and Admin Setup

Create your account in the app with an email address and password. To make your account the sole administrator, run this from the project root on the laptop after registering:

```powershell
py scripts/set_admin.py your-email@example.com
```

The script demotes any previous admin. Sign out and back in to refresh the admin view. Admins can read all users' health records, so grant this role only to a trusted account. Ordinary signup cannot grant admin access.

---

## 4. Managing Patients in the Database

1. **Add Patient**:
   - Tap **Add Patient** on the Patients tab.
   - Enter Full Name, Age, Gender, Blood Group, Phone, Chronic Conditions (e.g., `Hypertension, Type 2 Diabetes`), Allergies (e.g., `Penicillin`), and Medications.
   - The database automatically assigns an identifier (`PAT-1001`) if left blank.
2. **Modify Patient Data**:
   - Tap any patient card to open their complete file.
   - Tap **Modify Patient Data** at the top right to edit any demographic or clinical fields. Changes are immediately saved to the database.
3. **Medical Checkup & Future Reference Records**:
   - Under the patient's record, tap **Add Record**.
   - Input the visit date, symptoms/complaints, diagnosis, vitals (Blood pressure, Fasting blood sugar, Heart rate, Temperature, Weight), prescribed medications, and follow-up appointment date.
   - All past checkups are displayed in chronological order for future clinical review.

---

## 5. Build or Publish the Android APK

### Building locally with Flutter

```powershell
cd mobile
py bootstrap.py
flutter build apk --release --dart-define=API_BASE_URL=http://YOUR-PC-IP:8000/api
```

The compiled APK will be located at:
`mobile/build/app/outputs/flutter-apk/app-release.apk`

### Automated Build via GitHub Actions

Before building a release, configure repository settings under **Settings > Secrets and variables > Actions**:

- Set the `API_BASE_URL` variable to your stable HTTPS API URL ending in `/api`.
- Set the `ANDROID_DEBUG_KEYSTORE_BASE64` secret to a persistent Android signing keystore encoded as base64. Keep the keystore private and never commit it.

Push a version tag to trigger the GitHub Actions workflow:

```sh
git tag v1.1.0
git push origin v1.1.0
```

GitHub Actions will compile the Android APK and attach it to the Releases section for download.
