/* AI Offline - the app. Plain JavaScript, no build step, no internet.
 * Talks to two local servers: the AI Offline server (this page, chats, setup)
 * and the AI engine (Ollama) for answers and models. */
"use strict";

/* ------------------------------------------------------------------ icons */
const ICONS = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  cube: '<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5M12 13v8"/>',
  code: '<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>',
  gear: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  brain: '<path d="M9 18h6M10 22h4"/><path d="M12 2a7 7 0 0 0-4 12.7c.6.5 1 1.2 1 2V17h6v-.3c0-.8.4-1.5 1-2A7 7 0 0 0 12 2z"/>',
  edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  clip: '<path d="m21.4 11.1-9.2 9.2a6 6 0 0 1-8.5-8.5l9.2-9.2a4 4 0 0 1 5.7 5.7l-9.2 9.2a2 2 0 0 1-2.8-2.8l8.5-8.5"/>',
  arrow: '<path d="M12 19V5M5 12l7-7 7 7"/>',
  stop: '<rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor" stroke="none"/>',
  copy: '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  refresh: '<path d="M3 12a9 9 0 0 1 15.4-6.4L21 8M21 3v5h-5M21 12a9 9 0 0 1-15.4 6.4L3 16M3 21v-5h5"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
  wifiOff: '<path d="m2 2 20 20M8.5 16.5a5 5 0 0 1 7 0M5 12.6a10 10 0 0 1 5.2-2.8M19 12.6a10 10 0 0 0-2.1-1.5M2 8.8a15 15 0 0 1 4.2-2.7M22 8.8a15 15 0 0 0-11.3-3.7M12 20h.01"/>',
  tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
  download: '<path d="M12 3v12M7 10l5 5 5-5M5 21h14"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  power: '<path d="M12 2v10M18.4 6.6a9 9 0 1 1-12.8 0"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>'
};
const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
const paintIcons = (root = document) => root.querySelectorAll("[data-icon]").forEach((e) => { e.innerHTML = icon(e.dataset.icon); });

/* ------------------------------------------------------------------ helpers */
const $ = (sel, root = document) => root.querySelector(sel);
function h(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "class") e.className = v;
    else if (k === "html") e.innerHTML = v;
    else if (k === "text") e.textContent = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) if (kid != null && kid !== false) e.append(kid.nodeType ? kid : String(kid));
  return e;
}
const ico = (name, cls = "ico") => h("span", { class: cls, html: icon(name) });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

const S = {
  status: null,
  engine: "",
  settings: { lang: (navigator.language || "en").toLowerCase().startsWith("fa") ? "fa" : "en", theme: "system", model: "", system: "", think: false },
  chats: [],
  current: null,
  models: [],
  caps: {},
  attachments: [],
  gen: null,
  pulls: {},
  setupView: "welcome",
  setupChoice: "",
  setupShortcuts: true,
};

function t(key, vars) {
  const L = window.I18N[S.settings.lang] || window.I18N.en;
  let s = L[key] ?? window.I18N.en[key] ?? key;
  if (vars && typeof s === "string") for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(v);
  return s;
}
const nf = (n, digits = 1) => Number(n).toLocaleString(S.settings.lang === "fa" ? "fa-IR" : "en-US", { maximumFractionDigits: digits, minimumFractionDigits: 0 });
const gb = (bytes) => t("gb", { n: nf(bytes / 1e9, bytes >= 1e10 ? 0 : 1) });
function duration(sec) {
  if (!isFinite(sec) || sec <= 0) return "";
  if (sec < 60) return t("sec", { n: nf(Math.ceil(sec), 0) });
  if (sec < 3600) return t("min", { n: nf(Math.ceil(sec / 60), 0) });
  return t("hour", { n: nf(Math.floor(sec / 3600), 0), m: nf(Math.round((sec % 3600) / 60), 0) });
}

function toast(text, kind = "") {
  const el = h("div", { class: "toast " + kind, dir: "auto" }, text);
  $("#toasts").append(el);
  setTimeout(() => el.remove(), kind === "error" ? 7000 : 3200);
}

/* ------------------------------------------------------------------ servers */
const LOCAL = { "X-AIO": "1" };
async function local(path, opts = {}) {
  const init = { method: opts.method || "GET", headers: { ...LOCAL } };
  if (opts.body !== undefined) { init.body = JSON.stringify(opts.body); init.headers["Content-Type"] = "application/json"; }
  const r = await fetch("/api/local/" + path, init);
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(data.error || r.statusText), { status: r.status });
  return data;
}
const store = {
  async get(key, fallback) {
    const r = await fetch("/api/local/store/" + key, { headers: LOCAL });
    if (!r.ok) throw new Error("store " + r.status);
    const value = await r.json();
    return value === null ? fallback : value;
  },
  put: (key, value) => fetch("/api/local/store/" + key, { method: "PUT", headers: { ...LOCAL, "Content-Type": "application/json" }, body: JSON.stringify(value) }),
  del: (key) => fetch("/api/local/store/" + key, { method: "DELETE", headers: LOCAL }),
};
async function engine(path, body, signal) {
  const r = await fetch(S.engine + path, body === undefined ? { signal } : { method: "POST", body: JSON.stringify(body), signal });
  if (!r.ok) {
    const data = await r.json().catch(() => ({}));
    throw Object.assign(new Error(data.error || "HTTP " + r.status), { status: r.status, engine: true });
  }
  return r;
}
// Reads a stream of JSON lines (the engine's streaming format).
async function readLines(response, onLine) {
  const reader = response.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (line) onLine(JSON.parse(line));
    }
  }
  if (buf.trim()) onLine(JSON.parse(buf));
}

/* ------------------------------------------------------------------ settings, language, theme */
let saveSettingsTimer = 0;
function saveSettings() {
  clearTimeout(saveSettingsTimer);
  saveSettingsTimer = setTimeout(() => store.put("settings", S.settings), 300);
}
function applyLang() {
  const fa = S.settings.lang === "fa";
  document.documentElement.lang = fa ? "fa" : "en";
  document.documentElement.dir = fa ? "rtl" : "ltr";
  document.querySelectorAll("[data-i18n]").forEach((e) => { e.textContent = t(e.dataset.i18n); });
  document.querySelectorAll("[data-i18n-placeholder]").forEach((e) => { e.placeholder = t(e.dataset.i18nPlaceholder); });
  document.querySelectorAll("[data-i18n-title]").forEach((e) => { e.title = t(e.dataset.i18nTitle); e.setAttribute("aria-label", t(e.dataset.i18nTitle)); });
}
const darkQuery = matchMedia("(prefers-color-scheme: dark)");
function applyTheme() {
  const mode = S.settings.theme === "system" ? (darkQuery.matches ? "dark" : "light") : S.settings.theme;
  document.documentElement.dataset.theme = mode;
}
darkQuery.addEventListener("change", applyTheme);

