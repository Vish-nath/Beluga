/* =========================================================
   BELUGA HEALTH — WEB APPLICATION CORE (v2.0)
   Modern, secure, reactive SPA with glassmorphism & motion
   ========================================================= */

(function () {
  "use strict";

  const appNode = document.querySelector("#app");
  const toastContainer = document.querySelector("#toast-container");
  const API = (document.querySelector('meta[name="beluga-api-base"]')?.content || "/api").trim().replace(/\/+$/, "");

  let token = null;
  try {
    token = localStorage.getItem("beluga-token") || null;
  } catch (_) {
    // The sign-in screen can still render when storage is unavailable (for example, file previews).
  }
  let currentUser = null;
  let currentProfile = null;
  let activePage = "overview";
  let activePatientId = null;
  let activeChart = null;

  // ==========================================
  // ICONS (Clean, stroke-based SVG icons)
  // ==========================================
  const icons = {
    pulse: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg>`,
    home: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-6v-7h-4v7H4a1 1 0 0 1-1-1z"/></svg>`,
    patients: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>`,
    chart: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 19V5m0 14h17M8 15l4-4 3 2 5-6"/></svg>`,
    bell: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9m-8 12h4"/></svg>`,
    user: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>`,
    plus: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>`,
    check: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>`,
    exit: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 17l5-5-5-5m5 5H3m9-9h7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-7"/></svg>`,
    arrow: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>`,
    search: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>`,
    edit: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>`,
    trash: `<svg viewBox="0 0 24 24" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>`,
    calendar: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`,
    alert: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`,
    sparkle: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 1.912 5.885L20 10.8l-4.5 4.385L16.568 21 12 17.585 7.432 21l1.068-5.815L4 10.8l6.088-1.915L12 3z"/></svg>`,
    shield: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
  };

  function setupCustomCursor() {
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches ||
        window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const cursor = document.createElement("span");
    cursor.className = "custom-cursor is-hidden";
    cursor.setAttribute("aria-hidden", "true");
    document.body.append(cursor);

    let pointerX = 0;
    let pointerY = 0;
    let frameId = 0;
    document.addEventListener("pointermove", (event) => {
      if (event.pointerType !== "mouse") return;
      pointerX = event.clientX;
      pointerY = event.clientY;
      const target = event.target instanceof Element ? event.target : null;
      cursor.classList.toggle("is-hidden", Boolean(target?.closest("input, textarea, select, [contenteditable='true']")));
      cursor.classList.toggle("is-interactive", Boolean(target?.closest("a, button, [role='button']")));

      if (!frameId) {
        frameId = requestAnimationFrame(() => {
          cursor.style.transform = `translate3d(${pointerX}px, ${pointerY}px, 0) translate(-50%, -50%)`;
          frameId = 0;
        });
      }
    }, { passive: true });
    document.addEventListener("pointerdown", () => cursor.classList.add("is-pressed"), { passive: true });
    document.addEventListener("pointerup", () => cursor.classList.remove("is-pressed"), { passive: true });
    document.addEventListener("pointerleave", () => cursor.classList.add("is-hidden"));
  }

  setupCustomCursor();

  // ==========================================
  // UTILITIES
  // ==========================================
  const escapeHtml = (val = "") =>
    String(val ?? "").replace(/[&<>"']/g, (ch) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[ch]));

  function showToast(message, type = "success") {
    if (!toastContainer) return;
    const isError = type === true || type === "error";
    const toast = document.createElement("div");
    toast.className = `toast ${isError ? "toast-error" : "toast-success"}`;
    toast.innerHTML = `
      ${isError ? icons.alert : icons.check}
      <span>${escapeHtml(message)}</span>
    `;
    toastContainer.appendChild(toast);

    setTimeout(() => {
      toast.classList.add("toast-hide");
      setTimeout(() => toast.remove(), 250);
    }, 3500);
  }

  async function request(path, options = {}) {
    const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
    if (token) headers.Authorization = `Bearer ${token}`;

    const res = await fetch(`${API}${path}`, { ...options, headers });
    if (res.status === 204) return null;

    const contentType = (res.headers.get("content-type") || "").toLowerCase();
    if (!contentType.includes("application/json")) {
      throw new Error("Beluga's API did not return data. Start the FastAPI server or set the API address in web/index.html.");
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      if (res.status === 401 && token) {
        signOut(false);
      }
      throw new Error(data.detail || "Request failed. Please check input and try again.");
    }
    return data;
  }

  function destroyCurrentChart() {
    if (activeChart) {
      try {
        activeChart.destroy();
      } catch (_) {}
      activeChart = null;
    }
  }

  function setSession(authResponse) {
    token = authResponse.access_token;
    currentUser = authResponse.user;
    currentProfile = authResponse.profile;
    try {
      localStorage.setItem("beluga-token", token);
    } catch (_) {}
    activePage = "overview";
    render();
  }

  function signOut(notify = true) {
    const oldToken = token;
    token = null;
    currentUser = null;
    currentProfile = null;
    try {
      localStorage.removeItem("beluga-token");
    } catch (_) {}
    destroyCurrentChart();
    activePage = "overview";
    activePatientId = null;

    if (oldToken) {
      fetch(`${API}/logout`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${oldToken}` },
      }).catch(() => {});
    }

    renderAuth();
    if (notify) showToast("You have been signed out.", "info");
  }

  function renderField(label, name, type = "text", value = "", extra = "") {
    return `
      <div class="field">
        <label class="field-label" for="fld-${name}">${label}</label>
        <input id="fld-${name}" name="${name}" type="${type}" value="${escapeHtml(value ?? "")}" ${extra}>
      </div>
    `;
  }

  // ==========================================
  // AUTH VIEW (LOGIN & REGISTER)
  // ==========================================
  function renderAuth(mode = "login") {
    destroyCurrentChart();
    const isRegister = mode === "register";

    appNode.innerHTML = `
      <div class="auth-page">
      <section class="auth-layout">
        <section class="auth-art" aria-labelledby="auth-hero-title">
          <div class="auth-art-bg"></div>
          <div class="auth-art-grid"></div>

          <div class="auth-brand">
            <div class="auth-brand-icon">${icons.pulse}</div>
            <span>beluga<span class="auth-brand-sub"> health</span></span>
          </div>

          <div class="auth-art-main">
            <div class="auth-art-copy">
              <span class="eyebrow">${icons.sparkle} YOUR HEALTH WORKSPACE</span>
              <h1 id="auth-hero-title">Care feels clearer <span>when it’s together.</span></h1>
              <p>One calm place for personal check-ins, daily reminders, and patient visit notes.</p>
            </div>
            <figure class="auth-photo-frame">
              <img class="auth-hero-photo" src="https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?auto=format&amp;fit=crop&amp;w=640&amp;q=75" srcset="https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?auto=format&amp;fit=crop&amp;w=420&amp;q=70 420w, https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?auto=format&amp;fit=crop&amp;w=760&amp;q=75 760w" sizes="(max-width: 560px) 112px, (max-width: 860px) 180px, 32vw" alt="Healthcare professional reviewing information on a phone" width="640" height="800" fetchpriority="high" decoding="async">
              <figcaption class="auth-photo-caption"><span class="auth-photo-status"></span>Care details, all in one place</figcaption>
            </figure>
          </div>

          <div class="auth-art-bottom">
            <div class="auth-stats">
              <div class="auth-stat">
                <strong>Health</strong>
                <span>Personal check-ins</span>
              </div>
              <div class="auth-stat">
                <strong>Reminders</strong>
                <span>Keep daily routines close</span>
              </div>
              <div class="auth-stat">
                <strong>Records</strong>
                <span>Patient notes & visits</span>
              </div>
            </div>
            <div class="auth-art-footer">
              A STUDENT PROJECT PROTOTYPE · USE SYNTHETIC DATA ONLY
            </div>
          </div>
        </section>

        <div class="auth-panel">
          <div class="auth-form-wrap">
            <span class="eyebrow">${isRegister ? "GET STARTED" : "YOUR BELUGA ACCOUNT"}</span>
            <h2>${isRegister ? "Create your account" : "Welcome back"}</h2>
            <p class="auth-sub">${isRegister ? "Set up your space for health check-ins, reminders, and patient notes." : "Sign in to see your health entries, reminders, and patient records."}</p>

            <form id="auth-form" class="form-stack" novalidate>
              ${isRegister ? renderField("Full Name", "name", "text", "", "autocomplete='name' required placeholder='Your name'") : ""}
              ${renderField("Email Address", "email", "email", "", "autocomplete='email' required placeholder='you@example.com'")}
              ${renderField("Password", "password", "password", "", `autocomplete='${isRegister ? "new-password" : "current-password"}' minlength='8' required placeholder='••••••••'`)}
              ${isRegister ? '<p class="auth-password-hint">Use at least 8 characters for your password.</p>' : ""}
              
              <button class="btn btn-primary btn-wide" type="submit" id="btn-auth-submit" style="margin-top:6px;">
                <span>${isRegister ? "Create Account" : "Sign In to Workspace"}</span>
                ${icons.arrow}
              </button>
            </form>

            <div class="auth-switch-row">
              ${isRegister ? "Already registered?" : "Don't have an account yet?"}
              <button class="text-btn" id="auth-switch-btn" type="button">
                ${isRegister ? "Sign in instead" : "Create new account"}
              </button>
            </div>

            <div class="auth-foot-note">
              ${icons.shield} Beluga is a student project prototype. Use synthetic data only; this app does not diagnose conditions or recommend treatment.
            </div>
          </div>
        </div>
      </section>

      <section class="auth-info" aria-labelledby="auth-info-heading">
        <div class="auth-info-inner">
          <header class="auth-info-heading">
            <span class="eyebrow">A LITTLE MORE ROOM TO BREATHE</span>
            <h2 id="auth-info-heading">Everyday health, in one clear view.</h2>
            <p>Bring check-ins, useful reminders, and visit context together without making your routine feel complicated.</p>
          </header>

          <div class="auth-info-grid">
            <article class="auth-info-feature">
              <img src="https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?auto=format&amp;fit=crop&amp;w=720&amp;q=75" alt="Clinician using a phone to review health information" width="720" height="480" loading="lazy" decoding="async">
              <div class="auth-info-copy">
                <span class="auth-info-kicker">01 / CHECK IN</span>
                <h3>Notice your patterns</h3>
                <p>Keep everyday health entries together so you can look back at what you have recorded.</p>
              </div>
            </article>
            <article class="auth-info-feature">
              <img src="https://images.unsplash.com/photo-1506126613408-eca07ce68773?auto=format&amp;fit=crop&amp;w=720&amp;q=75" alt="Person taking a quiet moment for a daily wellness routine" width="640" height="744" loading="lazy" decoding="async">
              <div class="auth-info-copy">
                <span class="auth-info-kicker">02 / REMIND</span>
                <h3>Make space for routines</h3>
                <p>Set simple reminders for the habits and tasks you want to keep close through the day.</p>
              </div>
            </article>
            <article class="auth-info-feature">
              <img src="https://images.unsplash.com/photo-1532938911079-1b06ac7ceec7?auto=format&amp;fit=crop&amp;w=720&amp;q=75" alt="Healthcare professional with a stethoscope" width="720" height="480" loading="lazy" decoding="async">
              <div class="auth-info-copy">
                <span class="auth-info-kicker">03 / ORGANIZE</span>
                <h3>Keep visit details together</h3>
                <p>Organize patient notes and visit information in one place for this project workspace.</p>
              </div>
            </article>
          </div>

          <aside class="auth-info-safety">
            ${icons.shield}
            <p><strong>Student project prototype.</strong> Use synthetic data only. Beluga does not diagnose conditions or recommend treatment.</p>
          </aside>
        </div>
      </section>

      <footer class="auth-site-footer">
        <span>© ${new Date().getFullYear()} Beluga Health</span>
        <span>Built as a student project · Use synthetic data only</span>
      </footer>
      </div>
    `;

    document.querySelector("#auth-switch-btn").addEventListener("click", () => {
      renderAuth(isRegister ? "login" : "register");
    });

    const form = document.querySelector("#auth-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const formData = new FormData(form);
      const payload = Object.fromEntries(formData.entries());

      if (!payload.email || !payload.email.includes("@")) {
        return showToast("Please provide a valid email address.", "error");
      }
      if (!payload.password || payload.password.length < 8) {
        return showToast("Password must be at least 8 characters long.", "error");
      }
      if (isRegister && !payload.name?.trim()) {
        return showToast("Please enter your name.", "error");
      }

      const submitBtn = document.querySelector("#btn-auth-submit");
      submitBtn.disabled = true;
      submitBtn.innerHTML = `<span class="loader" style="width:18px;height:18px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:8px;"></span> Authenticating...`;

      try {
        const endpoint = isRegister ? "/register" : "/login";
        const result = await request(endpoint, {
          method: "POST",
          body: JSON.stringify(payload),
        });
        showToast(isRegister ? "Account created successfully!" : "Signed in successfully!");
        setSession(result);
      } catch (err) {
        showToast(err.message, "error");
        submitBtn.disabled = false;
        submitBtn.innerHTML = `<span>${isRegister ? "Create Account" : "Sign In to Workspace"}</span> ${icons.arrow}`;
      }
    });
  }

  // ==========================================
  // APPLICATION SHELL (SIDEBAR + TOPBAR + CONTENT)
  // ==========================================
  function renderShell(contentHtml) {
    const userName = currentUser?.name?.trim() || "Beluga member";
    const initials = userName
      .split(/\s+/)
      .filter(Boolean)
      .map((n) => n[0])
      .slice(0, 2)
      .join("")
      .toUpperCase() || "BH";

    const navItems = [
      { id: "overview", label: "Overview", icon: icons.home },
      { id: "measurements", label: "Health check-ins", icon: icons.chart },
      { id: "reminders", label: "Reminders", icon: icons.bell },
      { id: "patients", label: "Patient records", icon: icons.patients },
      { id: "profile", label: "My profile", icon: icons.user },
    ];

    appNode.innerHTML = `
      <div class="app-shell">
        <!-- Sidebar Navigation -->
        <aside class="sidebar">
          <a class="sidebar-brand" href="#" data-page="overview">
            <div class="sidebar-brand-icon">${icons.pulse}</div>
            <span>beluga<span class="sidebar-brand-sub"> health</span></span>
          </a>

          <div class="nav-section-label">Health workspace</div>
          <nav class="sidebar-nav">
            ${navItems
              .map(
                (item) => `
                <button class="nav-item ${activePage === item.id ? "is-active" : ""}" data-page="${item.id}" type="button">
                  ${item.icon}
                  <span>${item.label}</span>
                </button>
              `
              )
              .join("")}
          </nav>

          <div class="sidebar-bottom">
            <div class="status-dot">Workspace connected</div>
            <div class="user-chip">
              <div class="user-avatar">${escapeHtml(initials)}</div>
              <div class="user-chip-info">
                <div class="user-chip-name">${escapeHtml(userName)}</div>
                <div class="user-chip-role">${escapeHtml(currentUser?.email || "Local Server")}</div>
              </div>
            </div>
            <button class="sign-out-btn" id="btn-sign-out" type="button">
              ${icons.exit}
              <span>Sign out</span>
            </button>
          </div>
        </aside>

        <!-- Workspace & Topbar -->
        <div class="workspace">
          <header class="topbar">
            <div class="topbar-left">
              <span class="topbar-date">${new Intl.DateTimeFormat(undefined, {
                weekday: "long",
                month: "short",
                day: "numeric",
                year: "numeric",
              }).format(new Date())}</span>
              <div class="topbar-badge">Signed in</div>
            </div>
            <div class="topbar-right">
              <button class="topbar-avatar" data-page="profile" title="View Profile" type="button">
                ${escapeHtml(initials)}
              </button>
            </div>
          </header>

          <main class="page-content">
            ${contentHtml}
          </main>
        </div>

        <!-- Mobile Navigation Bottom Bar -->
        <nav class="mobile-nav" aria-label="Mobile Navigation">
          ${navItems
            .map(
              (item) => `
              <button class="mob-nav-item ${activePage === item.id ? "is-active" : ""}" data-page="${item.id}" type="button">
                ${item.icon}
                <span>${item.label.split(" ")[0]}</span>
              </button>
            `
            )
            .join("")}
        </nav>
      </div>
    `;

    // Bind navigation buttons
    document.querySelectorAll("[data-page]").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        const page = btn.dataset.page;
        if (page) navigate(page);
      });
    });

    document.querySelector("#btn-sign-out").addEventListener("click", () => signOut());
  }

  async function navigate(page, patientId = null) {
    destroyCurrentChart();
    activePage = page;
    activePatientId = patientId;
    await render();
  }

  // ==========================================
  // PATIENTS DIRECTORY (PRIMARY CLINICAL VIEW)
  // ==========================================
  async function renderPatients(searchQuery = "") {
    let patients = [];
    try {
      const url = searchQuery ? `/patients?q=${encodeURIComponent(searchQuery)}` : "/patients";
      patients = await request(url);
    } catch (err) {
      showToast(err.message, "error");
    }

    const contentHtml = `
      <section class="page-heading">
        <div>
          <span class="eyebrow">${icons.shield} PATIENT RECORDS</span>
          <h1>Patient records</h1>
          <p>Keep patient details, visit notes, and follow-up dates organized in one place.</p>
        </div>
        <div class="page-heading-actions">
          <button class="btn btn-primary" id="btn-add-patient" type="button">
            ${icons.plus}
            <span>Register New Patient</span>
          </button>
        </div>
      </section>

      <div class="patients-toolbar">
        <div class="search-box">
          ${icons.search}
          <input type="text" id="patient-search-input" placeholder="Search by name, ID, phone, condition..." value="${escapeHtml(searchQuery)}">
        </div>
        <div class="mono" style="font-size:12px;color:var(--text-muted);">
          Patient records: <strong style="color:var(--cyan);">${patients.length}</strong>
        </div>
      </div>

      ${
        patients.length
          ? `
        <div class="patients-grid">
          ${patients
            .map((p) => {
              const pInitials = (p.name || "P")
                .split(/\s+/)
                .filter(Boolean)
                .map((n) => n[0])
                .slice(0, 2)
                .join("")
                .toUpperCase();
              return `
                <article class="patient-card" data-patient-id="${escapeHtml(p.patient_id)}" tabindex="0" role="button">
                  <div class="patient-card-head">
                    <div class="patient-avatar">${escapeHtml(pInitials)}</div>
                    <div class="patient-card-info">
                      <h3 class="patient-name">${escapeHtml(p.name)}</h3>
                      <div class="patient-pid">${escapeHtml(p.patient_id)}</div>
                    </div>
                    <span class="tag tag-cyan">${escapeHtml(p.blood_group || "Blood N/A")}</span>
                  </div>

                  <div class="patient-meta">
                    <strong>${p.age} yrs</strong> · ${escapeHtml(p.gender || "Unspecified")}
                    ${p.phone ? ` · <span>📞 ${escapeHtml(p.phone)}</span>` : ""}
                  </div>

                  <div class="patient-tags">
                    ${(p.chronic_conditions || [])
                      .slice(0, 3)
                      .map((c) => `<span class="tag tag-amber">${escapeHtml(c)}</span>`)
                      .join("")}
                    ${(p.allergies || [])
                      .slice(0, 2)
                      .map((a) => `<span class="tag tag-rose">Allergy: ${escapeHtml(a)}</span>`)
                      .join("")}
                    ${!p.chronic_conditions?.length && !p.allergies?.length ? `<span class="tag">No conditions or allergies added</span>` : ""}
                  </div>

                  <div class="patient-card-foot">
                    <span>${p.visit_count} recorded visit(s)</span>
                    <span class="patient-card-foot-action">
                      Open Record ${icons.arrow}
                    </span>
                  </div>
                </article>
              `;
            })
            .join("")}
        </div>
      `
          : `
        <div class="empty-state">
          <div class="empty-icon">${icons.patients}</div>
          <h3>${searchQuery ? "No matching patients" : "No patient records registered"}</h3>
          <p>${searchQuery ? `No results found for "${escapeHtml(searchQuery)}". Try searching another term.` : "Start tracking clinical records by adding your first patient."}</p>
          <button class="btn btn-primary" id="btn-empty-add-patient" type="button">
            ${icons.plus}
            <span>Add Patient Record</span>
          </button>
        </div>
      `
      }
    `;

    renderShell(contentHtml);

    // Search input with debounce
    const searchInput = document.querySelector("#patient-search-input");
    if (searchInput) {
      let debounceTimer;
      searchInput.addEventListener("input", (e) => {
        clearTimeout(debounceTimer);
        const val = e.target.value;
        debounceTimer = setTimeout(async () => {
          await renderPatients(val.trim());
          const newSearch = document.querySelector("#patient-search-input");
          if (newSearch) {
            newSearch.focus();
            newSearch.setSelectionRange(newSearch.value.length, newSearch.value.length);
          }
        }, 280);
      });
    }

    // Patient card click
    document.querySelectorAll("[data-patient-id]").forEach((card) => {
      const openDetail = () => navigate("patient-detail", card.dataset.patientId);
      card.addEventListener("click", openDetail);
      card.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          openDetail();
        }
      });
    });

    document.querySelector("#btn-add-patient")?.addEventListener("click", () => openPatientModal());
    document.querySelector("#btn-empty-add-patient")?.addEventListener("click", () => openPatientModal());
  }

  // ==========================================
  // PATIENT DETAIL & MEDICAL VISITS TIMELINE
  // ==========================================
  async function renderPatientDetail(patientId) {
    let patient = null;
    try {
      patient = await request(`/patients/${patientId}`);
    } catch (err) {
      showToast(err.message, "error");
      return navigate("patients");
    }

    const visits = patient.visits || [];
    const pInitials = (patient.name || "P")
      .split(/\s+/)
      .filter(Boolean)
      .map((n) => n[0])
      .slice(0, 2)
      .join("")
      .toUpperCase();

    const contentHtml = `
      <section class="page-heading">
        <div>
          <button class="inline-back" id="btn-back-patients" type="button">
            ← Back to Patient Directory
          </button>
          <h1>${escapeHtml(patient.name)}</h1>
          <p>Saved details and visit notes for this patient.</p>
        </div>
        <div class="page-heading-actions">
          <button class="btn btn-secondary" id="btn-edit-patient" type="button">
            ${icons.edit}
            <span>Modify Patient</span>
          </button>
          <button class="btn btn-primary" id="btn-add-visit" type="button">
            ${icons.plus}
            <span>Add Medical Record</span>
          </button>
        </div>
      </section>

      <div class="detail-layout">
        <!-- Patient Overview Sidebar Card -->
        <aside class="patient-profile-card">
          <div class="patient-profile-hero">
            <div class="patient-profile-avatar">${escapeHtml(pInitials)}</div>
            <div class="patient-profile-name">${escapeHtml(patient.name)}</div>
            <div class="patient-profile-pid">${escapeHtml(patient.patient_id)}</div>
          </div>

          <div class="profile-meta-list">
            <div class="profile-meta-row">
              <span>Age / Gender</span>
              <strong>${patient.age} yrs · ${escapeHtml(patient.gender || "Unspecified")}</strong>
            </div>
            <div class="profile-meta-row">
              <span>Blood Group</span>
              <strong style="color:var(--cyan);">${escapeHtml(patient.blood_group || "Not provided")}</strong>
            </div>
            <div class="profile-meta-row">
              <span>Contact Phone</span>
              <strong>${escapeHtml(patient.phone || "—")}</strong>
            </div>
            <div class="profile-meta-row">
              <span>Email Address</span>
              <strong>${escapeHtml(patient.email || "—")}</strong>
            </div>
            <div class="profile-meta-row">
              <span>Emergency Contact</span>
              <strong>${escapeHtml(patient.emergency_contact || "—")}</strong>
            </div>
            <div class="profile-meta-row">
              <span>Address</span>
              <strong>${escapeHtml(patient.address || "—")}</strong>
            </div>
          </div>

          <!-- Chronic Conditions -->
          <div class="profile-section">
            <div class="profile-section-title">Chronic Conditions</div>
            <div class="patient-tags">
              ${
                (patient.chronic_conditions || []).length
                  ? patient.chronic_conditions.map((c) => `<span class="tag tag-amber">${escapeHtml(c)}</span>`).join("")
                  : `<span class="tag">None recorded</span>`
              }
            </div>
          </div>

          <!-- Allergies -->
          <div class="profile-section">
            <div class="profile-section-title">Allergies & Sensitivities</div>
            <div class="patient-tags">
              ${
                (patient.allergies || []).length
                  ? patient.allergies.map((a) => `<span class="tag tag-rose">⚠️ ${escapeHtml(a)}</span>`).join("")
                  : `<span class="tag">No known allergies</span>`
              }
            </div>
          </div>

          <!-- Current Medications -->
          <div class="profile-section">
            <div class="profile-section-title">Active Medications</div>
            <div class="patient-tags">
              ${
                (patient.current_medications || []).length
                  ? patient.current_medications.map((m) => `<span class="tag tag-violet">💊 ${escapeHtml(m)}</span>`).join("")
                  : `<span class="tag">None</span>`
              }
            </div>
          </div>

          ${
            patient.notes
              ? `
            <div class="profile-section">
              <div class="profile-section-title">Clinician Remarks</div>
              <p style="font-size:12px;color:var(--text-subtle);line-height:1.6;margin:0;">
                ${escapeHtml(patient.notes)}
              </p>
            </div>
          `
              : ""
          }

          <div class="danger-zone">
            <button class="btn btn-danger btn-sm btn-wide" id="btn-delete-patient" type="button">
              ${icons.trash}
              <span>Delete Patient Record</span>
            </button>
          </div>
        </aside>

        <!-- Medical Checkup Visits Timeline -->
        <section class="visits-section">
          <div class="visits-header">
            <h3>Medical Checkup Records (${visits.length})</h3>
            <span class="mono" style="font-size:11px;color:var(--text-muted);">Encrypted Mongo Vault</span>
          </div>

          ${
            visits.length
              ? `
            <div class="visit-list">
              ${visits
                .map((v) => `
                <article class="visit-card">
                  <div class="visit-card-top">
                    <div class="visit-date">
                      ${icons.calendar}
                      <span>Date: ${escapeHtml(v.visit_date)}</span>
                    </div>
                    ${
                      v.next_followup
                        ? `<span class="tag tag-cyan">Next Follow-up: ${escapeHtml(v.next_followup)}</span>`
                        : ""
                    }
                  </div>

                  ${v.chief_complaint ? `<h4 class="visit-complaint">${escapeHtml(v.chief_complaint)}</h4>` : ""}
                  ${v.diagnosis ? `<div class="visit-diagnosis">Diagnosis: ${escapeHtml(v.diagnosis)}</div>` : ""}

                  <div class="vitals-grid">
                    ${
                      v.systolic_bp && v.diastolic_bp
                        ? `<div class="vital-chip"><small>Blood Pressure</small><strong>${v.systolic_bp}/${v.diastolic_bp} mmHg</strong></div>`
                        : ""
                    }
                    ${
                      v.fasting_glucose
                        ? `<div class="vital-chip"><small>Fasting Glucose</small><strong>${v.fasting_glucose} mg/dL</strong></div>`
                        : ""
                    }
                    ${
                      v.heart_rate
                        ? `<div class="vital-chip"><small>Heart Rate</small><strong>${v.heart_rate} bpm</strong></div>`
                        : ""
                    }
                    ${
                      v.temperature
                        ? `<div class="vital-chip"><small>Body Temp</small><strong>${v.temperature} °C</strong></div>`
                        : ""
                    }
                    ${
                      v.weight_kg
                        ? `<div class="vital-chip"><small>Weight</small><strong>${v.weight_kg} kg</strong></div>`
                        : ""
                    }
                  </div>

                  ${
                    (v.prescriptions || []).length
                      ? `
                    <div style="margin-top:10px;">
                      <span class="eyebrow">PRESCRIBED REGIMEN:</span>
                      <div class="rx-list">
                        ${v.prescriptions.map((rx) => `<span class="rx-item">💊 ${escapeHtml(rx)}</span>`).join("")}
                      </div>
                    </div>
                  `
                      : ""
                  }

                  ${
                    v.clinical_notes
                      ? `
                    <div class="clinical-notes">
                      "${escapeHtml(v.clinical_notes)}"
                    </div>
                  `
                      : ""
                  }
                </article>
              `)
                .join("")}
            </div>
          `
              : `
            <div class="empty-state">
              <div class="empty-icon">${icons.chart}</div>
              <h3>No medical records yet</h3>
              <p>Record symptoms, blood pressure, fasting glucose, and prescriptions for this patient.</p>
              <button class="btn btn-primary" id="btn-empty-add-visit" type="button">
                ${icons.plus}
                <span>Add First Checkup</span>
              </button>
            </div>
          `
          }
        </section>
      </div>
    `;

    renderShell(contentHtml);

    document.querySelector("#btn-back-patients")?.addEventListener("click", () => navigate("patients"));
    document.querySelector("#btn-edit-patient")?.addEventListener("click", () => openPatientModal(patient));
    document.querySelector("#btn-add-visit")?.addEventListener("click", () => openVisitModal(patient.patient_id));
    document.querySelector("#btn-empty-add-visit")?.addEventListener("click", () => openVisitModal(patient.patient_id));

    document.querySelector("#btn-delete-patient")?.addEventListener("click", async () => {
      const confirmed = window.confirm(
        `Are you sure you want to permanently delete patient "${patient.name}" and all historical visit records?`
      );
      if (!confirmed) return;

      try {
        await request(`/patients/${patient.patient_id}`, { method: "DELETE" });
        showToast("Patient record successfully removed.");
        navigate("patients");
      } catch (err) {
        showToast(err.message, "error");
      }
    });
  }

  // ==========================================
  // PATIENT MODAL (CREATE / EDIT)
  // ==========================================
  function openPatientModal(existing = null) {
    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop";
    backdrop.innerHTML = `
      <div class="modal-dialog modal-lg">
        <div class="modal-header">
          <h3>${existing ? "Modify Patient Data" : "Register New Patient"}</h3>
          <button class="modal-close" id="modal-close-btn" type="button">&times;</button>
        </div>
        <form id="modal-patient-form">
          <div class="modal-body form-stack">
            <div class="form-grid">
              ${renderField("Full Patient Name *", "name", "text", existing?.name || "", "required placeholder='John Doe'")}
              ${renderField("Patient ID (auto-generated if empty)", "patient_id", "text", existing?.patient_id || "", "placeholder='PAT-2024-001'")}
            </div>

            <div class="form-grid-3">
              ${renderField("Age *", "age", "number", existing?.age ?? "", "min='0' max='150' required placeholder='45'")}
              <div class="field">
                <label class="field-label" for="fld-gender">Gender</label>
                <select id="fld-gender" name="gender">
                  <option value="Female" ${existing?.gender === "Female" ? "selected" : ""}>Female</option>
                  <option value="Male" ${existing?.gender === "Male" ? "selected" : ""}>Male</option>
                  <option value="Other" ${existing?.gender === "Other" ? "selected" : ""}>Other</option>
                  <option value="Unspecified" ${!existing || existing?.gender === "Unspecified" ? "selected" : ""}>Unspecified</option>
                </select>
              </div>
              <div class="field">
                <label class="field-label" for="fld-blood_group">Blood Group</label>
                <select id="fld-blood_group" name="blood_group">
                  <option value="">Not Known</option>
                  ${["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
                    .map((bg) => `<option value="${bg}" ${existing?.blood_group === bg ? "selected" : ""}>${bg}</option>`)
                    .join("")}
                </select>
              </div>
            </div>

            <div class="form-grid">
              ${renderField("Phone Number", "phone", "tel", existing?.phone || "", "placeholder='+1 (555) 000-0000'")}
              ${renderField("Email Address", "email", "email", existing?.email || "", "placeholder='patient@example.com'")}
            </div>

            <div class="form-grid">
              ${renderField("Emergency Contact", "emergency_contact", "text", existing?.emergency_contact || "", "placeholder='Name & Phone number'")}
              ${renderField("Residential Address", "address", "text", existing?.address || "", "placeholder='City, State'")}
            </div>

            ${renderField(
              "Chronic Conditions (comma separated)",
              "chronic_conditions",
              "text",
              (existing?.chronic_conditions || []).join(", "),
              "placeholder='Hypertension, Type 2 Diabetes, Asthma'"
            )}

            ${renderField(
              "Allergies (comma separated)",
              "allergies",
              "text",
              (existing?.allergies || []).join(", "),
              "placeholder='Penicillin, Sulfa drugs, Peanuts'"
            )}

            ${renderField(
              "Current Medications (comma separated)",
              "current_medications",
              "text",
              (existing?.current_medications || []).join(", "),
              "placeholder='Metformin 500mg, Lisinopril 10mg'"
            )}

            <div class="field">
              <label class="field-label" for="fld-notes">General Clinical Notes</label>
              <textarea id="fld-notes" name="notes" placeholder="Family history, lifestyle notes, risk factors">${escapeHtml(existing?.notes || "")}</textarea>
            </div>
          </div>

          <div class="modal-footer">
            <button class="btn btn-ghost" type="button" id="modal-cancel-btn">Cancel</button>
            <button class="btn btn-primary" type="submit" id="modal-submit-btn">
              ${existing ? "Save Modifications" : "Register Patient"}
            </button>
          </div>
        </form>
      </div>
    `;

    document.body.appendChild(backdrop);

    const closeModal = () => {
      backdrop.remove();
      document.removeEventListener("keydown", onKeyDown);
    };

    const onKeyDown = (e) => {
      if (e.key === "Escape") closeModal();
    };
    document.addEventListener("keydown", onKeyDown);

    backdrop.querySelector("#modal-close-btn").addEventListener("click", closeModal);
    backdrop.querySelector("#modal-cancel-btn").addEventListener("click", closeModal);
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) closeModal();
    });

    const form = backdrop.querySelector("#modal-patient-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());

      if (!raw.name?.trim()) return showToast("Patient name is required.", "error");
      if (!raw.age || Number(raw.age) < 0) return showToast("A valid age is required.", "error");

      const payload = {
        patient_id: raw.patient_id?.trim() || null,
        name: raw.name.trim(),
        age: Number(raw.age),
        gender: raw.gender,
        blood_group: raw.blood_group || null,
        phone: raw.phone?.trim() || "",
        email: raw.email?.trim() || "",
        address: raw.address?.trim() || "",
        emergency_contact: raw.emergency_contact?.trim() || "",
        chronic_conditions: (raw.chronic_conditions || "").split(",").map((s) => s.trim()).filter(Boolean),
        allergies: (raw.allergies || "").split(",").map((s) => s.trim()).filter(Boolean),
        current_medications: (raw.current_medications || "").split(",").map((s) => s.trim()).filter(Boolean),
        notes: raw.notes?.trim() || "",
      };

      const submitBtn = backdrop.querySelector("#modal-submit-btn");
      submitBtn.disabled = true;

      try {
        if (existing) {
          await request(`/patients/${existing.patient_id}`, {
            method: "PUT",
            body: JSON.stringify(payload),
          });
          showToast("Patient updated successfully.");
          closeModal();
          renderPatientDetail(payload.patient_id || existing.patient_id);
        } else {
          const created = await request("/patients", {
            method: "POST",
            body: JSON.stringify(payload),
          });
          showToast("Patient registered successfully.");
          closeModal();
          renderPatientDetail(created.patient_id);
        }
      } catch (err) {
        showToast(err.message, "error");
        submitBtn.disabled = false;
      }
    });
  }

  // ==========================================
  // VISIT MODAL (ADD MEDICAL CHECKUP)
  // ==========================================
  function openVisitModal(patientId) {
    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop";
    const todayIso = new Date().toISOString().substring(0, 10);

    backdrop.innerHTML = `
      <div class="modal-dialog modal-lg">
        <div class="modal-header">
          <h3>Add Medical Checkup / Record</h3>
          <button class="modal-close" id="modal-close-btn" type="button">&times;</button>
        </div>
        <form id="modal-visit-form">
          <div class="modal-body form-stack">
            <div class="form-grid">
              ${renderField("Visit Date *", "visit_date", "date", todayIso, "required")}
              ${renderField("Next Follow-up Date", "next_followup", "date", "")}
            </div>

            ${renderField("Chief Complaint / Symptoms *", "chief_complaint", "text", "", "required placeholder='e.g. Severe migraine, elevated BP, fatigue'")}
            ${renderField("Diagnosis / Clinical Assessment", "diagnosis", "text", "", "placeholder='e.g. Essential Hypertension, Acute Sinusitis'")}

            <div class="form-grid">
              ${renderField("Systolic BP (mmHg)", "systolic_bp", "number", "", "min='30' max='300' placeholder='120'")}
              ${renderField("Diastolic BP (mmHg)", "diastolic_bp", "number", "", "min='20' max='200' placeholder='80'")}
            </div>

            <div class="form-grid">
              ${renderField("Fasting Glucose (mg/dL)", "fasting_glucose", "number", "", "min='10' max='1000' step='0.1' placeholder='95.5'")}
              ${renderField("Heart Rate (bpm)", "heart_rate", "number", "", "min='20' max='250' placeholder='72'")}
            </div>

            <div class="form-grid">
              ${renderField("Temperature (°C)", "temperature", "number", "", "min='25' max='45' step='0.1' placeholder='36.6'")}
              ${renderField("Weight (kg)", "weight_kg", "number", "", "min='1' max='400' step='0.1' placeholder='70'")}
            </div>

            ${renderField(
              "Prescriptions (comma separated)",
              "prescriptions",
              "text",
              "",
              "placeholder='Amlodipine 5mg OD, Paracetamol 500mg SOS'"
            )}

            <div class="field">
              <label class="field-label" for="fld-clinical_notes">Clinical Notes & Physician Advice</label>
              <textarea id="fld-clinical_notes" name="clinical_notes" placeholder="Diet advice, test orders, ultrasound findings..."></textarea>
            </div>
          </div>

          <div class="modal-footer">
            <button class="btn btn-ghost" type="button" id="modal-cancel-btn">Cancel</button>
            <button class="btn btn-primary" type="submit" id="modal-submit-btn">Save Medical Record</button>
          </div>
        </form>
      </div>
    `;

    document.body.appendChild(backdrop);

    const closeModal = () => {
      backdrop.remove();
      document.removeEventListener("keydown", onKeyDown);
    };

    const onKeyDown = (e) => {
      if (e.key === "Escape") closeModal();
    };
    document.addEventListener("keydown", onKeyDown);

    backdrop.querySelector("#modal-close-btn").addEventListener("click", closeModal);
    backdrop.querySelector("#modal-cancel-btn").addEventListener("click", closeModal);
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) closeModal();
    });

    const form = backdrop.querySelector("#modal-visit-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());

      if (!raw.visit_date) return showToast("Visit date is required.", "error");
      if (!raw.chief_complaint?.trim()) return showToast("Chief complaint is required.", "error");

      const payload = {
        visit_date: raw.visit_date,
        chief_complaint: raw.chief_complaint.trim(),
        diagnosis: raw.diagnosis?.trim() || "",
        systolic_bp: raw.systolic_bp ? Number(raw.systolic_bp) : null,
        diastolic_bp: raw.diastolic_bp ? Number(raw.diastolic_bp) : null,
        fasting_glucose: raw.fasting_glucose ? Number(raw.fasting_glucose) : null,
        heart_rate: raw.heart_rate ? Number(raw.heart_rate) : null,
        temperature: raw.temperature ? Number(raw.temperature) : null,
        weight_kg: raw.weight_kg ? Number(raw.weight_kg) : null,
        prescriptions: (raw.prescriptions || "").split(",").map((s) => s.trim()).filter(Boolean),
        clinical_notes: raw.clinical_notes?.trim() || "",
        next_followup: raw.next_followup || null,
      };

      const submitBtn = backdrop.querySelector("#modal-submit-btn");
      submitBtn.disabled = true;

      try {
        await request(`/patients/${patientId}/visits`, {
          method: "POST",
          body: JSON.stringify(payload),
        });
        showToast("Medical visit recorded successfully.");
        closeModal();
        renderPatientDetail(patientId);
      } catch (err) {
        showToast(err.message, "error");
        submitBtn.disabled = false;
      }
    });
  }

  // ==========================================
  // DASHBOARD / OVERVIEW VIEW
  // ==========================================
  async function renderOverview() {
    let data = {};
    try {
      data = await request("/dashboard");
    } catch (err) {
      showToast(err.message, "error");
    }

    currentProfile = data.profile || {};
    const latest = data.latest_measurement || {};
    const readings = data.measurements || [];
    const hasTrendReadings = readings.some((reading) =>
      reading.fasting_glucose != null || reading.systolic_bp != null || reading.diastolic_bp != null
    );
    const reminders = data.reminders || [];
    const patientsCount = data.patients_count || 0;

    const steps = latest.steps != null ? Number(latest.steps).toLocaleString() : "—";
    const activeMin = latest.active_minutes != null ? `${latest.active_minutes} min` : "—";
    const sleep = latest.sleep_hours != null ? `${latest.sleep_hours} hrs` : "—";
    const bmi = currentProfile.bmi != null ? currentProfile.bmi : "—";

    const contentHtml = `
      <section class="page-heading">
        <div>
          <span class="eyebrow">${icons.sparkle} YOUR HEALTH WORKSPACE</span>
          <h1>Welcome, ${escapeHtml(currentUser?.name || data.name || "there")}</h1>
          <p>Your personal check-ins, daily reminders, and patient notes, together in one place.</p>
        </div>
        <div class="page-heading-actions">
          <button class="btn btn-secondary" data-page="patients" type="button">
            ${icons.patients}
            <span>Patient records</span>
          </button>
          <button class="btn btn-primary" data-page="measurements" type="button">
            ${icons.plus}
            <span>Log a check-in</span>
          </button>
        </div>
      </section>

      <!-- Metric Cards Grid -->
      <div class="metric-grid">
        <div class="metric-card mc-cyan">
          <div class="metric-top">
            <span class="metric-label">DAILY STEPS</span>
            <div class="metric-icon cyan">${icons.chart}</div>
          </div>
          <div class="metric-value">${steps}</div>
          <div class="metric-sub">${latest.steps != null ? "From your latest check-in" : "No recent entry"}</div>
          <div class="metric-bar">
            <div class="metric-bar-fill" style="width:${latest.steps ? Math.min(100, (latest.steps / 10000) * 100) : 0}%;background:var(--cyan);"></div>
          </div>
        </div>

        <div class="metric-card mc-emerald">
          <div class="metric-top">
            <span class="metric-label">ACTIVE TIME</span>
            <div class="metric-icon emerald">${icons.pulse}</div>
          </div>
          <div class="metric-value">${activeMin}</div>
          <div class="metric-sub">${latest.active_minutes != null ? "From your latest check-in" : "No recent entry"}</div>
          <div class="metric-bar">
            <div class="metric-bar-fill" style="width:${latest.active_minutes ? Math.min(100, (latest.active_minutes / 60) * 100) : 0}%;background:var(--emerald);"></div>
          </div>
        </div>

        <div class="metric-card mc-violet">
          <div class="metric-top">
            <span class="metric-label">SLEEP LOGGED</span>
            <div class="metric-icon violet">${icons.calendar}</div>
          </div>
          <div class="metric-value">${sleep}</div>
          <div class="metric-sub">${latest.sleep_hours != null ? "From your latest check-in" : "No recent entry"}</div>
          <div class="metric-bar">
            <div class="metric-bar-fill" style="width:${latest.sleep_hours ? Math.min(100, (latest.sleep_hours / 8) * 100) : 0}%;background:var(--violet);"></div>
          </div>
        </div>

        <div class="metric-card mc-amber">
          <div class="metric-top">
            <span class="metric-label">BMI</span>
            <div class="metric-icon amber">${icons.user}</div>
          </div>
          <div class="metric-value">${bmi}</div>
          <div class="metric-sub">${currentProfile.bmi != null ? "Calculated from height & weight" : "Update profile measurements"}</div>
          <div class="metric-bar">
            <div class="metric-bar-fill" style="width:${currentProfile.bmi ? Math.min(100, (currentProfile.bmi / 30) * 100) : 0}%;background:var(--amber);"></div>
          </div>
        </div>
      </div>

      <!-- Patient records quick link -->
      <div class="patient-banner">
        <div class="patient-banner-text">
          <h3>${patientsCount} patient record${patientsCount === 1 ? "" : "s"}</h3>
          <p>Add a patient profile or review the visit notes and follow-up dates you have saved.</p>
        </div>
        <button class="btn btn-primary" data-page="patients" type="button">
          <span>Manage Patients</span>
          ${icons.arrow}
        </button>
      </div>

      <!-- Main Overview 2-Column Grid -->
      <div class="overview-grid">
        <!-- Interactive Chart & History Panel -->
        <div class="card">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;">
            <div>
              <span class="eyebrow">TREND ANALYSIS</span>
              <h2 style="font-size:16px;font-weight:700;margin-top:2px;">Health readings over time</h2>
            </div>
            <button class="text-btn" data-page="measurements" type="button">
              <span>Full Vitals Log</span> ${icons.arrow}
            </button>
          </div>

          <p class="chart-caption">Glucose and blood pressure use separate axes because they have different units.</p>
          ${hasTrendReadings
            ? `<div style="height:240px;position:relative;"><canvas id="overview-chart"></canvas></div>`
            : `<div class="chart-empty">Your trend will appear after a check-in with glucose or blood pressure readings.</div>`}

          <div style="margin-top:24px;">
            <div style="font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--text-muted);margin-bottom:10px;">
              Recent Check-ins
            </div>
            ${
              readings.length
                ? `
              <table class="readings-table">
                <thead>
                  <tr>
                    <th>Recorded On</th>
                    <th>Fasting Glucose</th>
                    <th>Blood Pressure</th>
                    <th>Steps</th>
                  </tr>
                </thead>
                <tbody>
                  ${readings
                    .slice(0, 5)
                    .map((r) => {
                      const dt = new Date(r.recorded_at).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      });
                      const gl = r.fasting_glucose != null ? `${r.fasting_glucose} mg/dL` : "—";
                      const bp =
                        r.systolic_bp != null && r.diastolic_bp != null
                          ? `${r.systolic_bp}/${r.diastolic_bp} mmHg`
                          : r.systolic_bp ?? r.diastolic_bp ?? "—";
                      const st = r.steps != null ? r.steps.toLocaleString() : "—";
                      return `
                        <tr>
                          <td><strong>${dt}</strong></td>
                          <td><span style="color:var(--cyan);font-weight:600;">${gl}</span></td>
                          <td><span style="color:var(--emerald-l);font-weight:600;">${bp}</span></td>
                          <td>${st}</td>
                        </tr>
                      `;
                    })
                    .join("")}
                </tbody>
              </table>
            `
                : `
              <div class="empty-state" style="padding:30px 0;">
                <p>No check-in entries found. Log your first readings in Daily Vitals.</p>
                <button class="btn btn-secondary btn-sm" data-page="measurements" type="button">
                  ${icons.plus} <span>Log Vitals</span>
                </button>
              </div>
            `
            }
          </div>
        </div>

        <!-- Reminders & Schedule Panel -->
        <div class="card">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;">
            <div>
              <span class="eyebrow">DAILY REGIMEN</span>
              <h2 style="font-size:16px;font-weight:700;margin-top:2px;">Today's Schedule</h2>
            </div>
            <button class="btn btn-secondary btn-sm" data-page="reminders" type="button">
              ${icons.plus}
            </button>
          </div>

          ${
            reminders.length
              ? `
            <div class="reminders-list">
              ${reminders
                .slice(0, 6)
                .map(
                  (rem) => `
                <div class="reminder-item">
                  <button class="reminder-check ${rem.completed_today ? "done" : ""}" data-complete-id="${rem.id}" ${rem.completed_today ? "disabled" : ""} type="button">
                    ${icons.check}
                  </button>
                  <div class="reminder-info">
                    <div class="reminder-title">${escapeHtml(rem.title)}</div>
                    <div class="reminder-note">${escapeHtml(rem.instruction || "Scheduled reminder")}</div>
                  </div>
                  <div class="reminder-time">${escapeHtml(rem.scheduled_time)}</div>
                </div>
              `
                )
                .join("")}
            </div>
          `
              : `
            <div class="empty-state" style="padding:40px 0;">
              <div class="empty-icon">${icons.bell}</div>
              <h3>No reminders active</h3>
              <p>Add a reminder for a routine, meal, or medication schedule.</p>
              <button class="btn btn-secondary btn-sm" data-page="reminders" type="button">
                ${icons.plus} <span>Add Reminder</span>
              </button>
            </div>
          `
          }
        </div>
      </div>
    `;

    renderShell(contentHtml);

    // Render Chart.js
    if (window.Chart && hasTrendReadings) {
      const reversed = [...readings].reverse().slice(-10);
      const labels = reversed.map((r) =>
        new Date(r.recorded_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })
      );
      const glucoseData = reversed.map((r) => r.fasting_glucose);
      const systolicData = reversed.map((r) => r.systolic_bp);
      const diastolicData = reversed.map((r) => r.diastolic_bp);
      const canvas = document.querySelector("#overview-chart");

      if (canvas) {
        const ctx = canvas.getContext("2d");
        destroyCurrentChart();
        activeChart = new window.Chart(ctx, {
          type: "line",
          data: {
            labels,
            datasets: [
              {
                label: "Fasting Glucose (mg/dL)",
                data: glucoseData,
                yAxisID: "glucose",
                borderColor: "#06b6d4",
                backgroundColor: "rgba(6, 182, 212, 0.12)",
                fill: true,
                tension: 0.35,
                pointBackgroundColor: "#06b6d4",
                pointRadius: 4,
              },
              {
                label: "Systolic BP (mmHg)",
                data: systolicData,
                yAxisID: "pressure",
                borderColor: "#10b981",
                backgroundColor: "rgba(16, 185, 129, 0.08)",
                fill: true,
                tension: 0.35,
                pointBackgroundColor: "#10b981",
                pointRadius: 4,
              },
              {
                label: "Diastolic BP (mmHg)",
                data: diastolicData,
                yAxisID: "pressure",
                borderColor: "#8b5cf6",
                backgroundColor: "rgba(139, 92, 246, 0.08)",
                fill: false,
                tension: 0.35,
                pointBackgroundColor: "#8b5cf6",
                pointRadius: 4,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: {
                labels: { color: "#94a3b8", font: { family: "Inter", size: 11 } },
              },
            },
            scales: {
              x: {
                grid: { color: "rgba(255, 255, 255, 0.05)" },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
              glucose: {
                type: "linear",
                position: "left",
                title: { display: true, text: "Glucose (mg/dL)", color: "#94a3b8" },
                grid: { color: "rgba(255, 255, 255, 0.05)" },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
              pressure: {
                type: "linear",
                position: "right",
                title: { display: true, text: "Blood pressure (mmHg)", color: "#94a3b8" },
                grid: { drawOnChartArea: false },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
            },
          },
        });
      }
    }

    // Complete reminder button listener
    document.querySelectorAll("[data-complete-id]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.completeId;
        try {
          await request(`/reminders/${id}/complete`, { method: "POST" });
          showToast("Reminder marked complete!");
          renderOverview();
        } catch (err) {
          showToast(err.message, "error");
        }
      });
    });
  }

  // ==========================================
  // DAILY VITALS & MEASUREMENTS VIEW
  // ==========================================
  async function renderMeasurements() {
    let data = {};
    try {
      data = await request("/dashboard");
    } catch (err) {
      showToast(err.message, "error");
    }

    const readings = data.measurements || [];
    const hasTrendReadings = readings.some((reading) =>
      reading.fasting_glucose != null || reading.systolic_bp != null || reading.diastolic_bp != null
    );

    const contentHtml = `
      <section class="page-heading">
        <div>
          <span class="eyebrow">${icons.chart} PERSONAL HEALTH LOG</span>
          <h1>Daily Health Check-ins</h1>
          <p>Record personal measurements, activity, and sleep over time. Use your clinician’s guidance to interpret readings.</p>
        </div>
      </section>

      <div class="health-layout">
        <div>
          <!-- Entry Form Card -->
          <div class="card">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;">
              <div>
                <span class="eyebrow">NEW MEASUREMENT</span>
                <h2 style="font-size:16px;font-weight:700;margin-top:2px;">New check-in</h2>
              </div>
              <span class="mono" style="font-size:12px;color:var(--cyan);">${new Date().toLocaleDateString(undefined, {
                month: "short",
                day: "numeric",
              })}</span>
            </div>

            <form id="vitals-entry-form" class="form-stack">
              <div class="form-grid">
                ${renderField("Daily Steps", "steps", "number", "", "min='0' max='200000' placeholder='e.g. 7500'")}
                ${renderField("Active Minutes", "active_minutes", "number", "", "min='0' max='1440' placeholder='e.g. 45'")}
              </div>

              <div class="form-grid">
                ${renderField("Sleep Hours", "sleep_hours", "number", "", "min='0' max='24' step='0.1' placeholder='e.g. 7.5'")}
                ${renderField("Fasting Glucose (mg/dL)", "fasting_glucose", "number", "", "min='20' max='1000' step='0.1' placeholder='e.g. 92'")}
              </div>

              <div class="form-grid">
                ${renderField("Systolic Pressure (mmHg)", "systolic_bp", "number", "", "min='50' max='300' placeholder='e.g. 118'")}
                ${renderField("Diastolic Pressure (mmHg)", "diastolic_bp", "number", "", "min='30' max='200' placeholder='e.g. 76'")}
              </div>

              <button class="btn btn-primary" type="submit" id="btn-save-vitals" style="margin-top:8px;">
                <span>Save Vitals Entry</span>
                ${icons.arrow}
              </button>
            </form>
          </div>

          <!-- Interactive Trend Chart -->
          <div class="chart-wrapper">
            <div class="chart-title">Your recorded trends</div>
            <p class="chart-caption">Glucose and blood pressure use separate axes because they have different units.</p>
            ${hasTrendReadings
              ? `<div style="height:250px;position:relative;"><canvas id="vitals-trend-chart"></canvas></div>`
              : `<div class="chart-empty">Add glucose or blood pressure to a check-in to see a trend here.</div>`}
          </div>

          <!-- History Table -->
          <div class="card" style="margin-top:20px;">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;">
              <h3 style="font-size:15px;font-weight:700;">Recorded Entries History</h3>
              <span class="mono" style="font-size:11px;color:var(--text-muted);">${readings.length} total entries</span>
            </div>

            ${
              readings.length
                ? `
              <div style="overflow-x:auto;">
                <table class="history-table">
                  <thead>
                    <tr>
                      <th>Timestamp</th>
                      <th>Steps</th>
                      <th>Active Time</th>
                      <th>Sleep</th>
                      <th>Glucose</th>
                      <th>Blood Pressure</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${readings
                      .map((r) => `
                      <tr>
                        <td><strong>${new Date(r.recorded_at).toLocaleString(undefined, {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}</strong></td>
                        <td>${r.steps != null ? r.steps.toLocaleString() : "—"}</td>
                        <td>${r.active_minutes != null ? `${r.active_minutes} min` : "—"}</td>
                        <td>${r.sleep_hours != null ? `${r.sleep_hours} hrs` : "—"}</td>
                        <td><span style="color:var(--cyan);font-weight:600;">${r.fasting_glucose != null ? `${r.fasting_glucose} mg/dL` : "—"}</span></td>
                        <td><span style="color:var(--emerald-l);font-weight:600;">${
                          r.systolic_bp != null && r.diastolic_bp != null
                            ? `${r.systolic_bp}/${r.diastolic_bp} mmHg`
                            : r.systolic_bp ?? r.diastolic_bp ?? "—"
                        }</span></td>
                      </tr>
                    `)
                      .join("")}
                  </tbody>
                </table>
              </div>
            `
                : `
              <div class="empty-state" style="padding:30px 0;">
                <p>No check-in entries logged yet. Fill out the form above to record your first entry.</p>
              </div>
            `
            }
          </div>
        </div>

        <!-- Prototype and interpretation note -->
        <aside>
          <div class="card" style="background:linear-gradient(135deg, rgba(6,182,212,0.06), rgba(20,184,166,0.04));border-color:rgba(6,182,212,0.18);">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:12px;">
              <div style="width:32px;height:32px;border-radius:8px;background:var(--cyan-dim);color:var(--cyan);display:flex;align-items:center;justify-content:center;">
                ${icons.shield}
              </div>
              <span style="font-weight:700;font-size:14px;">A note about this log</span>
            </div>
            <p style="font-size:12px;color:var(--text-subtle);line-height:1.7;margin-bottom:14px;">
              Beluga stores the measurements you enter but does not interpret readings or recommend care. Use synthetic data in this prototype, and follow your clinician’s guidance.
            </p>
          </div>
        </aside>
      </div>
    `;

    renderShell(contentHtml);

    // Render Trend Chart
    if (window.Chart && hasTrendReadings) {
      const reversed = [...readings].reverse().slice(-14);
      const labels = reversed.map((r) =>
        new Date(r.recorded_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })
      );
      const glucoseData = reversed.map((r) => r.fasting_glucose);
      const systolicData = reversed.map((r) => r.systolic_bp);
      const diastolicData = reversed.map((r) => r.diastolic_bp);
      const canvas = document.querySelector("#vitals-trend-chart");

      if (canvas) {
        const ctx = canvas.getContext("2d");
        destroyCurrentChart();
        activeChart = new window.Chart(ctx, {
          type: "line",
          data: {
            labels,
            datasets: [
              {
                label: "Fasting Glucose",
                data: glucoseData,
                yAxisID: "glucose",
                borderColor: "#06b6d4",
                backgroundColor: "rgba(6, 182, 212, 0.1)",
                tension: 0.3,
                pointRadius: 4,
              },
              {
                label: "Systolic BP",
                data: systolicData,
                yAxisID: "pressure",
                borderColor: "#10b981",
                backgroundColor: "rgba(16, 185, 129, 0.1)",
                tension: 0.3,
                pointRadius: 4,
              },
              {
                label: "Diastolic BP",
                data: diastolicData,
                yAxisID: "pressure",
                borderColor: "#8b5cf6",
                backgroundColor: "rgba(139, 92, 246, 0.1)",
                tension: 0.3,
                pointRadius: 4,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { labels: { color: "#94a3b8", font: { family: "Inter", size: 11 } } },
            },
            scales: {
              x: {
                grid: { color: "rgba(255, 255, 255, 0.05)" },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
              glucose: {
                type: "linear",
                position: "left",
                title: { display: true, text: "Glucose (mg/dL)", color: "#94a3b8" },
                grid: { color: "rgba(255, 255, 255, 0.05)" },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
              pressure: {
                type: "linear",
                position: "right",
                title: { display: true, text: "Blood pressure (mmHg)", color: "#94a3b8" },
                grid: { drawOnChartArea: false },
                ticks: { color: "#94a3b8", font: { family: "Inter", size: 10 } },
              },
            },
          },
        });
      }
    }

    // Submit form handler
    const form = document.querySelector("#vitals-entry-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());
      const payload = {};

      for (const [key, val] of Object.entries(raw)) {
        if (val !== "") {
          payload[key] = Number(val);
        }
      }

      if (!Object.keys(payload).length) {
        return showToast("Please enter at least one measurement.", "error");
      }

      const submitBtn = document.querySelector("#btn-save-vitals");
      submitBtn.disabled = true;

      try {
        await request("/measurements", {
          method: "POST",
          body: JSON.stringify(payload),
        });
        showToast("Vitals entry saved successfully!");
        renderMeasurements();
      } catch (err) {
        showToast(err.message, "error");
        submitBtn.disabled = false;
      }
    });
  }

  // ==========================================
  // REMINDERS & NOTIFICATIONS VIEW
  // ==========================================
  async function renderReminders() {
    let reminders = [];
    try {
      reminders = await request("/reminders");
    } catch (err) {
      showToast(err.message, "error");
    }

    const contentHtml = `
      <section class="page-heading">
        <div>
          <span class="eyebrow">${icons.bell} SCHEDULE & REMINDERS</span>
          <h1>Clinical & Medication Routine</h1>
          <p>Organize recurring clinical check-ins, medication intake reminders, and daily habits.</p>
        </div>
      </section>

      <div class="reminder-layout">
        <!-- Reminders List -->
        <div class="card">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;">
            <div>
              <span class="eyebrow">ACTIVE ROUTINE</span>
              <h2 style="font-size:16px;font-weight:700;margin-top:2px;">Scheduled Reminders (${reminders.length})</h2>
            </div>
          </div>

          ${
            reminders.length
              ? `
            <div class="reminders-list">
              ${reminders
                .map(
                  (item) => `
                <div class="reminder-item">
                  <div class="reminder-time">${escapeHtml(item.scheduled_time)}</div>
                  <div class="reminder-info">
                    <div class="reminder-title">${escapeHtml(item.title)}</div>
                    <div class="reminder-note">${escapeHtml(item.instruction || "Clinical reminder")}</div>
                  </div>
                  <button class="reminder-del" data-delete-id="${item.id}" title="Delete reminder" type="button">
                    ${icons.trash}
                  </button>
                </div>
              `
                )
                .join("")}
            </div>
          `
              : `
            <div class="empty-state" style="padding:40px 0;">
              <div class="empty-icon">${icons.bell}</div>
              <h3>No reminders created yet</h3>
              <p>Add a new reminder using the form on the right to keep your daily clinical routine on track.</p>
            </div>
          `
          }
        </div>

        <!-- Add Reminder Form Panel -->
        <div class="card">
          <div style="margin-bottom:18px;">
            <span class="eyebrow">NEW REMINDER</span>
            <h2 style="font-size:16px;font-weight:700;margin-top:2px;">Create Schedule Entry</h2>
          </div>

          <form id="reminder-form" class="form-stack">
            ${renderField("Reminder Title *", "title", "text", "", "required placeholder='e.g. Check Blood Pressure'")}
            ${renderField("Scheduled Time *", "scheduled_time", "time", "08:30", "required")}

            <div class="field">
              <label class="field-label" for="fld-instruction">Instructions / Notes</label>
              <textarea id="fld-instruction" name="instruction" placeholder="Take with food, log in app..."></textarea>
            </div>

            <button class="btn btn-primary btn-wide" type="submit" id="btn-save-reminder" style="margin-top:8px;">
              ${icons.plus}
              <span>Add to Schedule</span>
            </button>
          </form>
        </div>
      </div>
    `;

    renderShell(contentHtml);

    // Form submission
    const form = document.querySelector("#reminder-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());

      if (!raw.title?.trim()) return showToast("Reminder title is required.", "error");
      if (!raw.scheduled_time) return showToast("Time is required.", "error");

      const payload = {
        title: raw.title.trim(),
        scheduled_time: raw.scheduled_time,
        instruction: raw.instruction?.trim() || "",
      };

      const btn = document.querySelector("#btn-save-reminder");
      btn.disabled = true;

      try {
        await request("/reminders", {
          method: "POST",
          body: JSON.stringify(payload),
        });
        showToast("Reminder created successfully!");
        renderReminders();
      } catch (err) {
        showToast(err.message, "error");
        btn.disabled = false;
      }
    });

    // Delete buttons
    document.querySelectorAll("[data-delete-id]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.deleteId;
        try {
          await request(`/reminders/${id}`, { method: "DELETE" });
          showToast("Reminder removed.");
          renderReminders();
        } catch (err) {
          showToast(err.message, "error");
        }
      });
    });
  }

  // ==========================================
  // CLINICIAN / USER PROFILE VIEW
  // ==========================================
  async function renderProfile() {
    let session = {};
    try {
      session = await request("/me");
      currentUser = session.user;
      currentProfile = session.profile || {};
    } catch (err) {
      showToast(err.message, "error");
    }

    const prof = currentProfile || {};
    const initials = (currentUser?.name || "BH")
      .split(/\s+/)
      .filter(Boolean)
      .map((n) => n[0])
      .slice(0, 2)
      .join("")
      .toUpperCase();

    const contentHtml = `
      <section class="page-heading">
        <div>
          <span class="eyebrow">${icons.user} ACCOUNT SETTINGS</span>
          <h1>Practitioner Profile</h1>
          <p>Manage account credentials, clinical identifiers, and biometric defaults.</p>
        </div>
      </section>

      <div class="profile-layout">
        <!-- Edit Profile Form -->
        <div class="card">
          <div style="margin-bottom:20px;">
            <span class="eyebrow">PERSONAL DETAILS</span>
            <h2 style="font-size:16px;font-weight:700;margin-top:2px;">Edit Clinician Information</h2>
          </div>

          <form id="profile-edit-form" class="form-stack">
            <div class="form-grid">
              ${renderField("Full Name *", "name", "text", currentUser?.name || "", "required")}
              ${renderField("Email Address", "email", "email", currentUser?.email || "", "disabled title='Email cannot be changed'")}
            </div>

            <div class="form-grid-3">
              ${renderField("Age", "age", "number", prof.age ?? "", "min='0' max='150' placeholder='Years'")}
              <div class="field">
                <label class="field-label" for="fld-gender">Gender</label>
                <select id="fld-gender" name="gender">
                  <option value="">Prefer not to say</option>
                  ${["Female", "Male", "Non-binary", "Self-describe"]
                    .map((g) => `<option value="${g}" ${prof.gender === g ? "selected" : ""}>${g}</option>`)
                    .join("")}
                </select>
              </div>
              <div class="field">
                <label class="field-label" for="fld-blood_type">Blood Type</label>
                <select id="fld-blood_type" name="blood_type">
                  <option value="">Not provided</option>
                  ${["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
                    .map((b) => `<option value="${b}" ${prof.blood_type === b ? "selected" : ""}>${b}</option>`)
                    .join("")}
                </select>
              </div>
            </div>

            <div class="form-grid">
              ${renderField("Height (cm)", "height_cm", "number", prof.height_cm ?? "", "min='30' max='300' placeholder='175'")}
              ${renderField("Weight (kg)", "weight_kg", "number", prof.weight_kg ?? "", "min='20' max='500' step='0.1' placeholder='72'")}
            </div>

            ${renderField("Location / Clinic", "location", "text", prof.location || "", "placeholder='Beluga Health Center, Floor 4'")}

            <button class="btn btn-primary" type="submit" id="btn-save-profile" style="margin-top:10px;">
              <span>Save Profile Updates</span>
              ${icons.arrow}
            </button>
          </form>
        </div>

        <!-- Profile Presentation Card -->
        <aside class="profile-aside-card">
          <div class="profile-aside-avatar">${escapeHtml(initials)}</div>
          <div class="profile-aside-name">${escapeHtml(currentUser?.name || "Clinician")}</div>
          <div class="profile-aside-email">${escapeHtml(currentUser?.email || "")}</div>
          <div class="profile-aside-badge">${icons.shield} Verified Practitioner</div>

          <div style="margin-top:24px;text-align:left;font-size:12px;display:grid;gap:10px;">
            <div class="profile-meta-row"><span>Calculated BMI:</span><strong style="color:var(--cyan);">${prof.bmi ?? "—"}</strong></div>
            <div class="profile-meta-row"><span>Height:</span><strong>${prof.height_cm ? `${prof.height_cm} cm` : "—"}</strong></div>
            <div class="profile-meta-row"><span>Weight:</span><strong>${prof.weight_kg ? `${prof.weight_kg} kg` : "—"}</strong></div>
            <div class="profile-meta-row"><span>Blood Type:</span><strong>${prof.blood_type || "—"}</strong></div>
          </div>
        </aside>
      </div>
    `;

    renderShell(contentHtml);

    // Profile submit handler
    const form = document.querySelector("#profile-edit-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const raw = Object.fromEntries(new FormData(form).entries());

      if (!raw.name?.trim()) return showToast("Name is required.", "error");

      const payload = {
        name: raw.name.trim(),
        age: raw.age ? Number(raw.age) : null,
        gender: raw.gender || "",
        blood_type: raw.blood_type || "",
        height_cm: raw.height_cm ? Number(raw.height_cm) : null,
        weight_kg: raw.weight_kg ? Number(raw.weight_kg) : null,
        location: raw.location?.trim() || "",
        conditions: prof.conditions || [],
        medications: prof.medications || [],
        appetite: prof.appetite || "",
        daily_routine: prof.daily_routine || "",
        family_history: prof.family_history || "",
        prescriptions: prof.prescriptions || [],
        profile_image: prof.profile_image || "",
      };

      const btn = document.querySelector("#btn-save-profile");
      btn.disabled = true;

      try {
        currentProfile = await request("/profile", {
          method: "PUT",
          body: JSON.stringify(payload),
        });
        if (currentUser) currentUser.name = payload.name;
        showToast("Profile updated successfully!");
        renderProfile();
      } catch (err) {
        showToast(err.message, "error");
        btn.disabled = false;
      }
    });
  }

  // ==========================================
  // ROOT ROUTER & DISPATCHER
  // ==========================================
  async function render() {
    if (!token) {
      return renderAuth();
    }

    try {
      if (!currentUser) {
        const session = await request("/me");
        currentUser = session.user;
        currentProfile = session.profile;
      }

      if (activePage === "patients") {
        await renderPatients();
      } else if (activePage === "patient-detail" && activePatientId) {
        await renderPatientDetail(activePatientId);
      } else if (activePage === "overview") {
        await renderOverview();
      } else if (activePage === "measurements") {
        await renderMeasurements();
      } else if (activePage === "reminders") {
        await renderReminders();
      } else if (activePage === "profile") {
        await renderProfile();
      } else {
        await renderPatients();
      }
    } catch (err) {
      const isConnectionError = /fetch|did not return data/i.test(err.message || "");
      destroyCurrentChart();
      appNode.innerHTML = `
        <section class="offline-state">
          <div class="offline-icon">${icons.alert}</div>
          <h1>${isConnectionError ? "Server Connection Paused" : "Workspace Could Not Load"}</h1>
          <p>${escapeHtml(err.message || "Please try loading your workspace again.")}</p>
          <div style="display:flex;gap:12px;margin-top:10px;">
            <button class="btn btn-primary" id="btn-reconnect" type="button">Try Reconnecting</button>
            <button class="btn btn-secondary" id="btn-offline-signout" type="button">Sign Out</button>
          </div>
        </section>
      `;
      document.querySelector("#btn-reconnect")?.addEventListener("click", () => render());
      document.querySelector("#btn-offline-signout")?.addEventListener("click", () => signOut());
    }
  }

  // Register service worker if supported
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./service-worker.js").catch(() => {});
  }

  // Start the application
  render();
})();
