import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import hooks from "./hooks";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
});

// Barra de progresso nas navegações live e em uploads longos.
topbar.config({
  barColors: { 0: "#F2A65A" },
  shadowColor: "rgba(6, 10, 20, .4)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();

// Exposto para debug no console (liveSocket.enableDebug(), etc.).
window.liveSocket = liveSocket;