/* ------------------------------------------------------------------ dialogs */
const modal = $("#modal");
function openModal(build) {
  const body = $("#modalBody");
  body.replaceChildren(...[].concat(build()).flat(Infinity).filter((x) => x != null && x !== false));
  paintIcons(body);
  if (!modal.open) modal.showModal();
}
function modalHead(title) {
  return h("div", { class: "modal-head" }, h("h2", {}, title), h("button", { class: "icon-btn", "aria-label": t("close"), onclick: () => modal.close() }, ico("x")));
}
modal.addEventListener("click", (e) => { if (e.target === modal) modal.close(); });
modal.addEventListener("close", () => { S.modalRefresh = null; });

function ask(text, okLabel, danger = false) {
  return new Promise((resolve) => {
    const d = h("dialog", { class: "ask" });
    const done = (v) => { d.close(); d.remove(); resolve(v); };
    d.append(h("div", { class: "modal-body" },
      h("p", { dir: "auto", style: "margin:0 0 18px;font-size:16px" }, text),
      h("div", { style: "display:flex;gap:10px;justify-content:flex-end" },
        h("button", { class: "btn", onclick: () => done(false) }, t("cancel")),
        h("button", { class: "btn " + (danger ? "danger" : "primary"), onclick: () => done(true) }, okLabel))));
    d.addEventListener("cancel", () => done(false));
    document.body.append(d);
    d.showModal();
  });
}

/* ------------------------------------------------------------------ boot */
async function boot() {
  try {
    S.status = await local("status");
  } catch {
    document.body.replaceChildren(h("div", { class: "boot" }, h("p", { style: "max-width:420px;text-align:center;color:var(--muted)", dir: "auto" },
      "AI Offline is not running. Open it from the desktop shortcut or with AI Offline.bat.  —  AI Offline اجرا نیست. از میان‌بر دسکتاپ یا فایل AI Offline.bat بازش کنید.")));
    return;
  }
  S.engine = S.status.engine.url;
  const saved = await store.get("settings", null).catch(() => null);
  if (saved) Object.assign(S.settings, saved);
  applyTheme();
  applyLang();
  paintIcons();
  $("#boot").hidden = true;
  if (!S.status.installed) {
    const setup = await local("setup").catch(() => ({ state: "idle" }));
    if (S.status.setupRunning || setup.state === "error") showSetup("progress");
    else showSetup(setup.state === "cancelled" ? "choose" : "welcome");
  } else {
    showApp();
  }
}

/* ================================================================== SETUP */
let setupTimer = 0;
function showSetup(view) {
  S.setupView = view;
  $("#app").hidden = true;
  $("#setup").hidden = false;
  renderSetup();
}
function langToggle() {
  return h("div", { class: "seg" },
    h("button", { class: S.settings.lang === "en" ? "on" : "", onclick: () => setLang("en") }, "English"),
    h("button", { class: S.settings.lang === "fa" ? "on" : "", onclick: () => setLang("fa") }, "فارسی"));
}
function setLang(lang) {
  S.settings.lang = lang;
  saveSettings();
  applyLang();
  if (!$("#setup").hidden) renderSetup();
  else { renderChatList(); renderMessages(); renderModelButton(); if (modal.open && S.modalRefresh) S.modalRefresh(); }
}

function renderSetup() {
  const root = $("#setup");
  const top = h("div", { class: "setup-top" },
    h("div", { class: "brand" }, h("img", { src: "logo.svg", width: 28, height: 28, alt: "" }), h("span", {}, "AI Offline")),
    langToggle());
  const views = { welcome: setupWelcome, choose: setupChoose, progress: setupProgress, done: setupDone };
  root.replaceChildren(top, h("div", { class: "setup-card" }, views[S.setupView]()));
  paintIcons(root);
  clearInterval(setupTimer);
  if (S.setupView === "progress") { pollSetup(); setupTimer = setInterval(pollSetup, 700); }
}

function setupWelcome() {
  const feat = (i, title, text) => h("div", { class: "feature" }, ico(i), h("b", {}, title), h("span", {}, text));
  return h("div", { class: "welcome" },
    h("img", { src: "logo.svg", alt: "" }),
    h("h1", {}, t("setupWelcome")),
    h("p", { class: "lead" }, t("setupLead")),
    h("div", { class: "features" }, feat("shield", t("f1t"), t("f1")), feat("wifiOff", t("f2t"), t("f2")), feat("tag", t("f3t"), t("f3"))),
    h("button", { class: "btn accent big", onclick: () => showSetup("choose") }, t("start")));
}

