# Beluga Health

**AI-Powered Health Monitoring & Patient Database Management System**.

Beluga Health turns your local PC into a dedicated **health database and API server** with companion **Android APK** and **Web** clients. Clinicians and users can register or sign in with their **Gmail ID & password** (or Google Sign-In), store patient records in the database, modify patient data whenever required, and track complete clinical checkups, vitals, and prescriptions for **future reference**.

---

## Key Features

- **Your PC as the Server & Database**:
  - Python FastAPI server running locally on your computer with a persistent SQLite database (`data/healthbot.sqlite3`).
  - Listen on `0.0.0.0:8000` to serve devices on your local Wi-Fi, or expose via secure tunnels (Cloudflare Tunnel or ngrok) for global mobile access.
  - Automatic IP detection and server launcher: `python scripts/start_server.py`.
- **Gmail ID & Password + Google Sign-In**:
  - Create accounts or log in using any Gmail address (`@gmail.com`) and secure password (PBKDF2 salted hash).
  - Quick Google Sign-In integration for mobile and web.
- **Patient Database Management**:
  - Add patients with custom or auto-generated clinical IDs (`PAT-1001`, `PAT-1002`, ...).
  - Modify patient demographics, contact details, emergency contacts, chronic conditions, allergies, and current medications at any time.
  - Real-time search by patient name, ID, phone number, or condition.
- **Medical History & Checkup Tracking (For Future Reference)**:
  - Log past and ongoing patient visits: Chief complaint, clinical diagnosis, vitals (systolic/diastolic blood pressure, fasting blood glucose, heart rate, temperature, body weight), prescriptions, doctor's notes, and follow-up dates.
  - Chronological visit timeline for reviewing patient trends over time.
- **Android APK with Dynamic Server Switching**:
  - Install the APK on any Android phone.
  - Built-in **Server Settings** modal allows easily switching the API address (e.g., `http://192.168.1.X:8000/api` or `https://xxxx.trycloudflare.com/api`) and testing connectivity with one tap.

---

## 1. Run Your PC as the Database & Server

1. Open PowerShell or Terminal in the project root:
   ```powershell
   py -m venv .venv
   .venv\Scripts\Activate.ps1
   py -m pip install -r requirements.txt
   ```

2. Start the server using the helper script:
   ```powershell
   py scripts/start_server.py
   ```
   This script:
   - Detects your PC's local Wi-Fi / LAN IP addresses.
   - Shows the exact URL to enter in the Android APK (e.g. `http://192.168.1.15:8000/api`).
   - Displays copy-paste instructions for free tunnels (Cloudflare Tunnel / ngrok) so users can reach your server anywhere over cellular data / internet.
   - Launches the FastAPI backend and creates the SQLite database in `data/healthbot.sqlite3`.

3. Open the web interface in your browser:
   [http://localhost:8000](http://localhost:8000)

---

## 2. Connect Mobile APK to Your PC Server

### Option A: Local Wi-Fi (Same Network)
1. Make sure your Android phone and PC are connected to the same Wi-Fi router.
2. In the Beluga APK, on the sign-in screen, tap the **Settings icon** (or the Server badge at the bottom).
3. Enter your PC's local IP address displayed by `scripts/start_server.py`:
   ```
   http://192.168.X.X:8000/api
   ```
4. Tap **Test Connection** to confirm connectivity, then tap **Save**.
5. (If prompted by Windows, make sure Python is allowed through Windows Firewall on private networks).

### Option B: Free Public Tunnel (Anywhere / Cellular Data)
If you want users to download the APK and connect from anywhere in the world:
1. In another terminal on your PC, start a tunnel:
   - **Cloudflare Tunnel (Free, no account needed)**:
     ```bash
     cloudflared tunnel --url http://localhost:8000
     ```
   - **ngrok**:
     ```bash
     ngrok http 8000
     ```
2. Cloudflare or ngrok will generate an HTTPS URL (e.g., `https://random-name.trycloudflare.com`).
3. In the APK, enter:
   ```
   https://random-name.trycloudflare.com/api
   ```
   Now any user with the APK can connect to the database running on your PC!

---

## 3. Account Creation & Sign In

- **Gmail ID & Password**: Enter your Gmail address (e.g., `doctor@gmail.com`) and choose a password. Tap **Create account** (or **Sign in**).
- **Google Sign-In**: Tap **Continue with Google** to sign in directly with your Gmail identity.

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
Push a version tag to trigger the GitHub Actions workflow:
```sh
git tag v1.1.0
git push origin v1.1.0
```
GitHub Actions will compile the Android APK and attach it to the Releases section for download.
