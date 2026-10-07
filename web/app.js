const app = document.querySelector("#app");
const toastNode = document.querySelector("#toast");
const API = "/api";
let token = localStorage.getItem("beluga-token");
let currentUser = null;
let currentProfile = null;
let activePage = "patients";
let activePatientId = null;
let toastTimer;

const icons = {
  pulse: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg>',
  home: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-6v-7h-4v7H4a1 1 0 0 1-1-1z"/></svg>',
  chart: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 19V5m0 14h17M8 15l4-4 3 2 5-6"/></svg>',
  bell: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9m-8 12h4"/></svg>',
  user: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
  plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>',
  exit: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 17l5-5-5-5m5 5H3m9-9h7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-7"/></svg>',
  arrow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>',
  patients: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
  search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>',
  edit: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>',
  trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>',
  calendar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>',
};

const escapeHtml = (value = "") => String(value ?? "").replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[character]));

function showToast(message, error = false) {
  toastNode.textContent = message;
  toastNode.classList.toggle("is-error", error);
  toastNode.classList.add("is-visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastNode.classList.remove("is-visible"), 3000);
}

async function request(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${API}${path}`, { ...options, headers });
  if (response.status === 204) return null;
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && token) signOut(false);
    throw new Error(body.detail || "Something went wrong. Please try again.");
  }
  return body;
}

function setSession(result) {
  token = result.access_token;
  currentUser = result.user;
  currentProfile = result.profile;
  localStorage.setItem("beluga-token", token);
  activePage = "patients";
  render();
}

function field(label, name, type = "text", value = "", extra = "") {
  return `<label class="field"><span>${label}</span><input name="${name}" type="${type}" value="${escapeHtml(value ?? "")}" ${extra}></label>`;
}

function authView(mode = "login") {
  const register = mode === "register";
  app.innerHTML = `
    <section class="auth-layout">
      <div class="auth-art" aria-hidden="true">
        <a class="brand" href="#">${icons.pulse}<span>beluga<span class="brand-light"> health</span></span></a>
        <div class="art-copy">
          <span class="eyebrow">YOUR CLINICAL & PERSONAL HEALTH SPACE</span>
          <h1>Small steps.<br>Better care.</h1>
          <p>Local database & server for patient record tracking, clinical checkups, and future reference.</p>
        </div>
        <div class="pulse-visual"><span>01</span><div class="pulse-line">${icons.pulse}</div><span>24</span></div>
        <span class="art-caption">LAPTOP-HOSTED SERVER & DATABASE</span>
      </div>
      <div class="auth-panel">
        <div class="auth-mobile-brand brand">${icons.pulse}<span>beluga<span class="brand-light"> health</span></span></div>
        <div class="auth-form-wrap">
          <span class="eyebrow">${register ? "NEW CLINICIAN / USER" : "WELCOME BACK"}</span>
          <h2>${register ? "Create your account" : "Sign in to Beluga"}</h2>
          <p class="muted">${register ? "Create an account with your email and password." : "Sign in with your email and password."}</p>

          <form id="auth-form" class="form-stack">
            ${register ? field("Full name", "name", "text", "", "autocomplete='name' required") : ""}
            ${field("Gmail / Email address", "email", "email", "", "autocomplete='email' placeholder='name@gmail.com' required")}
            ${field("Password", "password", "password", "", `autocomplete='${register ? "new-password" : "current-password"}' minlength='8' required`)}
            <button class="button button-primary button-wide" type="submit">${register ? "Create account" : "Sign in"}${icons.arrow}</button>
          </form>
          <p class="auth-switch">${register ? "Already have an account?" : "New to Beluga?"} <button class="text-button" id="auth-toggle">${register ? "Sign in" : "Create an account"}</button></p>
          <p class="privacy-note">The app administrator can view account health records. This prototype is not for real health data.</p>
        </div>
        <span class="auth-foot">BELUGA HEALTH · LOCAL SERVER & DATABASE</span>
      </div>
    </section>`;

  document.querySelector("#auth-toggle").addEventListener("click", () => authView(register ? "login" : "register"));

  document.querySelector("#auth-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = Object.fromEntries(form.entries());
    const submitButton = event.currentTarget.querySelector("button[type=submit]");
    submitButton.disabled = true;
    try {
      setSession(await request(register ? "/register" : "/login", { method: "POST", body: JSON.stringify(payload) }));
    } catch (error) {
      showToast(error.message, true);
      submitButton.disabled = false;
    }
  });
}

function navItem(page, label, icon) {
  return `<button class="nav-item ${activePage === page ? "is-active" : ""}" data-page="${page}">${icon}<span>${label}</span>${activePage === page ? '<i></i>' : ""}</button>`;
}

function shell(content) {
  const initials = (currentUser?.name?.trim() || "U")
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => part[0])
    .slice(0, 2)
    .join("")
    .toUpperCase() || "U";
  app.innerHTML = `
    <div class="app-shell">
      <aside class="sidebar">
        <a class="brand" href="#" aria-label="Beluga Health home">${icons.pulse}<span>beluga<span class="brand-light"> health</span></span></a>
        <span class="nav-label">DATABASE & CLINICAL</span>
        <nav>
          ${navItem("patients", "Patients", icons.patients)}
          ${navItem("overview", "Overview", icons.home)}
          ${navItem("measurements", "My health", icons.chart)}
          ${navItem("reminders", "Reminders", icons.bell)}
          ${navItem("profile", "Profile", icons.user)}
        </nav>
        <div class="sidebar-bottom">
          <div class="privacy-chip"><span></span>PC Local Database</div>
          <button id="sign-out" class="sign-out">${icons.exit}<span>Sign out</span></button>
        </div>
      </aside>
      <div class="workspace">
        <header class="topbar">
          <div>
            <span class="topbar-date">${new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date())}</span>
            <span class="connection"><i></i>Beluga Local Database</span>
          </div>
          <button class="avatar" data-page="profile" aria-label="Open profile">${escapeHtml(initials)}</button>
        </header>
        <main class="page-content">${content}</main>
      </div>
      <nav class="mobile-nav" aria-label="Main navigation">
        ${navItem("patients", "Patients", icons.patients)}
        ${navItem("overview", "Home", icons.home)}
        ${navItem("measurements", "Health", icons.chart)}
        ${navItem("reminders", "Reminders", icons.bell)}
        ${navItem("profile", "Profile", icons.user)}
      </nav>
    </div>`;
  document.querySelectorAll("[data-page]").forEach((button) => button.addEventListener("click", () => navigate(button.dataset.page)));
  document.querySelector("#sign-out").addEventListener("click", () => signOut());
}

async function navigate(page, patientId = null) {
  activePage = page;
  activePatientId = patientId;
  await render();
}

// ==========================================
// PATIENTS MANAGEMENT VIEW (WEB)
// ==========================================

async function renderPatients(query = "") {
  const url = query ? `/patients?q=${encodeURIComponent(query)}` : "/patients";
  const patients = await request(url);
  shell(`
    <section class="page-heading">
      <div>
        <span class="eyebrow">PATIENT DATABASE</span>
        <h1>Patients & Medical Records</h1>
        <p class="muted">Store, modify, and track patient data and clinical checkups for future reference.</p>
      </div>
      <button class="button button-primary" id="btn-add-patient">${icons.plus}<span>Add new patient</span></button>
    </section>

    <div class="patient-header-bar">
      <div class="search-box">
        ${icons.search}
        <input type="text" id="patient-search" placeholder="Search patients by name, ID, phone, condition..." value="${escapeHtml(query)}">
      </div>
      <span class="history-count">${patients.length} ${patients.length === 1 ? 'patient' : 'patients'} registered</span>
    </div>

    ${patients.length ? `
      <div class="patients-grid">
        ${patients.map(p => `
          <div class="patient-card" data-patient-id="${p.patient_id}">
            <div>
              <div class="patient-top">
                <div>
                  <h3 class="patient-name">${escapeHtml(p.name)}</h3>
                  <span class="patient-id">${escapeHtml(p.patient_id)}</span>
                </div>
                <span class="tag tag-blue">${escapeHtml(p.blood_group || 'Blood N/A')}</span>
              </div>
              <p class="muted" style="font-size:12px;margin:8px 0 0;">${p.age} years · ${escapeHtml(p.gender)}</p>
              ${p.phone ? `<p style="font-size:12px;margin:4px 0 0;color:#555;">📞 ${escapeHtml(p.phone)}</p>` : ''}
              
              <div class="patient-tags">
                ${(p.chronic_conditions || []).map(c => `<span class="tag">${escapeHtml(c)}</span>`).join('')}
                ${(p.allergies || []).map(a => `<span class="tag tag-alert">Allergy: ${escapeHtml(a)}</span>`).join('')}
              </div>
            </div>
            <div class="patient-foot">
              <span>${p.visit_count} visit record(s)</span>
              <span style="color:var(--green);font-weight:600;">View & Modify ${icons.arrow}</span>
            </div>
          </div>
        `).join('')}
      </div>
    ` : `
      <div class="empty-state">
        <div class="empty-mark">${icons.patients}</div>
        <strong>No patients found</strong>
        <span>Add a patient record to manage their health data and checkups.</span>
        <button class="button button-primary" style="margin-top:12px;" id="btn-empty-add-patient">${icons.plus}<span>Add First Patient</span></button>
      </div>
    `}
  `);

  const searchInput = document.querySelector("#patient-search");
  let searchDebounce;
  searchInput.addEventListener("input", (e) => {
    clearTimeout(searchDebounce);
    const val = e.target.value;
    searchDebounce = setTimeout(async () => {
      await renderPatients(val.trim());
      const newSearchInput = document.querySelector("#patient-search");
      if (newSearchInput) {
        newSearchInput.focus();
        newSearchInput.setSelectionRange(newSearchInput.value.length, newSearchInput.value.length);
      }
    }, 300);
  });

  document.querySelectorAll("[data-patient-id]").forEach(card => {
    card.addEventListener("click", () => navigate("patient-detail", card.dataset.patientId));
  });

  const openAdd = () => openPatientModal();
  document.querySelector("#btn-add-patient")?.addEventListener("click", openAdd);
  document.querySelector("#btn-empty-add-patient")?.addEventListener("click", openAdd);
}

// ==========================================
// PATIENT DETAIL & VISITS VIEW (WEB)
// ==========================================

async function renderPatientDetail(patientId) {
  const patient = await request(`/patients/${patientId}`);
  const visits = patient.visits || [];

  shell(`
    <section class="page-heading">
      <div>
        <button class="inline-action" id="btn-back-patients" style="margin-bottom:8px;">← Back to Patients list</button>
        <div style="display:flex;align-items:center;gap:12px;">
          <h1>${escapeHtml(patient.name)}</h1>
          <span class="patient-id" style="font-size:14px;padding:4px 10px;">${escapeHtml(patient.patient_id)}</span>
        </div>
      </div>
      <div style="display:flex;gap:10px;">
        <button class="button button-secondary" id="btn-edit-patient">${icons.edit}<span>Modify Patient Data</span></button>
        <button class="button button-primary" id="btn-add-visit">${icons.plus}<span>Add Medical Record</span></button>
      </div>
    </section>

    <div class="detail-layout">
      <!-- Profile Card -->
      <div class="patient-profile-card">
        <h3 style="margin-top:0;font-size:16px;">Demographics & Profile</h3>
        <div class="profile-meta-row"><span>Age / Gender</span><strong>${patient.age} yrs · ${escapeHtml(patient.gender)}</strong></div>
        <div class="profile-meta-row"><span>Blood Group</span><strong>${escapeHtml(patient.blood_group || 'Not provided')}</strong></div>
        <div class="profile-meta-row"><span>Phone</span><strong>${escapeHtml(patient.phone || '—')}</strong></div>
        <div class="profile-meta-row"><span>Email</span><strong>${escapeHtml(patient.email || '—')}</strong></div>
        <div class="profile-meta-row"><span>Emergency Contact</span><strong>${escapeHtml(patient.emergency_contact || '—')}</strong></div>
        <div class="profile-meta-row"><span>Address</span><strong>${escapeHtml(patient.address || '—')}</strong></div>

        <div style="margin-top:16px;">
          <h4 style="margin:0 0 6px;font-size:12px;color:var(--muted);text-transform:uppercase;">Chronic Conditions</h4>
          <div class="patient-tags">
            ${(patient.chronic_conditions || []).length ? patient.chronic_conditions.map(c => `<span class="tag">${escapeHtml(c)}</span>`).join('') : '<span class="muted">None recorded</span>'}
          </div>
        </div>

        <div style="margin-top:12px;">
          <h4 style="margin:0 0 6px;font-size:12px;color:var(--muted);text-transform:uppercase;">Allergies</h4>
          <div class="patient-tags">
            ${(patient.allergies || []).length ? patient.allergies.map(a => `<span class="tag tag-alert">⚠️ ${escapeHtml(a)}</span>`).join('') : '<span class="muted">No known allergies</span>'}
          </div>
        </div>

        <div style="margin-top:12px;">
          <h4 style="margin:0 0 6px;font-size:12px;color:var(--muted);text-transform:uppercase;">Current Medications</h4>
          <div class="patient-tags">
            ${(patient.current_medications || []).length ? patient.current_medications.map(m => `<span class="tag tag-blue">💊 ${escapeHtml(m)}</span>`).join('') : '<span class="muted">None</span>'}
          </div>
        </div>

        ${patient.notes ? `
          <div style="margin-top:14px;padding-top:12px;border-top:1px solid var(--line);">
            <h4 style="margin:0 0 4px;font-size:12px;color:var(--muted);text-transform:uppercase;">Clinical Notes</h4>
            <p style="font-size:13px;line-height:1.5;margin:0;">${escapeHtml(patient.notes)}</p>
          </div>
        ` : ''}

        <div style="margin-top:20px;padding-top:14px;border-top:1px solid var(--line);">
          <button class="text-button" id="btn-delete-patient" style="color:#d32f2f;">Delete Patient Record</button>
        </div>
      </div>

      <!-- Medical History & Visits Timeline -->
      <div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
          <h3 style="margin:0;font-size:18px;">Medical History & Visits (${visits.length})</h3>
          <span class="muted" style="font-size:12px;">Historical data retained for future reference</span>
        </div>

        ${visits.length ? `
          <div class="visit-list">
            ${visits.map(v => `
              <div class="visit-card">
                <div class="visit-top">
                  <span class="visit-date">${icons.calendar} ${escapeHtml(v.visit_date)}</span>
                  ${v.next_followup ? `<span class="tag tag-blue">Next Follow-up: ${escapeHtml(v.next_followup)}</span>` : ''}
                </div>

                ${v.chief_complaint ? `<h4 style="margin:4px 0 6px;font-size:15px;">Complaint: ${escapeHtml(v.chief_complaint)}</h4>` : ''}
                ${v.diagnosis ? `<p style="margin:0 0 8px;color:var(--green-deep);font-weight:600;font-size:13px;">Diagnosis: ${escapeHtml(v.diagnosis)}</p>` : ''}

                <div class="vitals-bar">
                  ${v.systolic_bp && v.diastolic_bp ? `<div class="vital-chip"><small>Blood Pressure</small><strong>${v.systolic_bp}/${v.diastolic_bp} mmHg</strong></div>` : ''}
                  ${v.fasting_glucose ? `<div class="vital-chip"><small>Fasting Glucose</small><strong>${v.fasting_glucose} mg/dL</strong></div>` : ''}
                  ${v.heart_rate ? `<div class="vital-chip"><small>Heart Rate</small><strong>${v.heart_rate} bpm</strong></div>` : ''}
                  ${v.temperature ? `<div class="vital-chip"><small>Temp</small><strong>${v.temperature} °C</strong></div>` : ''}
                  ${v.weight_kg ? `<div class="vital-chip"><small>Weight</small><strong>${v.weight_kg} kg</strong></div>` : ''}
                </div>

                ${(v.prescriptions || []).length ? `
                  <div style="margin-top:10px;">
                    <strong style="font-size:11px;text-transform:uppercase;color:var(--muted);">Prescriptions:</strong>
                    ${v.prescriptions.map(rx => `<div class="rx-item">💊 <span>${escapeHtml(rx)}</span></div>`).join('')}
                  </div>
                ` : ''}

                ${v.clinical_notes ? `
                  <div style="margin-top:10px;font-size:12px;font-style:italic;color:#444;">
                    "${escapeHtml(v.clinical_notes)}"
                  </div>
                ` : ''}
              </div>
            `).join('')}
          </div>
        ` : `
          <div class="empty-state">
            <div class="empty-mark">${icons.chart}</div>
            <strong>No medical records yet</strong>
            <span>Add a checkup record with symptoms, vitals, prescriptions, and notes.</span>
            <button class="button button-primary" style="margin-top:12px;" id="btn-empty-add-visit">${icons.plus}<span>Add First Record</span></button>
          </div>
        `}
      </div>
    </div>
  `);

  document.querySelector("#btn-back-patients")?.addEventListener("click", () => navigate("patients"));
  document.querySelector("#btn-edit-patient")?.addEventListener("click", () => openPatientModal(patient));
  document.querySelector("#btn-add-visit")?.addEventListener("click", () => openVisitModal(patient.patient_id));
  document.querySelector("#btn-empty-add-visit")?.addEventListener("click", () => openVisitModal(patient.patient_id));

  document.querySelector("#btn-delete-patient")?.addEventListener("click", async () => {
    if (!confirm(`Are you sure you want to delete patient '${patient.name}' and all associated records?`)) return;
    try {
      await request(`/patients/${patient.patient_id}`, { method: "DELETE" });
      showToast("Patient record deleted.");
      navigate("patients");
    } catch (err) {
      showToast(err.message, true);
    }
  });
}

function openPatientModal(existing = null) {
  const modal = document.createElement("div");
  modal.className = "modal-backdrop";
  modal.innerHTML = `
    <div class="modal-dialog">
      <div class="modal-top">
        <h3>${existing ? "Modify Patient Data" : "Add New Patient"}</h3>
        <button class="modal-close">&times;</button>
      </div>
      <form id="modal-patient-form" class="form-stack">
        ${field("Full Name *", "name", "text", existing?.name || "", "required")}
        <div class="form-grid">
          ${field("Patient ID (auto if empty)", "patient_id", "text", existing?.patient_id || "", "placeholder='e.g. PAT-1001'")}
          ${field("Age *", "age", "number", existing?.age || "", "min='0' max='150' required")}
        </div>
        <div class="form-grid">
          <label class="field"><span>Gender</span>
            <select name="gender">
              <option value="Female" ${existing?.gender === 'Female' ? 'selected' : ''}>Female</option>
              <option value="Male" ${existing?.gender === 'Male' ? 'selected' : ''}>Male</option>
              <option value="Other" ${existing?.gender === 'Other' ? 'selected' : ''}>Other</option>
            </select>
          </label>
          <label class="field"><span>Blood Group</span>
            <select name="blood_group">
              <option value="">Not known</option>
              ${['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map(bg => `<option value="${bg}" ${existing?.blood_group === bg ? 'selected' : ''}>${bg}</option>`).join('')}
            </select>
          </label>
        </div>
        <div class="form-grid">
          ${field("Phone Number", "phone", "tel", existing?.phone || "")}
          ${field("Email Address", "email", "email", existing?.email || "")}
        </div>
        <div class="form-grid">
          ${field("Emergency Contact", "emergency_contact", "text", existing?.emergency_contact || "")}
          ${field("Address", "address", "text", existing?.address || "")}
        </div>
        ${field("Chronic Conditions (comma separated)", "chronic_conditions", "text", (existing?.chronic_conditions || []).join(', '), "placeholder='Diabetes, Hypertension, Asthma'")}
        ${field("Allergies (comma separated)", "allergies", "text", (existing?.allergies || []).join(', '), "placeholder='Penicillin, Peanuts'")}
        ${field("Current Medications (comma separated)", "current_medications", "text", (existing?.current_medications || []).join(', '), "placeholder='Metformin 500mg, Lisinopril 10mg'")}
        <label class="field"><span>Clinical Notes</span><textarea name="notes" rows="2" placeholder="General observations or history">${escapeHtml(existing?.notes || '')}</textarea></label>
        <button class="button button-primary button-wide" type="submit">${existing ? "Save Changes" : "Create Patient"}</button>
      </form>
    </div>
  `;
  document.body.appendChild(modal);

  const close = () => modal.remove();
  modal.querySelector(".modal-close").addEventListener("click", close);
  modal.addEventListener("click", (e) => { if (e.target === modal) close(); });

  modal.querySelector("#modal-patient-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(e.currentTarget).entries());
    const payload = {
      patient_id: data.patient_id.trim() || null,
      name: data.name.trim(),
      age: Number(data.age),
      gender: data.gender,
      blood_group: data.blood_group,
      phone: data.phone.trim(),
      email: data.email.trim(),
      address: data.address.trim(),
      emergency_contact: data.emergency_contact.trim(),
      chronic_conditions: data.chronic_conditions.split(',').map(s => s.trim()).filter(Boolean),
      allergies: data.allergies.split(',').map(s => s.trim()).filter(Boolean),
      current_medications: data.current_medications.split(',').map(s => s.trim()).filter(Boolean),
      notes: data.notes.trim(),
    };

    try {
      if (existing) {
        await request(`/patients/${existing.patient_id}`, { method: "PUT", body: JSON.stringify(payload) });
        showToast("Patient record updated.");
        close();
        renderPatientDetail(payload.patient_id || existing.patient_id);
      } else {
        const created = await request("/patients", { method: "POST", body: JSON.stringify(payload) });
        showToast("New patient created.");
        close();
        renderPatientDetail(created.patient_id);
      }
    } catch (err) {
      showToast(err.message, true);
    }
  });
}

function openVisitModal(patientId) {
  const modal = document.createElement("div");
  modal.className = "modal-backdrop";
  const today = new Date().toISOString().substring(0, 10);
  modal.innerHTML = `
    <div class="modal-dialog">
      <div class="modal-top">
        <h3>Add Medical Checkup / Record</h3>
        <button class="modal-close">&times;</button>
      </div>
      <form id="modal-visit-form" class="form-stack">
        <div class="form-grid">
          ${field("Visit Date *", "visit_date", "date", today, "required")}
          ${field("Next Follow-up (optional)", "next_followup", "date", "")}
        </div>
        ${field("Chief Complaint / Symptoms *", "chief_complaint", "text", "", "placeholder='e.g. Headache, high fever' required")}
        ${field("Diagnosis / Assessment", "diagnosis", "text", "", "placeholder='e.g. Stage 1 Hypertension'")}
        <div class="form-grid">
          ${field("Systolic BP (mmHg)", "systolic_bp", "number", "", "min='30' max='300'")}
          ${field("Diastolic BP (mmHg)", "diastolic_bp", "number", "", "min='20' max='200'")}
        </div>
        <div class="form-grid">
          ${field("Fasting Glucose (mg/dL)", "fasting_glucose", "number", "", "min='10' max='1000' step='0.1'")}
          ${field("Heart Rate (bpm)", "heart_rate", "number", "", "min='20' max='250'")}
        </div>
        <div class="form-grid">
          ${field("Temperature (°C)", "temperature", "number", "", "min='25' max='45' step='0.1'")}
          ${field("Weight (kg)", "weight_kg", "number", "", "min='1' max='400' step='0.1'")}
        </div>
        ${field("Prescriptions (comma separated)", "prescriptions", "text", "", "placeholder='e.g. Metformin 500mg, Paracetamol 500mg'")}
        <label class="field"><span>Clinical Notes & Advice</span><textarea name="clinical_notes" rows="2" placeholder="Lifestyle advice, test results, doctor remarks"></textarea></label>
        <button class="button button-primary button-wide" type="submit">Save Medical Record</button>
      </form>
    </div>
  `;
  document.body.appendChild(modal);

  const close = () => modal.remove();
  modal.querySelector(".modal-close").addEventListener("click", close);
  modal.addEventListener("click", (e) => { if (e.target === modal) close(); });

  modal.querySelector("#modal-visit-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(e.currentTarget).entries());
    const payload = {
      visit_date: data.visit_date,
      chief_complaint: data.chief_complaint.trim(),
      diagnosis: data.diagnosis.trim(),
      systolic_bp: data.systolic_bp ? Number(data.systolic_bp) : null,
      diastolic_bp: data.diastolic_bp ? Number(data.diastolic_bp) : null,
      fasting_glucose: data.fasting_glucose ? Number(data.fasting_glucose) : null,
      heart_rate: data.heart_rate ? Number(data.heart_rate) : null,
      temperature: data.temperature ? Number(data.temperature) : null,
      weight_kg: data.weight_kg ? Number(data.weight_kg) : null,
      prescriptions: data.prescriptions.split(',').map(s => s.trim()).filter(Boolean),
      clinical_notes: data.clinical_notes.trim(),
      next_followup: data.next_followup || null,
    };

    try {
      await request(`/patients/${patientId}/visits`, { method: "POST", body: JSON.stringify(payload) });
      showToast("Medical visit recorded.");
      close();
      renderPatientDetail(patientId);
    } catch (err) {
      showToast(err.message, true);
    }
  });
}

// ==========================================
// OVERVIEW, MEASUREMENTS, REMINDERS, PROFILE
// ==========================================

async function renderOverview() {
  const data = await request("/dashboard");
  currentProfile = data.profile;
  const latest = data.latest_measurement || {};
  const todaySteps = latest.steps;
  const dataset = data.dataset;
  const reminders = data.reminders || [];
  const readings = data.measurements || [];
  const patientsCount = data.patients_count || 0;
  const greeting = new Date().getHours() < 12 ? "Good morning" : new Date().getHours() < 18 ? "Good afternoon" : "Good evening";

  shell(`
    <section class="page-heading">
      <div>
        <span class="eyebrow">YOUR HEALTH DATABASE</span>
        <h1>${greeting}, ${escapeHtml(currentUser?.name?.split(" ")[0] || data.name)}</h1>
        <p class="muted">Local server and database for clinical records & daily check-ins.</p>
      </div>
      <button class="button button-primary" data-page="patients">${icons.patients}<span>Manage Patients</span></button>
    </section>

    <!-- Quick Patient Banner -->
    <div style="background:var(--green-wash);border:1px solid #d2e4d9;border-radius:8px;padding:16px 20px;margin-bottom:20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;">
      <div>
        <h3 style="margin:0 0 4px;color:var(--green-deep);font-size:16px;">${patientsCount} Patient(s) In Local Database</h3>
        <p style="margin:0;font-size:13px;color:#335b49;">Manage patient records, update diagnoses, and save checkups for future reference.</p>
      </div>
      <button class="button button-primary" data-page="patients">Open Patients List ${icons.arrow}</button>
    </div>

    <section class="metric-grid" aria-label="Latest health metrics">
      <article class="metric-card metric-green"><div class="metric-top"><span>Steps</span><span class="metric-icon">${icons.chart}</span></div><strong>${todaySteps == null ? "—" : Number(todaySteps).toLocaleString()}</strong><div class="metric-foot">${todaySteps == null ? "Log personal activity" : `Daily activity logged`}</div><div class="progress-track"><i style="width:${todaySteps ? 100 : 0}%"></i></div></article>
      <article class="metric-card metric-coral"><div class="metric-top"><span>Active time</span><span class="metric-glyph">↗</span></div><strong>${latest.active_minutes == null ? "—" : `${latest.active_minutes}<small> min</small>`}</strong><div class="metric-foot">${latest.active_minutes == null ? "No activity logged" : "Minutes in latest entry"}</div><div class="metric-rule"></div></article>
      <article class="metric-card metric-blue"><div class="metric-top"><span>Sleep</span><span class="metric-glyph">◒</span></div><strong>${latest.sleep_hours == null ? "—" : `${latest.sleep_hours}<small> hrs</small>`}</strong><div class="metric-foot">${latest.sleep_hours == null ? "No sleep logged" : "Hours in latest entry"}</div><div class="metric-rule"></div></article>
      <article class="metric-card metric-yellow"><div class="metric-top"><span>Body mass index</span><span class="metric-glyph">⌁</span></div><strong>${currentProfile?.bmi ?? "—"}</strong><div class="metric-foot">${currentProfile?.height_cm && currentProfile?.weight_kg ? "Calculated from profile" : "Add height and weight in profile"}</div><div class="metric-rule"></div></article>
    </section>

    <section class="overview-grid">
      <article class="section-panel trend-panel"><div class="section-title"><div><span class="eyebrow">RECENT CHECK-INS</span><h2>Personal Health readings</h2></div><button class="inline-action" data-page="measurements">See log ${icons.arrow}</button></div>
        ${readings.length ? `<div class="reading-table"><div class="reading-row reading-head"><span>Date</span><span>Glucose</span><span>Blood pressure</span></div>${readings.slice(0, 5).map((reading) => `<div class="reading-row"><span>${new Date(reading.recorded_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}</span><span>${reading.fasting_glucose == null ? "—" : `${reading.fasting_glucose} <small>mg/dL</small>`}</span><span>${reading.systolic_bp != null && reading.diastolic_bp != null ? `${reading.systolic_bp}/${reading.diastolic_bp} <small>mmHg</small>` : (reading.systolic_bp ?? reading.diastolic_bp ?? "—")}</span></div>`).join("")}</div>` : `<div class="empty-state"><div class="empty-mark">${icons.chart}</div><strong>No personal check-ins yet</strong><button class="text-button" data-action="log">Add check-in ${icons.arrow}</button></div>`}
      </article>
      <article class="section-panel reminder-panel"><div class="section-title"><div><span class="eyebrow">DAILY ROUTINE</span><h2>Today's reminders</h2></div><button class="icon-button" data-action="new-reminder" aria-label="Add reminder">${icons.plus}</button></div>
        ${reminders.length ? `<div class="reminder-list">${reminders.slice(0, 4).map(reminderRow).join("")}</div>` : `<div class="empty-state compact"><div class="empty-mark warm">${icons.bell}</div><strong>No reminders</strong></div>`}
      </article>
    </section>
  `);
  bindDashboardActions();
}

function reminderRow(reminder) {
  return `<div class="reminder-row"><button class="reminder-check ${reminder.completed_today ? "is-done" : ""}" data-complete="${reminder.id}" aria-label="${reminder.completed_today ? "Completed" : "Mark complete"}" ${reminder.completed_today ? "disabled" : ""}>${icons.check}</button><div class="reminder-copy"><strong>${escapeHtml(reminder.title)}</strong><span>${escapeHtml(reminder.instruction || "Daily reminder")}</span></div><time>${escapeHtml(reminder.scheduled_time)}</time></div>`;
}

function bindDashboardActions() {
  document.querySelectorAll("[data-action='log']").forEach((b) => b.addEventListener("click", () => navigate("measurements")));
  document.querySelectorAll("[data-action='new-reminder']").forEach((b) => b.addEventListener("click", () => navigate("reminders")));
  document.querySelectorAll("[data-complete]").forEach((button) => button.addEventListener("click", async () => {
    try {
      await request(`/reminders/${button.dataset.complete}/complete`, { method: "POST" });
      showToast("Reminder marked complete.");
      await renderOverview();
    } catch (error) { showToast(error.message, true); }
  }));
}

async function renderMeasurements() {
  const data = await request("/dashboard");
  const readings = data.measurements || [];
  shell(`
    <section class="page-heading"><div><span class="eyebrow">YOUR HEALTH LOG</span><h1>Daily Check-ins</h1><p class="muted">Record personal metrics and vitals.</p></div></section>
    <section class="health-layout">
      <article class="section-panel entry-panel"><div class="section-title"><div><span class="eyebrow">NEW ENTRY</span><h2>Log measurements</h2></div><span class="date-stamp">${new Date().toLocaleDateString(undefined, { month: "short", day: "numeric" })}</span></div>
        <form id="measurement-form" class="form-stack">
          <div class="form-grid">${field("Steps", "steps", "number", "", "min='0' max='200000' placeholder='e.g. 4200'")}${field("Active minutes", "active_minutes", "number", "", "min='0' max='1440' placeholder='e.g. 30'")}</div>
          <div class="form-grid">${field("Sleep", "sleep_hours", "number", "", "min='0' max='24' step='0.1' placeholder='Hours')}${field("Fasting glucose", "fasting_glucose", "number", "", "min='20' max='1000' step='0.1' placeholder='mg/dL'")}</div>
          <div class="form-grid">${field("Systolic pressure", "systolic_bp", "number", "", "min='50' max='300' placeholder='mmHg'")}${field("Diastolic pressure", "diastolic_bp", "number", "", "min='30' max='200' placeholder='mmHg'")}</div>
          <button class="button button-primary" type="submit">Save check-in ${icons.arrow}</button>
        </form>
      </article>
      <aside class="guidance-panel"><span class="guidance-icon">${icons.pulse}</span><span class="eyebrow">NOTE</span><h2>Vitals Tracking</h2><p>Measurements are saved directly to your local database.</p></aside>
    </section>
    <article class="section-panel history-panel" style="margin-top:20px;"><div class="section-title"><div><span class="eyebrow">HISTORY</span><h2>Recent personal entries</h2></div><span class="history-count">${readings.length} entries</span></div>
      ${readings.length ? `<div class="history-table"><div class="history-row history-head"><span>Date</span><span>Steps</span><span>Active</span><span>Sleep</span><span>Glucose</span><span>Blood pressure</span></div>${readings.map((reading) => `<div class="history-row"><span>${new Date(reading.recorded_at).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</span><span>${reading.steps?.toLocaleString() ?? "—"}</span><span>${reading.active_minutes == null ? "—" : `${reading.active_minutes} min`}</span><span>${reading.sleep_hours == null ? "—" : `${reading.sleep_hours} hrs`}</span><span>${reading.fasting_glucose == null ? "—" : `${reading.fasting_glucose} mg/dL`}</span><span>${reading.systolic_bp != null && reading.diastolic_bp != null ? `${reading.systolic_bp}/${reading.diastolic_bp}` : (reading.systolic_bp ?? reading.diastolic_bp ?? "—")}</span></div>`).join("")}</div>` : `<div class="empty-history">Your saved check-ins will appear here.</div>`}
    </article>
  `);

  document.querySelector("#measurement-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.currentTarget).entries());
    const payload = Object.fromEntries(Object.entries(values).filter(([, value]) => value !== "").map(([key, value]) => [key, Number(value)]));
    if (!Object.keys(payload).length) return showToast("Enter at least one measurement.", true);
    try {
      await request("/measurements", { method: "POST", body: JSON.stringify(payload) });
      showToast("Check-in saved.");
      await renderMeasurements();
    } catch (error) { showToast(error.message, true); }
  });
}

async function renderReminders() {
  const reminders = await request("/reminders");
  shell(`
    <section class="page-heading"><div><span class="eyebrow">YOUR SCHEDULE</span><h1>Reminders</h1><p class="muted">Keep routine checkups and medications on schedule.</p></div></section>
    <section class="reminder-layout">
      <article class="section-panel reminder-manager"><div class="section-title"><div><span class="eyebrow">DAILY ROUTINE</span><h2>Active Reminders</h2></div><span class="history-count">${reminders.length} active</span></div>
        ${reminders.length ? `<div class="managed-reminders">${reminders.map((item) => `<div class="managed-row"><div class="managed-time">${escapeHtml(item.scheduled_time)}</div><div class="managed-copy"><strong>${escapeHtml(item.title)}</strong><span>${escapeHtml(item.instruction || "Personal reminder")}</span></div><button class="delete-button" data-delete="${item.id}" title="Remove reminder">×</button></div>`).join("")}</div>` : `<div class="empty-history">Create a reminder to add it to your daily routine.</div>`}
      </article>
      <article class="section-panel reminder-form-panel"><div class="section-title"><div><span class="eyebrow">ADD NEW</span><h2>Create reminder</h2></div></div>
        <form id="reminder-form" class="form-stack">${field("Title", "title", "text", "", "placeholder='e.g. Patient follow-up' required")}${field("Time", "scheduled_time", "time", "08:00", "required")}<label class="field"><span>Note</span><input name="instruction" placeholder="Short note"></label><button class="button button-primary button-wide" type="submit">Add reminder ${icons.plus}</button></form>
      </article>
    </section>
  `);
  document.querySelector("#reminder-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const payload = Object.fromEntries(new FormData(event.currentTarget).entries());
    try {
      await request("/reminders", { method: "POST", body: JSON.stringify(payload) });
      showToast("Reminder added.");
      await renderReminders();
    } catch (error) { showToast(error.message, true); }
  });
  document.querySelectorAll("[data-delete]").forEach((button) => button.addEventListener("click", async () => {
    try {
      await request(`/reminders/${button.dataset.delete}`, { method: "DELETE" });
      showToast("Reminder removed.");
      await renderReminders();
    } catch (error) { showToast(error.message, true); }
  }));
}

async function renderProfile() {
  const data = await request("/me");
  currentUser = data.user;
  currentProfile = data.profile;
  const profile = data.profile || {};
  shell(`
    <section class="page-heading"><div><span class="eyebrow">YOUR ACCOUNT</span><h1>User Profile</h1><p class="muted">Beluga Database & Server credentials.</p></div></section>
    <section class="profile-layout">
      <article class="section-panel profile-panel"><div class="section-title"><div><span class="eyebrow">ABOUT YOU</span><h2>Account details</h2></div><span class="profile-badge">${escapeHtml(currentUser.email)}</span></div>
        <form id="profile-form" class="form-stack"><div class="form-grid">${field("Full name", "name", "text", currentUser.name, "required")}${field("Gmail / Email address", "email", "email", currentUser.email, "disabled")}</div><div class="form-grid">${field("Age", "age", "number", profile.age ?? "")}<label class="field"><span>Gender</span><select name="gender"><option value="">Prefer not to say</option>${["Female", "Male", "Non-binary", "Self-describe"].map((v) => `<option ${profile.gender === v ? "selected" : ""}>${v}</option>`).join("")}</select></label></div><div class="form-grid"><label class="field"><span>Blood type</span><select name="blood_type"><option value="">Not provided</option>${["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"].map((v) => `<option value="${v}" ${profile.blood_type === v ? "selected" : ""}>${v}</option>`).join("")}</select></label><div></div></div><div class="form-grid">${field("Height (cm)", "height_cm", "number", profile.height_cm ?? "")}${field("Weight (kg)", "weight_kg", "number", profile.weight_kg ?? "")}</div>${field("Location", "location", "text", profile.location ?? "")}<button class="button button-primary" type="submit">Save profile ${icons.arrow}</button></form>
      </article>
      <aside class="profile-aside"><div class="profile-aside-mark">${icons.user}</div><span class="eyebrow">DATABASE</span><h2>MongoDB Connected</h2><p>Your records are stored in the configured MongoDB database. The app administrator can view account data.</p><div class="privacy-chip"><span></span>MongoDB Storage</div></aside>
    </section>
  `);
  document.querySelector("#profile-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.currentTarget).entries());
    const payload = {
      name: values.name.trim(),
      age: values.age ? Number(values.age) : null,
      gender: values.gender,
      blood_type: values.blood_type,
      height_cm: values.height_cm ? Number(values.height_cm) : null,
      weight_kg: values.weight_kg ? Number(values.weight_kg) : null,
      location: values.location,
      conditions: currentProfile?.conditions || [],
      medications: currentProfile?.medications || [],
      appetite: currentProfile?.appetite || "",
      daily_routine: currentProfile?.daily_routine || "",
      family_history: currentProfile?.family_history || "",
      prescriptions: currentProfile?.prescriptions || [],
      profile_image: currentProfile?.profile_image || "",
    };
    try {
      currentProfile = await request("/profile", { method: "PUT", body: JSON.stringify(payload) });
      currentUser.name = values.name.trim();
      showToast("Profile saved.");
      await renderProfile();
    } catch (error) { showToast(error.message, true); }
  });
}

async function render() {
  if (!token) return authView();
  try {
    if (!currentUser) {
      const session = await request("/me");
      currentUser = session.user;
      currentProfile = session.profile;
    }
    if (activePage === "patients") await renderPatients();
    else if (activePage === "patient-detail" && activePatientId) await renderPatientDetail(activePatientId);
    else if (activePage === "overview") await renderOverview();
    else if (activePage === "measurements") await renderMeasurements();
    else if (activePage === "reminders") await renderReminders();
    else await renderProfile();
  } catch (error) {
    if (error.message.toLowerCase().includes("fetch")) {
      app.innerHTML = `<section class="offline-state"><div class="offline-mark">${icons.pulse}</div><span class="eyebrow">SERVER UNAVAILABLE</span><h1>Let's reconnect.</h1><p>The Python server may be stopped. Run <code>python scripts/start_server.py</code> to restart it.</p><button class="button button-primary" id="retry">Try again</button><button class="text-button" id="offline-signout">Sign out</button></section>`;
      document.querySelector("#retry").addEventListener("click", render);
      document.querySelector("#offline-signout").addEventListener("click", () => signOut());
    } else showToast(error.message, true);
  }
}

function signOut(notify = true) {
  const currentToken = token;
  token = null;
  currentUser = null;
  currentProfile = null;
  localStorage.removeItem("beluga-token");
  activePage = "patients";
  activePatientId = null;
  if (currentToken) {
    fetch(`${API}/logout`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${currentToken}` },
    }).catch(() => {});
  }
  authView();
  if (notify) showToast("You have signed out.");
}

document.addEventListener("click", (event) => {
  const pageButton = event.target.closest("[data-page]");
  if (pageButton && !pageButton.closest(".app-shell")) navigate(pageButton.dataset.page);
});

render();