function setupChoose() {
  const st = S.status;
  const hw = st.hardware;
  if (!S.setupChoice) S.setupChoice = st.recommended;
  const engineGB = (st.downloadMB.engine + st.downloadMB.gpu) / 1024;
  const agentGB = st.downloadMB.agent / 1024;
  // show the real graphics card; the built-in Intel one only when there is nothing else
  let gpus = (hw.gpus || []).filter((g) => g.vendor === "nvidia" || g.vendor === "amd");
  if (!gpus.length) gpus = (hw.gpus || []).filter((g) => g.vendor === "intel");
  const gpuText = gpus.length
    ? gpus.map((g) => h("div", {}, h("bdi", {}, g.name), g.vramGB >= 1 && g.vendor !== "intel" ? h("span", { style: "color:var(--muted);font-weight:500" }, " · " + t("gb", { n: nf(g.vramGB, 0) })) : null))
    : t("noGpu");

  const warnings = [];
  if ((hw.warnings || []).includes("onedrive")) warnings.push(t("warnOneDrive"));
  if ((hw.warnings || []).includes("temp")) warnings.push(t("warnTemp"));
  if (hw.ramGB < 8) warnings.push(t("warnRam"));

  const dots = (n) => h("span", { class: "dots" }, [1, 2, 3, 4, 5].map((i) => h("i", { class: i <= n ? "on" : "" })));
  const cards = st.catalog.map((m) => {
    const needGB = m.sizeGB + engineGB + agentGB + 2;
    const noDisk = hw.freeGB < needGB;
    const lowRam = hw.ramGB < m.minRamGB;
    const on = S.setupChoice === m.id;
    return h("button", { class: "choice" + (on ? " on" : ""), disabled: noDisk, onclick: () => { S.setupChoice = m.id; renderSetup(); } },
      h("span", { class: "size" }, t("gb", { n: nf(m.sizeGB) })),
      h("div", { class: "c-top" },
        h("span", { class: "c-name" }, t("name_" + m.tier)),
        h("span", { class: "badge gray" }, m.name),
        m.id === st.recommended ? h("span", { class: "badge" }, t("recommended")) : null,
        lowRam ? h("span", { class: "badge warn" }, t("needsRam", { n: nf(m.minRamGB, 0) })) : null,
        noDisk ? h("span", { class: "badge warn" }, t("noSpace")) : null),
      h("p", { class: "c-desc" }, t("tier_" + m.tier)),
      h("div", { class: "meters" }, h("span", {}, t("speed"), dots(m.speed)), h("span", {}, t("quality"), dots(m.quality))));
  });

  const chosen = st.catalog.find((m) => m.id === S.setupChoice) || st.catalog[0];
  const total = engineGB + agentGB + chosen.sizeGB;
  return h("div", {},
    h("h2", {}, t("yourPc")),
    h("div", { class: "pc" },
      h("div", {}, h("span", {}, t("ram")), h("b", {}, t("gb", { n: nf(hw.ramGB, 0) }))),
      h("div", {}, h("span", {}, t("gpu")), h("b", {}, gpuText)),
      h("div", {}, h("span", {}, t("disk", { d: hw.drive })), h("b", {}, t("gb", { n: nf(hw.freeGB, 0) })))),
    warnings.map((w) => h("div", { class: "warnbox", dir: "auto" }, w)),
    h("h2", { style: "margin-top:22px" }, t("chooseTitle")),
    h("p", { class: "sub" }, t("chooseSub")),
    h("div", { class: "choices" }, cards),
    h("div", { class: "setup-foot" },
      h("div", { class: "total" },
        h("b", {}, t("totalDownload", { n: nf(total) })),
        h("span", {}, t("totalSub", { e: nf(engineGB), a: nf(agentGB), m: nf(chosen.sizeGB), d: nf(Math.ceil(total * 1.6 + 2), 0) }))),
      h("label", { class: "check" }, h("input", { type: "checkbox", checked: S.setupShortcuts, onchange: (e) => { S.setupShortcuts = e.target.checked; } }), t("makeShortcuts")),
      h("button", { class: "btn accent big", onclick: startSetup }, ico("download"), t("install"))),
    h("p", { class: "tip" }, t("vpnTip")));
}

async function startSetup() {
  try {
    await local("setup", { method: "POST", body: { model: S.setupChoice || S.status.recommended, shortcuts: S.setupShortcuts } });
    S.setupState = null;
    showSetup("progress");
  } catch (e) { toast(t("errGeneric", { m: e.message }), "error"); }
}

async function pollSetup() {
  try {
    const st = await local("setup");
    S.setupState = st;
    if (st.state === "done") { clearInterval(setupTimer); showSetup("done"); return; }
    paintProgress(st);
  } catch { /* the server may be busy for a moment */ }
}

function setupProgress() {
  return h("div", {},
    h("h2", {}, t("installing")),
    h("p", { class: "sub" }, t("installingSub")),
    h("div", { class: "overall", id: "overall" }),
    h("div", { class: "steps", id: "steps" }),
    h("div", { id: "setupActions", style: "display:flex;gap:10px;flex-wrap:wrap" }));
}

function errorText(msg) {
  const m = (msg || "").toLowerCase();
  if (m.includes("model-not-found")) return t("e_model");
  if (m.includes("engine-start")) return t("e_engine");
  if (m.includes("checksum")) return t("e_checksum");
  if (m.includes("space") || m.includes("disk")) return t("e_disk");
  return t("e_network");
}

function paintProgress(st) {
  const box = $("#steps"), overall = $("#overall"), actions = $("#setupActions");
  if (!box) return;
  const steps = st.steps || {};
  const order = ["engine", "gpu", "agent", "prepare", "start", "model", "finish"].filter((k) => steps[k] && steps[k].status !== "skipped");
  const bytesSteps = ["engine", "gpu", "agent", "model"].filter((k) => order.includes(k));
  let total = 0, done = 0;
  for (const k of bytesSteps) { total += steps[k].total || 0; done += steps[k].status === "done" ? steps[k].total || 0 : steps[k].done || 0; }
  const active = steps[st.step] || {};
  const pct = total ? Math.min(st.state === "done" ? 100 : 99, Math.floor((done / total) * 100)) : 0;
  const speed = active.speed || 0;
  const remain = speed > 0 && bytesSteps.includes(st.step) ? (total - done) / speed : 0;
  const modelName = (S.status.catalog.concat(S.status.extraModels).find((m) => m.id === st.model) || { name: st.model }).name;

  let line = t("of", { a: gb(done), b: gb(total) });
  if (speed > 0) line += ` · ${nf(speed / 1e6, 1)} MB/s`;
  if (remain) line += " · " + t("left", { t: duration(remain) });
  if (st.detail === "starting" || !order.length) line = t("preparing");
  if (st.detail === "verify") line = t("verifying");
  if (st.detail && st.detail.startsWith("retry:")) line = t("retrying", { n: nf(st.detail.split(":")[1], 0) });

  overall.replaceChildren(
    h("div", { class: "o-top" }, h("b", {}, nf(pct, 0) + (S.settings.lang === "fa" ? "٪" : "%")), h("span", { dir: "auto" }, line)),
    h("div", { class: "bar big" }, h("i", { style: `width:${pct}%` })));

  box.replaceChildren(...order.map((k) => {
    const s = steps[k];
    const label = k === "model" ? t("s_model", { m: modelName }) : t("s_" + k);
    const showBar = s.status === "active" && bytesSteps.includes(k) && s.total;
    const meta = s.status === "active" && s.total && bytesSteps.includes(k) ? t("of", { a: gb(s.done || 0), b: gb(s.total) }) : "";
    return h("div", { class: "step " + s.status },
      h("span", { class: "s-ico" }, s.status === "done" ? ico("check", "ico sm") : s.status === "error" ? ico("x", "ico sm") : null),
      h("span", { class: "s-name" }, label),
      h("span", { class: "s-meta" }, meta),
      showBar ? h("div", { class: "bar" }, h("i", { style: `width:${Math.floor(((s.done || 0) / s.total) * 100)}%` })) : null);
  }));
  paintIcons(box);

  if (st.state === "error" || st.state === "cancelled") {
    const err = st.state === "error";
    actions.replaceChildren(
      h("div", { class: "warnbox", style: "width:100%", dir: "auto" }, h("b", {}, err ? t("setupFailed") : t("setupStopped")), h("div", {}, err ? errorText(st.error) : "")),
      h("button", { class: "btn accent", onclick: () => local("setup", { method: "POST", body: { model: st.model, shortcuts: S.setupShortcuts } }).then(pollSetup) }, ico("refresh"), err ? t("retry") : t("resume")),
      h("button", { class: "btn", onclick: () => showSetup("choose") }, t("back")),
      err ? h("button", { class: "btn", onclick: () => local("open-folder", { method: "POST" }) }, ico("folder"), t("openLogs")) : null,
      err ? h("details", { style: "width:100%;color:var(--muted);font-size:13px" }, h("summary", {}, t("showDetails")), h("code", { dir: "ltr" }, st.error || "")) : null);
    paintIcons(actions);
  } else if (!actions.childElementCount) {
    actions.replaceChildren(h("button", { class: "btn", onclick: async () => { if (await ask(t("cancelSetupQ"), t("cancelSetup"), true)) { await local("setup/cancel", { method: "POST" }); pollSetup(); } } }, t("cancelSetup")));
  }
}

