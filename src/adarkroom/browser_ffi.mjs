export function openUrl(url) {
  window.open(url, "_blank", "noopener");
}

export function onKeys(down, up) {
  // Arrow keys would otherwise scroll the page while steering the ascent.
  const swallow = (e) => {
    if (e.key.startsWith("Arrow")) {
      e.preventDefault();
    }
  };
  // Typing into a text box (the save code) is not walking or flying.
  const typing = (e) => {
    const tag = e.target && e.target.tagName;
    return tag === "TEXTAREA" || tag === "INPUT";
  };
  document.addEventListener("keydown", (e) => {
    if (typing(e)) return;
    swallow(e);
    down(e.key);
  });
  document.addEventListener("keyup", (e) => {
    if (typing(e)) return;
    swallow(e);
    up(e.key);
  });
}

export function reload() {
  window.location.reload();
}

export function setTitle(title) {
  document.title = title;
}

// The original appends css/dark.css titled darkenLights and toggles its
// `disabled`; the body class carries the port's own dark rules (index.html)
// for the <button>s the original's div-qualified selectors can't reach.
export function setLightsOff(off) {
  let link = document.getElementById("darkenLights");
  if (off && link === null) {
    link = document.createElement("link");
    link.id = "darkenLights";
    link.rel = "stylesheet";
    link.href = "/css/dark.css";
    document.head.appendChild(link);
  }
  if (link !== null) link.disabled = !off;
  document.body.classList.toggle("lightsOff", off);
}
