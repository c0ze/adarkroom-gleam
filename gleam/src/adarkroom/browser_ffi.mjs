export function openUrl(url) {
  window.open(url);
}

export function onKeys(down, up) {
  document.addEventListener("keydown", (e) => down(e.key));
  document.addEventListener("keyup", (e) => up(e.key));
}
