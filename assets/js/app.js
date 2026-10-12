import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import hooks from "./hooks";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");

if (!csrfToken) {
  console.warn("CSRF token ausente no <meta name='csrf-token'>");
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: csrfToken ? { _csrf_token: csrfToken } : {},
  hooks,
});

// Barra de progresso nas navegações live e em uploads longos. A cor vem do
// token de marca no tokens.css, sem hex cru no JS.
const brandPrimary = getComputedStyle(document.documentElement)
  .getPropertyValue("--brand-primary")
  .trim();

topbar.config({
  className: "topbar",
  barColors: { 0: brandPrimary },
  shadowColor: "rgba(6, 10, 20, .4)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// Teclado virtual no iOS: o visualViewport encolhe sem redimensionar a janela.
// Com o teclado aberto a bottom-nav some (fixa, ficaria flutuando sobre as
// teclas); o limite de 120px separa "teclado de verdade" de barrinhas flutuantes.
if (window.visualViewport) {
  const vv = window.visualViewport;
  const sync = () => document.body.classList.toggle(
    "keyboard-open", vv.height < document.documentElement.clientHeight - 120);
  vv.addEventListener("resize", sync);
  sync();
}

liveSocket.connect();

// Exposto para debug no console (liveSocket.enableDebug(), etc.).
window.liveSocket = liveSocket;

// Registra o service worker (app instalável + tela offline). updateViaCache
// 'none' garante que o navegador sempre rebusque o sw.js para pegar versões
// novas. Falha silenciosa em navegadores sem suporte.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js", { updateViaCache: "none" })
      .catch((err) => console.warn("Falha ao registrar o service worker:", err));
  });
}