function setupDone() {
  return h("div", { class: "done-screen" },
    h("div", { class: "done-mark" }, ico("check")),
    h("div", { class: "welcome", style: "padding:0" }, h("h1", {}, t("doneTitle")), h("p", { class: "lead" }, t("doneText"))),
    h("button", { class: "btn accent big", onclick: () => location.reload() }, t("startChat")));
}

/* ================================================================== APP */
async function showApp() {
  $("#setup").hidden = true;
  $("#app").hidden = false;
  applyLang();
  bindApp();
  S.chats = (await store.get("chats", [])) || [];
  renderChatList();
  renderMessages();
  await ensureEngine();
  await refreshModels();
  renderMessages();
  setInterval(watchEngine, 15000);
}

async function ensureEngine() {
  for (let i = 0; i < 3; i++) {
    try { await engine("/api/version"); $("#engineState").hidden = true; return true; } catch { /* starting */ }
    $("#engineState").hidden = false;
    $("#engineState").textContent = t("engineStarting");
    await local("engine/start", { method: "POST" }).catch(() => {});
  }
  return false;
}
async function watchEngine() {
  if (S.gen) return;
  try { await engine("/api/version"); $("#engineState").hidden = true; } catch { ensureEngine(); }
}

const catalogAll = () => S.status.catalog.concat(S.status.extraModels);
const prettyName = (id) => (catalogAll().find((m) => m.id === id) || { name: id }).name;

async function refreshModels() {
  try {
    const r = await engine("/api/tags");
    S.models = ((await r.json()).models || []).sort((a, b) => a.size - b.size);
  } catch { S.models = []; }
  const names = S.models.map((m) => m.name);
  if (!names.includes(S.settings.model)) { S.settings.model = names.includes(S.status.recommended) ? S.status.recommended : names[names.length - 1] || ""; saveSettings(); }
  renderModelButton();
}

async function caps(model) {
  if (!model) return {};
  if (S.caps[model]) return S.caps[model];
  try {
    const r = await engine("/api/show", { model });
    const c = (await r.json()).capabilities || [];
    S.caps[model] = { vision: c.includes("vision"), thinking: c.includes("thinking") };
  } catch { S.caps[model] = { vision: false, thinking: false }; }
  return S.caps[model];
}

async function renderModelButton() {
  const m = S.settings.model;
  $("#modelName").textContent = m ? prettyName(m) : t("getModel");
  const c = await caps(m);
  const btn = $("#thinkBtn");
  btn.hidden = !c.thinking;
  btn.classList.toggle("on", !!S.settings.think);
  btn.title = S.settings.think ? t("thinkOn") : t("thinkOff");
}

let bound = false;
function bindApp() {
  if (bound) return;
  bound = true;
  const input = $("#input");
  $("#newChat").onclick = $("#newChatTop").onclick = () => { S.current = null; closeSide(); renderChatList(); renderMessages(); input.focus(); };
  $("#openSide").onclick = () => $("#app").classList.add("side-open");
  $("#closeSide").onclick = $("#scrim").onclick = closeSide;
  $("#closeSide").innerHTML = icon("x");
  $("#search").oninput = renderChatList;
  $("#openModels").onclick = () => { closeSide(); openModels(); };
  $("#openAgent").onclick = () => { closeSide(); openAgent(); };
  $("#openSettings").onclick = () => { closeSide(); openSettings(); };
  $("#modelBtn").onclick = (e) => { e.stopPropagation(); toggleModelMenu(); };
  document.addEventListener("click", (e) => { if (!e.target.closest(".model-picker")) $("#modelMenu").hidden = true; });
  $("#thinkBtn").onclick = () => { S.settings.think = !S.settings.think; saveSettings(); renderModelButton(); toast(S.settings.think ? t("thinkOn") : t("thinkOff")); };
  input.addEventListener("input", autosize);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); submit(); }
  });
  $("#composer").onsubmit = (e) => { e.preventDefault(); if (S.gen) S.gen.controller.abort(); else submit(); };
  $("#attachBtn").onclick = () => $("#fileInput").click();
  $("#fileInput").onchange = (e) => { addFiles([...e.target.files]); e.target.value = ""; };
  input.addEventListener("paste", (e) => {
    const files = [...(e.clipboardData?.files || [])];
    if (files.length) { e.preventDefault(); addFiles(files); }
  });
  const main = $(".main");
  main.addEventListener("dragover", (e) => { e.preventDefault(); main.classList.add("dropping"); });
  main.addEventListener("dragleave", (e) => { if (!main.contains(e.relatedTarget)) main.classList.remove("dropping"); });
  main.addEventListener("drop", (e) => { e.preventDefault(); main.classList.remove("dropping"); addFiles([...e.dataTransfer.files]); });
  $("#messages").addEventListener("click", onMessageClick);
  $("#thread").addEventListener("scroll", () => {
    const th = $("#thread");
    S.stick = th.scrollHeight - th.scrollTop - th.clientHeight < 80;
  });
  setSendState();
}
const closeSide = () => $("#app").classList.remove("side-open");
function autosize() {
  const el = $("#input");
  el.style.height = "auto";
  el.style.height = Math.min(el.scrollHeight, 240) + "px";
  setSendState();
}
function setSendState() {
  const btn = $("#sendBtn");
  const busy = !!S.gen;
  btn.classList.toggle("stop", busy);
  btn.innerHTML = icon(busy ? "stop" : "arrow");
  btn.title = busy ? t("stop") : t("send");
  btn.disabled = !busy && !$("#input").value.trim() && !S.attachments.length;
}

function toggleModelMenu() {
  const menu = $("#modelMenu");
  if (!menu.hidden) { menu.hidden = true; return; }
  const items = S.models.map((m) => h("button", { onclick: async () => { S.settings.model = m.name; saveSettings(); menu.hidden = true; await renderModelButton(); } },
    h("span", {}, h("div", { class: "m-name" }, prettyName(m.name)), h("div", { class: "m-sub" }, `${m.name} · ${gb(m.size)}`)),
    m.name === S.settings.model ? h("span", { class: "check" }, ico("check", "ico sm")) : null));
  menu.replaceChildren(...items, items.length ? h("hr") : null, h("button", { onclick: () => { menu.hidden = true; openModels(); } }, ico("cube", "ico sm"), t("models") + "…"));
  menu.hidden = false;
}

