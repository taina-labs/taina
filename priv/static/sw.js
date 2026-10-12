// Service worker do Tainá: torna o app instalável e mostra uma tela de
// "sem conexão" amigável, SEM tentar funcionar offline de verdade. A UI é
// LiveView e depende do socket /live, então o SW nunca intercepta o socket nem
// rotas dinâmicas. Navegações são sempre network-first, e só os assets com
// fingerprint (imutáveis) ficam em cache, então uma atualização nunca serve
// arquivo velho.

// A versão do cache é a alavanca de atualização: mudou o PRECACHE (ou o
// offline.html), suba o sufixo para o install regravar tudo e o activate
// descartar o cache antigo. Assets com fingerprint ficam fora daqui: entram
// pelo fetch (cache-first) e a versão nova chega com o nome novo.
const CACHE = "taina-shell-v1";
const OFFLINE_URL = "/offline.html";

// Assets estáticos seguros para pré-cachear (a tela offline e os ícones). O
// manifest NÃO entra: ele muda sem fingerprint, e é servido pelo
// stale-while-revalidate do fetch (abaixo).
const PRECACHE = [
  OFFLINE_URL,
  "/icons/favicon.svg",
  "/icons/web-app-manifest-192x192.png",
  "/icons/web-app-manifest-512x512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)),
  );
  // Aplica o SW novo imediatamente, sem esperar abas antigas fecharem.
  self.skipWaiting();
  // (mantém o cache atual e descarta os antigos no 'activate')
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  // Só GET; deixa POST/PUT/etc. passarem direto.
  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Só mesma origem.
  if (url.origin !== self.location.origin) return;

  // Nunca intercepta o socket LiveView nem o healthcheck.
  if (url.pathname === "/health" || url.pathname.startsWith("/live")) return;

  // Navegações (HTML): network-first, com a tela offline como último recurso.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() =>
        caches.match(OFFLINE_URL, { ignoreSearch: true }),
      ),
    );
    return;
  }

  // Assets com fingerprint são imutáveis: cache-first é seguro.
  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(
      caches.match(request).then(
        (hit) =>
          hit ||
          fetch(request).then((res) => {
            const copy = res.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
            return res;
          }),
      ),
    );
    return;
  }

  // Ícones e manifest (qualquer arquivo sob /manifest.*): stale-while-revalidate.
  if (url.pathname.startsWith("/icons/") || url.pathname.startsWith("/manifest")) {
    event.respondWith(
      caches.match(request).then((hit) => {
        const network = fetch(request).then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
          return res;
        });
        return hit || network;
      }),
    );
  }
});
