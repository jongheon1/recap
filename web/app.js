const app = document.getElementById("app");
const actions = document.getElementById("header-actions");

const fmtDur = (s) => {
  if (!s) return "";
  const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
  return h ? `${h}시간 ${m}분` : `${m}분`;
};
const fmtT = (s) => {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return (h ? `${h}:` : "") + String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
};
const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

async function loadIndex() {
  const res = await fetch("data/index.json", { cache: "no-cache" });
  return res.json();
}

async function renderCourses() {
  actions.innerHTML = "";
  const idx = await loadIndex();
  if (!idx.courses.length) {
    app.innerHTML = `<div class="empty">아직 코스가 없습니다.</div>`;
    return;
  }
  app.innerHTML = `<h1>코스</h1><div class="list">` +
    idx.courses.map(c => `
      <a class="card" href="#/c/${c.id}">
        <div class="title">${esc(c.name)}</div>
        <div class="meta">${c.files.length}개 문서</div>
      </a>`).join("") + `</div>`;
}

async function renderCourse(courseId) {
  actions.innerHTML = "";
  const idx = await loadIndex();
  const course = idx.courses.find(c => c.id === courseId);
  if (!course) { app.innerHTML = `<div class="empty">코스를 찾을 수 없습니다.</div>`; return; }
  app.innerHTML =
    `<div class="crumb"><a href="#/">코스</a> /</div>` +
    `<h1>${esc(course.name)}</h1>` +
    (course.files.length ? `<div class="list">` +
      course.files.map(f => `
        <a class="card" href="#/r/${f.id}">
          <div class="title">${esc(f.title)}</div>
          <div class="meta">${f.date} · ${fmtDur(f.duration_sec)} · ${f.paragraphs}문단</div>
        </a>`).join("") + `</div>`
      : `<div class="empty">아직 문서가 없습니다.</div>`);
}

async function renderDoc(docId) {
  const res = await fetch(`data/results/${docId}.json`, { cache: "no-cache" });
  if (!res.ok) { app.innerHTML = `<div class="empty">문서를 찾을 수 없습니다.</div>`; return; }
  const doc = await res.json();

  actions.innerHTML = `<button class="toggle" id="ko-toggle">한국어 숨기기</button>`;
  document.getElementById("ko-toggle").onclick = () => {
    document.body.classList.toggle("hide-ko");
    document.getElementById("ko-toggle").textContent =
      document.body.classList.contains("hide-ko") ? "한국어 보이기" : "한국어 숨기기";
  };

  app.innerHTML =
    `<div class="doc-head">
       <div class="crumb"><a href="#/">코스</a> / <a href="#/c/${doc.course}">${esc(doc.course)}</a> /</div>
       <h1>${esc(doc.title)}</h1>
       <div class="crumb">${doc.date} · ${fmtDur(doc.duration_sec)}</div>
     </div>` +
    doc.paragraphs.map(p => `
      <div class="para">
        <div class="t">${fmtT(p.t || 0)}</div>
        <div class="en">${esc(p.en)}</div>
        <div class="ko">${esc(p.ko)}</div>
      </div>`).join("");
  window.scrollTo(0, 0);
}

function route() {
  document.body.classList.remove("hide-ko");
  const hash = location.hash || "#/";
  const mCourse = hash.match(/^#\/c\/(.+)$/);
  const mDoc = hash.match(/^#\/r\/(.+)$/);
  if (mDoc) renderDoc(decodeURIComponent(mDoc[1]));
  else if (mCourse) renderCourse(decodeURIComponent(mCourse[1]));
  else renderCourses();
}
window.addEventListener("hashchange", route);
route();