/* ------------------------------------------------------------------ chat list */
function renderChatList() {
  const list = $("#chatList");
  const q = ($("#search").value || "").trim().toLowerCase();
  const chats = S.chats.filter((c) => !q || (c.title || "").toLowerCase().includes(q));
  if (!chats.length) { list.replaceChildren(h("div", { class: "empty-list" }, t("noChats"))); return; }
  const now = new Date();
  const day0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const groups = [["today", day0], ["yesterday", day0 - 864e5], ["week", day0 - 7 * 864e5], ["older", -Infinity]];
  const out = [];
  let last = "";
  for (const c of chats) {
    const g = groups.find(([, from]) => c.updated >= from)[0];
    if (g !== last) { out.push(h("div", { class: "group-label" }, t(g))); last = g; }
    out.push(h("div", { class: "chat-item" + (S.current && S.current.id === c.id ? " active" : "") },
      h("a", { href: "#", dir: "auto", title: c.title, onclick: (e) => { e.preventDefault(); openChat(c.id); } }, c.title || "…"),
      h("button", { class: "icon-btn more", title: t("rename"), onclick: () => renameChat(c) }, ico("edit", "ico sm")),
      h("button", { class: "icon-btn more", title: t("delete"), onclick: () => deleteChat(c) }, ico("trash", "ico sm"))));
  }
  list.replaceChildren(...out);
}

async function openChat(id) {
  closeSide();
  if (S.gen && S.gen.chat.id === id) { S.current = S.gen.chat; }
  else {
    const chat = await store.get("chat-" + id, null);
    if (!chat) { toast(t("errGeneric", { m: "not found" }), "error"); return; }
    S.current = chat;
  }
  const names = S.models.map((m) => m.name);
  if (S.current.model && names.includes(S.current.model) && S.current.model !== S.settings.model) { S.settings.model = S.current.model; saveSettings(); renderModelButton(); }
  renderChatList();
  renderMessages();
  scrollToEnd(true);
}

async function renameChat(c) {
  const name = prompt(t("renamePrompt"), c.title);
  if (!name || !name.trim()) return;
  c.title = name.trim();
  if (S.current && S.current.id === c.id) S.current.title = c.title;
  const full = S.current && S.current.id === c.id ? S.current : await store.get("chat-" + c.id, null);
  if (full) { full.title = c.title; await store.put("chat-" + c.id, full); }
  await store.put("chats", S.chats);
  renderChatList();
}

async function deleteChat(c) {
  if (!(await ask(t("deleteChatQ"), t("delete"), true))) return;
  S.chats = S.chats.filter((x) => x.id !== c.id);
  await store.del("chat-" + c.id);
  await store.put("chats", S.chats);
  if (S.current && S.current.id === c.id) { S.current = null; renderMessages(); }
  renderChatList();
}

function saveChat(chat) {
  const clean = { ...chat, messages: chat.messages.map(({ streaming, ...m }) => m) };
  store.put("chat-" + chat.id, clean);
  const entry = { id: chat.id, title: chat.title, updated: chat.updated, model: chat.model };
  S.chats = [entry, ...S.chats.filter((c) => c.id !== chat.id)];
  store.put("chats", S.chats);
  renderChatList();
}

/* ------------------------------------------------------------------ messages */
const md = (() => {
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const renderer = {
    html: ({ text }) => esc(text),
    image: ({ text }) => esc(text || ""),
    link({ href, tokens }) {
      const label = this.parser.parseInline(tokens);
      if (!/^(https?:|mailto:)/i.test(href || "")) return label;
      return `<a href="${esc(href)}" target="_blank" rel="noopener noreferrer">${label}</a>`;
    },
    code({ text, lang }) {
      const name = esc((lang || "").split(/\s/)[0] || "code");
      return `<div class="code"><div class="code-head"><span>${name}</span><button type="button" data-copy>${esc(t("copy"))}</button></div><pre><code>${esc(text)}</code></pre></div>`;
    },
  };
  let ready = false;
  return (text) => {
    if (!ready && window.marked) { window.marked.use({ gfm: true, breaks: true, renderer }); ready = true; }
    if (!window.marked) return esc(text).replace(/\n/g, "<br>");
    const div = document.createElement("div");
    div.innerHTML = window.marked.parse(text || "");
    div.querySelectorAll("p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th").forEach((e) => e.setAttribute("dir", "auto"));
    return div.innerHTML;
  };
})();

function helloView() {
  if (!S.models.length && S.status) {
    return h("div", { class: "hello" },
      h("img", { src: "logo.svg", alt: "" }),
      h("h1", {}, t("noModelsTitle")),
      h("p", {}, t("noModelsText")),
      h("button", { class: "btn accent", onclick: openModels }, ico("download"), t("getModel")));
  }
  return h("div", { class: "hello" },
    h("img", { src: "logo.svg", alt: "" }),
    h("h1", {}, t("helloTitle")),
    h("p", {}, t("helloSub")),
    h("div", { class: "suggestions" }, t("suggestions").map(([a, b]) => h("button", { class: "suggestion", dir: "auto", onclick: () => { $("#input").value = `${a}: ${b}`; autosize(); $("#input").focus(); } }, h("b", {}, a), h("span", {}, b)))));
}

function renderMessages() {
  const box = $("#messages");
  if (!S.current || !S.current.messages.length) { box.replaceChildren(helloView()); paintIcons(box); return; }
  const msgs = S.current.messages;
  box.replaceChildren(...msgs.map((m, i) => messageEl(m, i === msgs.length - 1)));
  paintIcons(box);
}

