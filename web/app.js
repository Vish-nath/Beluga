const app = document.querySelector("#app");
const toastNode = document.querySelector("#toast");
const API = "/api";
let token = localStorage.getItem("beluga-token");
let currentUser = null;
let currentProfile = null;
let activePage = "overview";
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
};

const escapeHtml = (value = "") => String(value).replace(/[&<>"']/g, (character) => ({
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
  activePage = "overview";
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
        <div class="art-copy"><span class="eyebrow">YOUR DAILY HEALTH COMPANION</span><h1>Small steps.<br>Better days.</h1><p>A quieter way to keep track of how you feel, move, and rest.</p></div>
        <div class="pulse-visual"><span>01</span><div class="pulse-line">${icons.pulse}</div><span>24</span></div>
        <span class="art-caption">PERSONAL TRACKING, ON YOUR TERMS</span>
      </div>
      <div class="auth-panel">
        <div class="auth-mobile-brand brand">${icons.pulse}<span>beluga<span class="brand-light"> health</span></span></div>
        <div class="auth-form-wrap">
          <span class="eyebrow">${register ? "A FRESH START" : "WELCOME BACK"}</span>
          <h2>${register ? "Create your profile" : "Good to see you"}</h2>
          <p class="muted">${register ? "Your health information stays in your own account." : "Sign in to continue your daily check-in."}</p>
          <form id="auth-form" class="form-stack">
            ${register ? field("Your name", "name", "text", "", "autocomplete='name' required") : ""}
            ${field("Email address", "email", "email", "", "autocomplete='email' required")}
            ${field("Password", "password", "password", "", `autocomplete='${register ? "new-password" : "current-password"}' minlength='8' required`)}
            ${register ? `<div class="form-grid">${field("Age", "age", "number", "", "min='1' max='120'")}${field("Location", "location", "text", "", "placeholder='City or area'")}</div>` : ""}
            <button class="button button-primary button-wide" type="submit">${register ? "Create account" : "Sign in"}${icons.arrow}</button>
          </form>
          <p class="auth-switch">${register ? "Already have an account?" : "New to Beluga?"} <button class="text-button" id="auth-toggle">${register ? "Sign in" : "Create an account"}</button></p>
          <p class="privacy-note">This prototype is for personal tracking and education. It does not diagnose, prescribe, or replace medical care.</p>
        </div>
        <span class="auth-foot">BELUGA HEALTH · PERSONAL HEALTH SPACE</span>
      </div>
    </section>`;

  document.querySelector("#auth-toggle").addEventListener("click", () => authView(register ? "login" : "register"));
  document.querySelector("#auth-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = Object.fromEntries(form.entries());
    if (register) {
      payload.age = payload.age ? Number(payload.age) : null;
      payload.conditions = [];
    }
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
  const initials = (currentUser?.name || "U").split(/\s+/).map((part) => part[0]).slice(0, 2).join("").toUpperCase();
  app.innerHTML = `
    <div class="app-shell">
      <aside class="sidebar">
        <a class="brand" href="#" aria-label="Beluga Health home">${icons.pulse}<span>beluga<span class="brand-light"> health</span></span></a>
        <span class="nav-label">YOUR SPACE</span>
        <nav>${navItem("overview", "Overview", icons.home)}${navItem("measurements", "My health", icons.chart)}${navItem("reminders", "Reminders", icons.bell)}${navItem("profile", "Profile", icons.user)}</nav>
        <div class="sidebar-bottom"><div class="privacy-chip"><span></span>Personal account</div><button id="sign-out" class="sign-out">${icons.exit}<span>Sign out</span></button></div>
      </aside>
      <div class="workspace">
        <header class="topbar"><div><span class="topbar-date">${new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date())}</span><span class="connection"><i></i>Personal health space</span></div><button class="avatar" data-page="profile" aria-label="Open profile">${escapeHtml(initials)}</button></header>
        <main class="page-content">${content}</main>
      </div>
      <nav class="mobile-nav" aria-label="Main navigation">${navItem("overview", "Home", icons.home)}${navItem("measurements", "Health", icons.chart)}${navItem("reminders", "Reminders", icons.bell)}${navItem("profile", "Profile", icons.user)}</nav>
    </div>`;
  document.querySelectorAll("[data-page]").forEach((button) => button.addEventListener("click", () => navigate(button.dataset.page)));
  document.querySelector("#sign-out").addEventListener("click", () => signOut());
}

async function navigate(page) {
  activePage = page;
  await render();
}

async function renderOverview() {
  const data = await request("/dashboard");
  currentProfile = data.profile;
  const latest = data.latest_measurement || {};
  const todaySteps = latest.steps;
  const dataset = data.dataset;
  const reminders = data.reminders || [];
  const readings = data.measurements || [];
  const stepsGoal = 7000;
  const stepProgress = todaySteps == null ? 0 : Math.min(100, Math.round(todaySteps / stepsGoal * 100));
  const greeting = new Date().getHours() < 12 ? "Good morning" : new Date().getHours() < 18 ? "Good afternoon" : "Good evening";
  shell(`
    <section class="page-heading"><div><span class="eyebrow">YOUR HEALTH, AT A GLANCE</span><h1>${greeting}, ${escapeHtml(currentUser?.name?.split(" ")[0] || data.name)}</h1><p class="muted">A little check-in can make the day feel more intentional.</p></div><button class="button button-primary" data-action="log">${icons.plus}<span>Log today's health</span></button></section>
    <section class="metric-grid" aria-label="Latest health metrics">
      <article class="metric-card metric-green"><div class="metric-top"><span>Steps</span><span class="metric-icon">${icons.chart}</span></div><strong>${todaySteps == null ? "—" : Number(todaySteps).toLocaleString()}</strong><div class="metric-foot">${todaySteps == null ? "Log activity to begin" : `${stepProgress}% of a gentle 7,000-step goal`}</div><div class="progress-track"><i style="width:${stepProgress}%"></i></div></article>
      <article class="metric-card metric-coral"><div class="metric-top"><span>Active time</span><span class="metric-glyph">↗</span></div><strong>${latest.active_minutes == null ? "—" : `${latest.active_minutes}<small> min</small>`}</strong><div class="metric-foot">${latest.active_minutes == null ? "No activity logged yet" : "Minutes in your latest entry"}</div><div class="metric-rule"></div></article>
      <article class="metric-card metric-blue"><div class="metric-top"><span>Sleep</span><span class="metric-glyph">◒</span></div><strong>${latest.sleep_hours == null ? "—" : `${latest.sleep_hours}<small> hrs</small>`}</strong><div class="metric-foot">${latest.sleep_hours == null ? "No sleep logged yet" : "Hours in your latest entry"}</div><div class="metric-rule"></div></article>
      <article class="metric-card metric-yellow"><div class="metric-top"><span>Body mass index</span><span class="metric-glyph">⌁</span></div><strong>${currentProfile?.bmi ?? "—"}</strong><div class="metric-foot">${currentProfile?.height_cm && currentProfile?.weight_kg ? "Calculated from your profile" : "Add height and weight to calculate"}</div><div class="metric-rule"></div></article>
    </section>
    <section class="overview-grid">
      <article class="section-panel trend-panel"><div class="section-title"><div><span class="eyebrow">YOUR RECENT CHECK-INS</span><h2>Health readings</h2></div><button class="inline-action" data-page="measurements">See health log ${icons.arrow}</button></div>
        ${readings.length ? `<div class="reading-table"><div class="reading-row reading-head"><span>Date</span><span>Glucose</span><span>Blood pressure</span></div>${readings.slice(0, 5).map((reading) => `<div class="reading-row"><span>${new Date(reading.recorded_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}</span><span>${reading.fasting_glucose == null ? "—" : `${reading.fasting_glucose} <small>mg/dL</small>`}</span><span>${reading.systolic_bp == null ? "—" : `${reading.systolic_bp}/${reading.diastolic_bp} <small>mmHg</small>`}</span></div>`).join("")}</div>` : `<div class="empty-state"><div class="empty-mark">${icons.chart}</div><strong>Your health log starts here</strong><span>Record activity, sleep, or a reading to see your history.</span><button class="text-button" data-action="log">Add first check-in ${icons.arrow}</button></div>`}
      </article>
      <article class="section-panel reminder-panel"><div class="section-title"><div><span class="eyebrow">A GENTLE NUDGE</span><h2>Today's reminders</h2></div><button class="icon-button" data-action="new-reminder" aria-label="Add reminder" title="Add reminder">${icons.plus}</button></div>
        ${reminders.length ? `<div class="reminder-list">${reminders.slice(0, 4).map(reminderRow).join("")}</div>` : `<div class="empty-state compact"><div class="empty-mark warm">${icons.bell}</div><strong>Nothing scheduled today</strong><span>Add a reminder for a routine or check-in.</span><button class="text-button" data-action="new-reminder">Create reminder ${icons.arrow}</button></div>`}
      </article>
    </section>
    <section class="data-note"><div class="data-note-mark">i</div><div><strong>About the sample dataset</strong><p>${dataset ? `Aggregate summary: ${dataset.record_count} records, ${dataset.diabetes_count} diabetes labels, ${dataset.hypertension_count} hypertension labels.` : "No sample dataset summary has been imported on the laptop server yet."} These are sample-data counts, not a local disease forecast or an individual risk estimate.</p></div></section>
    ${data.reading_notes?.length ? `<section class="reading-note"><strong>Reading note</strong>${data.reading_notes.map((note) => `<p>${escapeHtml(note)}</p>`).join("")}</section>` : ""}
  `);
  bindDashboardActions();
}

function reminderRow(reminder) {
  return `<div class="reminder-row"><button class="reminder-check ${reminder.completed_today ? "is-done" : ""}" data-complete="${reminder.id}" aria-label="${reminder.completed_today ? "Completed" : "Mark complete"}" ${reminder.completed_today ? "disabled" : ""}>${icons.check}</button><div class="reminder-copy"><strong>${escapeHtml(reminder.title)}</strong><span>${escapeHtml(reminder.instruction || "Daily reminder")}</span></div><time>${escapeHtml(reminder.scheduled_time)}</time></div>`;
}

function bindDashboardActions() {
  document.querySelectorAll("[data-action='log']").forEach((button) => button.addEventListener("click", () => navigate("measurements")));
  document.querySelectorAll("[data-action='new-reminder']").forEach((button) => button.addEventListener("click", () => navigate("reminders")));
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
    <section class="page-heading"><div><span class="eyebrow">YOUR HEALTH LOG</span><h1>Check in with yourself</h1><p class="muted">Record the numbers and habits you choose to track.</p></div></section>
    <section class="health-layout">
      <article class="section-panel entry-panel"><div class="section-title"><div><span class="eyebrow">NEW ENTRY</span><h2>Today's health</h2></div><span class="date-stamp">${new Date().toLocaleDateString(undefined, { month: "short", day: "numeric" })}</span></div>
        <form id="measurement-form" class="form-stack">
          <div class="form-grid">${field("Steps", "steps", "number", "", "min='0' max='200000' placeholder='e.g. 4200'")}${field("Active minutes", "active_minutes", "number", "", "min='0' max='1440' placeholder='e.g. 30'")}</div>
          <div class="form-grid">${field("Sleep", "sleep_hours", "number", "", "min='0' max='24' step='0.1' placeholder='Hours')}${field("Fasting glucose", "fasting_glucose", "number", "", "min='20' max='1000' step='0.1' placeholder='mg/dL'")}</div>
          <div class="form-grid">${field("Systolic pressure", "systolic_bp", "number", "", "min='50' max='300' placeholder='mmHg'")}${field("Diastolic pressure", "diastolic_bp", "number", "", "min='30' max='200' placeholder='mmHg'")}</div>
          <p class="form-hint">Only enter measurements you have. For blood pressure, enter the upper and lower numbers from your monitor.</p>
          <button class="button button-primary" type="submit">Save check-in ${icons.arrow}</button>
        </form>
      </article>
      <aside class="guidance-panel"><span class="guidance-icon">${icons.pulse}</span><span class="eyebrow">A NOTE ON NUMBERS</span><h2>Patterns take time.</h2><p>A single reading cannot tell the whole story. Use measurements as a conversation starter with your healthcare professional.</p><div class="guidance-divider"></div><span class="guidance-label">PERSONAL PROFILE BMI</span><strong>${data.profile?.bmi ?? "—"}</strong><span class="guidance-small">${data.profile?.bmi ? "BMI is a screening measure, not a diagnosis." : "Add height and weight in your profile."}</span></aside>
    </section>
    <article class="section-panel history-panel"><div class="section-title"><div><span class="eyebrow">MOST RECENT FIRST</span><h2>Recent entries</h2></div><span class="history-count">${readings.length} ${readings.length === 1 ? "entry" : "entries"}</span></div>
      ${readings.length ? `<div class="history-table"><div class="history-row history-head"><span>Date</span><span>Steps</span><span>Active</span><span>Sleep</span><span>Glucose</span><span>Blood pressure</span></div>${readings.map((reading) => `<div class="history-row"><span>${new Date(reading.recorded_at).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</span><span>${reading.steps?.toLocaleString() ?? "—"}</span><span>${reading.active_minutes == null ? "—" : `${reading.active_minutes} min`}</span><span>${reading.sleep_hours == null ? "—" : `${reading.sleep_hours} hrs`}</span><span>${reading.fasting_glucose == null ? "—" : `${reading.fasting_glucose} mg/dL`}</span><span>${reading.systolic_bp == null ? "—" : `${reading.systolic_bp}/${reading.diastolic_bp}`}</span></div>`).join("")}</div>` : `<div class="empty-history">Your saved check-ins will appear here.</div>`}
    </article>
    ${data.reading_notes?.length ? `<section class="reading-note"><strong>Reading note</strong>${data.reading_notes.map((note) => `<p>${escapeHtml(note)}</p>`).join("")}</section>` : ""}
  `);

  document.querySelector("#measurement-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.currentTarget).entries());
    const payload = Object.fromEntries(Object.entries(values).filter(([, value]) => value !== "").map(([key, value]) => [key, Number(value)]));
    if (!Object.keys(payload).length) return showToast("Enter at least one measurement.", true);
    try {
      await request("/measurements", { method: "POST", body: JSON.stringify(payload) });
      showToast("Your check-in has been saved.");
      await renderMeasurements();
    } catch (error) { showToast(error.message, true); }
  });
}

