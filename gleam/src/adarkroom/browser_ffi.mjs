export function openUrl(url) {
  window.open(url);
}

export function onKeys(down, up) {
  // Arrow keys would otherwise scroll the page while steering the ascent.
  const swallow = (e) => {
    if (e.key.startsWith("Arrow")) {
      e.preventDefault();
    }
  };
  document.addEventListener("keydown", (e) => {
    swallow(e);
    down(e.key);
  });
  document.addEventListener("keyup", (e) => {
    swallow(e);
    up(e.key);
  });
}