function messageEl(m, isLast) {
  if (m.role === "user") {
    return h("div", { class: "msg user" },
      h("div", {},
        m.images && m.images.length ? h("div", { class: "imgs" }, m.images.map((b) => h("img", { src: "data:image/jpeg;base64," + b, alt: "" }))) : null,
        m.files && m.files.length ? h("div", { class: "imgs" }, m.files.map((f) => h("span", { class: "att" }, ico("file", "ico sm"), h("span", { class: "fname" }, f)))) : null,
        (m.text ?? m.content) ? h("div", { class: "bubble", dir: "auto" }, m.text ?? m.content) : null));
  }
  const body = h("div", { class: "body" });
  if (m.thinking) {
    const label = m.streaming && !m.content ? t("thinking") : m.thinkSec ? t("thoughtFor", { s: nf(m.thinkSec, 0) }) : t("showThinking");
    body.append(h("details", { class: "thinking", open: m.streaming && !m.content }, h("summary", {}, ico("brain", "ico sm"), label), h("div", { class: "t-body", dir: "auto" }, m.thinking)));
  }
  if (m.content) body.append(h("div", { class: "md", dir: "auto", html: md(m.content) }));
  else if (m.streaming && !m.thinking) body.append(h("div", { class: "typing" }, h("i"), h("i"), h("i")), m.slow ? h("div", { class: "status-line" }, t("loadingModel")) : null);
  if (m.error) body.append(h("div", { class: "error-box", dir: "auto" }, m.error));
  if (!m.streaming) {
    const stats = m.stats && m.stats.tps ? t("tokS", { n: nf(m.stats.tps, 0) }) : "";
    body.append(h("div", { class: "msg-actions" },
      m.content ? h("button", { class: "icon-btn", title: t("copy"), "data-copymsg": "1" }, ico("copy", "ico sm")) : null,
      isLast ? h("button", { class: "icon-btn", title: t("regenerate"), "data-regen": "1" }, ico("refresh", "ico sm")) : null,
      stats ? h("span", { class: "stats", title: prettyName(m.model || "") }, stats) : null));
  }
  const el = h("div", { class: "msg assistant" }, h("img", { class: "avatar", src: "logo.svg", alt: "" }), body);
  el._msg = m;
  return el;
}

function onMessageClick(e) {
  const copyBtn = e.target.closest("[data-copy]");
  if (copyBtn) {
    navigator.clipboard.writeText(copyBtn.closest(".code").querySelector("code").textContent);
    copyBtn.textContent = t("copied");
    setTimeout(() => { copyBtn.textContent = t("copy"); }, 1500);
    return;
  }
  const copyMsg = e.target.closest("[data-copymsg]");
  if (copyMsg) { navigator.clipboard.writeText(copyMsg.closest(".msg")._msg.content); toast(t("copied")); return; }
  if (e.target.closest("[data-regen]")) regenerate();
}

function scrollToEnd(force) {
  const th = $("#thread");
  if (force || S.stick !== false) th.scrollTop = th.scrollHeight;
}

/* ------------------------------------------------------------------ attachments */
const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|jsonl|xml|html?|css|js|mjs|cjs|ts|tsx|jsx|py|java|kt|c|h|cpp|hpp|cs|go|rs|php|rb|swift|dart|lua|r|sql|sh|bat|cmd|ps1|ini|cfg|conf|toml|ya?ml|log|srt|vtt|tex)$/i;
async function addFiles(files) {
  const c = await caps(S.settings.model);
  for (const f of files) {
    if (f.type.startsWith("image/")) {
      if (!c.vision) { toast(t("noVision"), "error"); continue; }
      const data = await shrinkImage(f);
      S.attachments.push({ kind: "image", name: f.name, data });
    } else if (f.type.startsWith("text/") || TEXT_EXT.test(f.name)) {
      if (f.size > 300 * 1024) { toast(t("fileTooBig", { f: f.name }), "error"); continue; }
      S.attachments.push({ kind: "text", name: f.name, text: await f.text() });
    } else toast(t("fileType", { f: f.name }), "error");
  }
  renderAttachments();
}
function shrinkImage(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const k = Math.min(1, 1600 / Math.max(img.width, img.height));
      const c = document.createElement("canvas");
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(img.src);
      resolve(c.toDataURL("image/jpeg", 0.9).split(",")[1]);
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}
function renderAttachments() {
  const box = $("#attachments");
  box.hidden = !S.attachments.length;
  box.replaceChildren(...S.attachments.map((a, i) => h("div", { class: "att" },
    a.kind === "image" ? h("img", { src: "data:image/jpeg;base64," + a.data, alt: "" }) : ico("file"),
    h("span", { class: "fname", dir: "auto" }, a.name),
    h("button", { type: "button", class: "x", "aria-label": t("delete"), onclick: () => { S.attachments.splice(i, 1); renderAttachments(); } }, "×"))));
  setSendState();
}

/* ------------------------------------------------------------------ talking to the model */
function systemPrompt() {
  const date = new Date().toISOString().slice(0, 10);
  let s = "You are AI Offline, a helpful assistant that runs entirely on the user's own computer, without internet access. "
    + "Always answer in the same language the user writes in; for example, answer Persian messages in Persian. "
    + "Be clear and practical, and use Markdown when it helps. Today's date is " + date + ".";
  if ((S.settings.system || "").trim()) s += "\n\nThe user's instructions:\n" + S.settings.system.trim();
  return s;
}

function submit() {
  const input = $("#input");
  const text = input.value.trim();
  if (S.gen || (!text && !S.attachments.length)) return;
  if (!S.models.length || !S.settings.model) { openModels(); return; }
  const atts = S.attachments;
  S.attachments = [];
  renderAttachments();
  input.value = "";
  autosize();
  const files = atts.filter((a) => a.kind === "text");
  let content = text;
  if (files.length) content = files.map((a) => `File "${a.name}":\n\`\`\`\n${a.text}\n\`\`\``).join("\n\n") + (text ? "\n\n" + text : "");
  const images = atts.filter((a) => a.kind === "image").map((a) => a.data);
  if (!S.current) {
    const title = (text || files.map((f) => f.name).join(", ") || "…").replace(/\s+/g, " ").slice(0, 60);
    S.current = { id: newId(), title, model: S.settings.model, created: Date.now(), updated: Date.now(), messages: [] };
  }
  S.current.messages.push({ role: "user", content, text, files: files.map((f) => f.name), images });
  S.stick = true;
  generate(S.current);
}

function regenerate() {
  const chat = S.current;
  if (!chat || S.gen) return;
  if (chat.messages.length && chat.messages[chat.messages.length - 1].role === "assistant") chat.messages.pop();
  generate(chat);
}