async function renderReminders() {
  const reminders = await request("/reminders");
  shell(`
    <section class="page-heading"><div><span class="eyebrow">YOUR DAILY RHYTHM</span><h1>Reminders</h1><p class="muted">Keep helpful routines close, at times that work for you.</p></div></section>
    <section class="reminder-layout">
      <article class="section-panel reminder-manager"><div class="section-title"><div><span class="eyebrow">YOUR SCHEDULE</span><h2>Daily reminders</h2></div><span class="history-count">${reminders.length} active</span></div>
        ${reminders.length ? `<div class="managed-reminders">${reminders.map((item) => `<div class="managed-row"><div class="managed-time">${escapeHtml(item.scheduled_time)}</div><div class="managed-copy"><strong>${escapeHtml(item.title)}</strong><span>${escapeHtml(item.instruction || "Personal reminder")}</span></div><button class="delete-button" data-delete="${item.id}" aria-label="Remove ${escapeHtml(item.title)}" title="Remove reminder">×</button></div>`).join("")}</div>` : `<div class="empty-history">Create a reminder to add it to your daily rhythm.</div>`}
      </article>
      <article class="section-panel reminder-form-panel"><div class="section-title"><div><span class="eyebrow">MAKE IT YOURS</span><h2>Add a reminder</h2></div></div>
        <form id="reminder-form" class="form-stack">${field("What would you like to remember?", "title", "text", "", "maxlength='100' placeholder='For example, evening walk' required")}${field("Time", "scheduled_time", "time", "08:00", "required")}<label class="field"><span>Note <small>Optional</small></span><input name="instruction" maxlength="120" placeholder="A short personal note"></label><button class="button button-primary button-wide" type="submit">Add reminder ${icons.plus}</button><p class="form-hint">Reminders are stored in your account and appear when you open the app. Background notifications are not enabled in this prototype.</p></form>
      </article>
    </section>
  `);
  document.querySelector("#reminder-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const payload = Object.fromEntries(new FormData(event.currentTarget).entries());
    try {
      await request("/reminders", { method: "POST", body: JSON.stringify(payload) });
      showToast("Reminder added to your schedule.");
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
    <section class="page-heading"><div><span class="eyebrow">YOUR INFORMATION</span><h1>Personal profile</h1><p class="muted">Keep the details you choose to share up to date.</p></div></section>
    <section class="profile-layout">
      <article class="section-panel profile-panel"><div class="section-title"><div><span class="eyebrow">ABOUT YOU</span><h2>Profile details</h2></div><span class="profile-badge">${escapeHtml(currentUser.email)}</span></div>
        <form id="profile-form" class="form-stack"><div class="form-grid">${field("Full name", "name", "text", currentUser.name, "autocomplete='name' required")}${field("Email address", "email", "email", currentUser.email, "disabled")}</div><div class="form-grid">${field("Age", "age", "number", profile.age ?? "", "min='1' max='120'")}<label class="field"><span>Gender <small>Optional</small></span><select name="gender"><option value="">Prefer not to say</option>${["Female", "Male", "Non-binary", "Self-describe"].map((value) => `<option ${profile.gender === value ? "selected" : ""}>${value}</option>`).join("")}</select></label></div><div class="form-grid"><label class="field"><span>Blood type <small>Optional</small></span><select name="blood_type"><option value="">Not provided</option>${["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"].map((value) => `<option value="${value}" ${profile.blood_type === value ? "selected" : ""}>${value}</option>`).join("")}</select></label><div></div></div><div class="form-grid">${field("Height", "height_cm", "number", profile.height_cm ?? "", "min='40' max='260' step='0.1' placeholder='cm'")}${field("Weight", "weight_kg", "number", profile.weight_kg ?? "", "min='2' max='400' step='0.1' placeholder='kg'")}</div>${field("Location", "location", "text", profile.location ?? "", "maxlength='120' placeholder='City or area'")}<label class="field"><span>Health conditions <small>Optional</small></span><textarea name="conditions" rows="2" placeholder="Add only what you choose to track">${escapeHtml((profile.conditions || []).join(", "))}</textarea></label><label class="field"><span>Current medications <small>Optional</small></span><textarea name="medications" rows="2" placeholder="Separate medication names with commas">${escapeHtml((profile.medications || []).join(", "))}</textarea><small class="field-note">Saved for your reference only. This prototype does not check drug interactions or dosage.</small></label><div class="profile-summary"><span>Calculated BMI</span><strong>${profile.bmi ?? "—"}</strong><small>Screening measure only, not a diagnosis.</small></div><button class="button button-primary" type="submit">Save profile ${icons.arrow}</button></form>
      </article>
      <aside class="profile-aside"><div class="profile-aside-mark">${icons.user}</div><span class="eyebrow">YOUR DATA</span><h2>You're in control.</h2><p>Your information is kept in the laptop-hosted database for this prototype. Only add data you are comfortable storing there.</p><div class="privacy-chip"><span></span>Stored on your server</div></aside>
    </section>
  `);
  document.querySelector("#profile-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.currentTarget).entries());
    const conditions = values.conditions.split(",").map((value) => value.trim()).filter(Boolean);
    const medications = values.medications.split(",").map((value) => value.trim()).filter(Boolean);
    const payload = { name: values.name.trim(), age: values.age ? Number(values.age) : null, gender: values.gender, blood_type: values.blood_type, height_cm: values.height_cm ? Number(values.height_cm) : null, weight_kg: values.weight_kg ? Number(values.weight_kg) : null, location: values.location, conditions, medications };
    try {
      currentProfile = await request("/profile", { method: "PUT", body: JSON.stringify(payload) });
      currentUser.name = values.name.trim();
      showToast("Your profile has been updated.");
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
    if (activePage === "overview") await renderOverview();
    else if (activePage === "measurements") await renderMeasurements();
    else if (activePage === "reminders") await renderReminders();
    else await renderProfile();
  } catch (error) {
    if (error.message.toLowerCase().includes("fetch")) {
      app.innerHTML = `<section class="offline-state"><div class="offline-mark">${icons.pulse}</div><span class="eyebrow">SERVER UNAVAILABLE</span><h1>Let's reconnect.</h1><p>The laptop server may be asleep or disconnected from this network.</p><button class="button button-primary" id="retry">Try again</button><button class="text-button" id="offline-signout">Sign out</button></section>`;
      document.querySelector("#retry").addEventListener("click", render);
      document.querySelector("#offline-signout").addEventListener("click", () => signOut());
    } else showToast(error.message, true);
  }
}

function signOut(notify = true) {
  if (token) request("/logout", { method: "POST" }).catch(() => {});
  token = null;
  currentUser = null;
  currentProfile = null;
  localStorage.removeItem("beluga-token");
  activePage = "overview";
  authView();
  if (notify) showToast("You have signed out.");
}

document.addEventListener("click", (event) => {
  const pageButton = event.target.closest("[data-page]");
  if (pageButton && !pageButton.closest(".app-shell")) navigate(pageButton.dataset.page);
});

if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost")) {
  navigator.serviceWorker.register("/service-worker.js").catch(() => {});
}

render();