async function generate(chat) {
  const model = S.settings.model;
  chat.model = model;
  const msg = { role: "assistant", content: "", thinking: "", model, streaming: true };
  chat.messages.push(msg);
  const controller = new AbortController();
  S.gen = { controller, chat, msg };
  setSendState();
  renderChatList();
  renderMessages();
  scrollToEnd(true);
  const slowTimer = setTimeout(() => { if (!msg.content && !msg.thinking) { msg.slow = true; paintLast(chat); } }, 3500);
  let thinkStart = 0;
  let frame = 0;
  const paint = () => { if (frame) return; frame = requestAnimationFrame(() => { frame = 0; paintLast(chat); scrollToEnd(); }); };

  const history = [{ role: "system", content: systemPrompt() }];
  for (const m of chat.messages) {
    if (m === msg || m.error || (m.role === "assistant" && !m.content)) continue;
    const item = { role: m.role, content: m.content || "" };
    if (m.images && m.images.length) item.images = m.images;
    history.push(item);
  }
  const c = await caps(model);
  const body = { model, messages: history, stream: true };
  if (c.thinking) body.think = !!S.settings.think;

  try {
    let r;
    try { r = await engine("/api/chat", body, controller.signal); }
    catch (e) {
      if (e.name === "AbortError") throw e;
      if (e.engine && /think/i.test(e.message)) { S.caps[model] = { ...c, thinking: false }; delete body.think; renderModelButton(); r = await engine("/api/chat", body, controller.signal); }
      else if (!e.engine) { toast(t("errEngine")); await ensureEngine(); r = await engine("/api/chat", body, controller.signal); }
      else throw e;
    }
    await readLines(r, (j) => {
      if (j.error) throw new Error(j.error);
      const mm = j.message || {};
      if (mm.thinking) { if (!thinkStart) thinkStart = performance.now(); msg.thinking += mm.thinking; }
      if (mm.content) {
        if (thinkStart && !msg.thinkSec) msg.thinkSec = Math.max(1, Math.round((performance.now() - thinkStart) / 1000));
        msg.content += mm.content;
      }
      if (j.done && j.eval_count && j.eval_duration) msg.stats = { tps: j.eval_count / (j.eval_duration / 1e9), tokens: j.eval_count };
      if (mm.thinking || mm.content) { msg.slow = false; paint(); }
    });
    if (thinkStart && !msg.thinkSec) msg.thinkSec = Math.max(1, Math.round((performance.now() - thinkStart) / 1000));
  } catch (e) {
    if (e.name !== "AbortError") msg.error = t("errGeneric", { m: e.message });
  } finally {
    clearTimeout(slowTimer);
    if (frame) cancelAnimationFrame(frame);
    msg.streaming = false;
    delete msg.slow;
    S.gen = null;
    chat.updated = Date.now();
    saveChat(chat);
    if (S.current === chat) { renderMessages(); scrollToEnd(); }
    setSendState();
  }
}

// Repaint only the last message while it streams.
function paintLast(chat) {
  if (S.current !== chat) return;
  const box = $("#messages");
  const last = box.lastElementChild;
  const m = chat.messages[chat.messages.length - 1];
  if (!last || last._msg !== m) { renderMessages(); return; }
  const fresh = messageEl(m, true);
  last.replaceWith(fresh);
  paintIcons(fresh);
}

/* ------------------------------------------------------------------ models window */
function openModels() {
  S.modalRefresh = openModels;
  openModal(() => {
    const installed = S.models.map((m) => {
      const inUse = m.name === S.settings.model;
      return h("div", { class: "model-row" },
        h("div", { class: "label" },
          h("b", {}, prettyName(m.name), h("span", { class: "badge gray" }, m.name), inUse ? h("span", { class: "badge" }, t("inUse")) : null),
          h("span", {}, gb(m.size) + (m.details && m.details.parameter_size ? " · " + m.details.parameter_size : ""))),
        inUse ? null : h("button", { class: "btn small", onclick: async () => { S.settings.model = m.name; saveSettings(); await renderModelButton(); openModels(); } }, t("use")),
        h("button", { class: "icon-btn", title: t("delete"), onclick: () => deleteModel(m.name) }, ico("trash", "ico sm")));
    });
    const names = S.models.map((m) => m.name);
    const hw = S.status.hardware;
    const more = catalogAll().filter((m) => !names.includes(m.id)).map((m) => modelOffer(m, hw));
    const custom = h("input", { class: "field", placeholder: t("customPh"), dir: "ltr" });
    return [
      modalHead(t("modelsTitle")),
      S.models.length ? h("div", { class: "section-title" }, t("installed")) : null,
      installed,
      h("div", { class: "section-title" }, t("getMore")),
      more,
      Object.keys(S.pulls).filter((id) => !catalogAll().some((m) => m.id === id)).map((id) => modelOffer({ id, name: id, sizeGB: 0, tier: "" }, hw)),
      h("div", { class: "section-title" }, t("customModel")),
      h("div", { style: "display:flex;gap:10px" }, custom, h("button", { class: "btn", onclick: () => { const id = custom.value.trim().toLowerCase(); if (/^[a-z0-9][a-z0-9._\/-]*(:[a-z0-9._-]+)?$/.test(id)) pullModel(id); } }, ico("download", "ico sm"), t("download"))),
      h("p", { class: "tip" }, t("netHint")),
    ];
  });
}

function modelOffer(m, hw) {
  const p = S.pulls[m.id];
  const lowRam = m.minRamGB && hw.ramGB < m.minRamGB;
  const noDisk = m.sizeGB && hw.freeGB < m.sizeGB + 2;
  return h("div", { class: "model-row" },
    h("div", { class: "label" },
      h("b", {}, m.tier && t("name_" + m.tier) !== "name_" + m.tier ? t("name_" + m.tier) + " · " : "", m.name,
        m.id === S.status.recommended ? h("span", { class: "badge" }, t("recommended")) : null,
        lowRam ? h("span", { class: "badge warn" }, t("needsRam", { n: nf(m.minRamGB, 0) })) : null,
        noDisk ? h("span", { class: "badge warn" }, t("noSpace")) : null),
      h("span", {}, (m.sizeGB ? t("gb", { n: nf(m.sizeGB) }) + " · " : "") + (m.tier ? t("tier_" + m.tier) : m.id)),
      p ? h("div", {}, h("div", { class: "bar", style: "margin-top:8px" }, h("i", { style: `width:${p.pct}%` })), h("div", { class: "pull-line" }, p.line)) : null),
    p ? h("button", { class: "btn small", onclick: () => p.controller.abort() }, t("cancel"))
      : h("button", { class: "btn small", disabled: noDisk, onclick: () => pullModel(m.id) }, ico("download", "ico sm"), t("download")));
}

async function pullModel(id) {
  if (S.pulls[id]) return;
  const controller = new AbortController();
  const entry = (catalogAll().find((m) => m.id === id) || {});
  const p = (S.pulls[id] = { controller, pct: 0, line: t("downloading") });
  const refresh = () => { if (modal.open && S.modalRefresh === openModels) openModels(); };
  refresh();
  const layers = {};
  let mark = performance.now(), markBytes = 0, speed = 0, lastPaint = 0;
  try {
    const r = await engine("/api/pull", { model: id, stream: true }, controller.signal);
    await readLines(r, (j) => {
      if (j.error) throw new Error(j.error);
      if (j.digest && j.total) layers[j.digest] = [j.completed || 0, j.total];
      let done = 0, total = 0;
      for (const [d, tt] of Object.values(layers)) { done += d; total += tt; }
      total = Math.max(total, (entry.sizeGB || 0) * 1e9);
      const now = performance.now();
      if (now - mark > 700) { const v = ((done - markBytes) / (now - mark)) * 1000; speed = speed ? speed * 0.7 + v * 0.3 : v; mark = now; markBytes = done; }
      p.pct = total ? Math.floor((done / total) * 100) : 0;
      p.line = /verifying|writing/.test(j.status || "") ? t("verifying") : `${t("of", { a: gb(done), b: gb(total) })}${speed > 0 ? ` · ${nf(speed / 1e6, 1)} MB/s` : ""}`;
      if (now - lastPaint > 400) { lastPaint = now; refresh(); }
    });
    toast(t("pullDone", { m: entry.name || id }));
    delete S.pulls[id];
    await refreshModels();
    if (!S.settings.model) { S.settings.model = id; saveSettings(); renderModelButton(); }
    local("agent/config", { method: "POST" }).catch(() => {});
    renderMessages();
  } catch (e) {
    delete S.pulls[id];
    if (e.name !== "AbortError") toast(t("pullFailed", { m: e.message }) + " " + t("netHint"), "error");
  }
  refresh();
}

async function deleteModel(name) {
  if (!(await ask(t("deleteModelQ", { m: prettyName(name) }), t("delete"), true))) return;
  try {
    const r = await fetch(S.engine + "/api/delete", { method: "DELETE", body: JSON.stringify({ model: name }) });
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || r.status);
    toast(t("deleted"));
  } catch (e) { toast(t("errGeneric", { m: e.message }), "error"); }
  await refreshModels();
  openModels();
}

/* ------------------------------------------------------------------ settings window */
function openSettings() {
  S.modalRefresh = openSettings;
  openModal(() => {
    const seg = (options, value, onPick) => h("div", { class: "seg" }, options.map(([v, label]) => h("button", { class: v === value ? "on" : "", onclick: () => onPick(v) }, label)));
    const sw = (on, onToggle) => h("button", { class: "switch" + (on ? " on" : ""), role: "switch", "aria-checked": String(!!on), onclick: onToggle });
    const instr = h("textarea", { class: "field", rows: 3, dir: "auto", placeholder: t("instructionsPh"), oninput: (e) => { S.settings.system = e.target.value; saveSettings(); } });
    instr.value = S.settings.system || "";
    const row = (title, hint, control) => h("div", { class: "row" }, h("div", { class: "label" }, h("b", {}, title), hint ? h("span", {}, hint) : null), control);
    return [
      modalHead(t("settingsTitle")),
      row(t("language"), null, seg([["en", "English"], ["fa", "فارسی"]], S.settings.lang, (v) => { setLang(v); openSettings(); })),
      row(t("theme"), null, seg([["system", t("themeSystem")], ["light", t("themeLight")], ["dark", t("themeDark")]], S.settings.theme, (v) => { S.settings.theme = v; saveSettings(); applyTheme(); openSettings(); })),
      row(t("thinkDefault"), t("thinkDefaultHint"), sw(S.settings.think, () => { S.settings.think = !S.settings.think; saveSettings(); renderModelButton(); openSettings(); })),
      h("div", { class: "row", style: "display:block" }, h("div", { class: "label", style: "margin-bottom:8px" }, h("b", {}, t("instructions")), h("span", {}, t("instructionsHint"))), instr),
      h("div", { class: "section-title" }, t("data")),
      row(t("data"), t("dataHint"), h("button", { class: "btn small", onclick: () => local("open-folder", { method: "POST" }) }, ico("folder", "ico sm"), t("openFolder"))),
      row(t("shortcuts"), null, h("button", { class: "btn small", onclick: () => local("shortcuts", { method: "POST" }).then(() => toast(t("shortcutsDone"))) }, t("createShortcuts"))),
      row(t("deleteAll"), null, h("button", { class: "btn small danger", onclick: deleteAllChats }, ico("trash", "ico sm"), t("delete"))),
      h("div", { class: "section-title" }, t("about")),
      row(t("aboutText", { v: S.status.version, o: S.status.engine.version }), null, h("a", { class: "btn small", href: S.status.repo, target: "_blank", rel: "noopener" }, "GitHub")),
      row(t("quit"), t("quitHint"), h("button", { class: "btn small danger", onclick: quitApp }, ico("power", "ico sm"), t("quit"))),
    ];
  });
}

async function deleteAllChats() {
  if (!(await ask(t("deleteAllQ"), t("delete"), true))) return;
  for (const c of S.chats) await store.del("chat-" + c.id);
  S.chats = [];
  S.current = null;
  await store.put("chats", []);
  renderChatList();
  renderMessages();
  toast(t("deleted"));
}

async function quitApp() {
  if (!(await ask(t("quitQ"), t("quit"), true))) return;
  if (S.gen) S.gen.controller.abort();
  await local("quit", { method: "POST" }).catch(() => {});
  modal.close();
  document.body.replaceChildren(h("div", { class: "boot" }, h("div", { style: "text-align:center" }, h("img", { src: "logo.svg", width: 56, height: 56, alt: "" }), h("p", { style: "color:var(--muted)" }, t("stopped")))));
}

/* ------------------------------------------------------------------ coding agent window */
function openAgent() {
  S.modalRefresh = openAgent;
  openModal(() => [
    modalHead(t("agentTitle")),
    h("p", { style: "margin-top:0" }, t("agentText")),
    h("p", { class: "tip", style: "margin-top:0" }, t("agentModelHint")),
    h("div", { id: "agentOut", style: "margin:14px 0" }),
    h("button", { class: "btn accent", id: "agentGo", onclick: startAgent }, ico("code", "ico sm"), t("agentOpen")),
    h("p", { class: "tip" }, t("agentTerminal")),
  ]);
}
async function startAgent() {
  const out = $("#agentOut");
  const go = $("#agentGo");
  if (!S.models.length) { out.replaceChildren(h("div", { class: "warnbox" }, t("agentNoModels"))); return; }
  go.disabled = true;
  out.replaceChildren(h("div", { class: "status-line" }, t("agentOpening")));
  try {
    const r = await local("agent/start", { method: "POST" });
    if (!r.opened) window.open(r.url, "_blank");
    out.replaceChildren(h("div", { class: "status-line" }, h("a", { href: r.url, target: "_blank", rel: "noopener" }, t("agentLink"))));
  } catch (e) {
    const key = e.message === "agent-missing" ? "agentMissing" : e.message === "no-models" ? "agentNoModels" : null;
    out.replaceChildren(h("div", { class: "warnbox", dir: "auto" }, key ? t(key) : t("errGeneric", { m: e.message })));
  }
  go.disabled = false;
}

boot();
