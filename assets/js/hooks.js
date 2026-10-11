// Hooks mínimos, todo o resto é LiveView. Antes de adicionar um hook novo,
// verifique se um binding nativo (phx-viewport-*, phx-drop-target, JS.*)
// já resolve.

// Escrita na área de transferência: navigator.clipboard não existe em origens
// inseguras (a instalação canônica é http://taina.local), então a promessa
// nasce rejeitada quando a API não está disponível. Nunca lança no escuro.
const writeClipboard = (text) =>
  navigator.clipboard?.writeText
    ? navigator.clipboard.writeText(text)
    : Promise.reject(new Error("clipboard unavailable"));

// Copia o atributo data-copy para a área de transferência e avisa o servidor
// (feedback "copiado!" fica por conta do LiveView).
const Clipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy;
      if (!text) return;
      writeClipboard(text)
        .then(() => this.pushEvent("copied", {}))
        .catch(() => this.pushEvent("copy-failed", {}));
    });
  },
};

// Navegação do visualizador de fotos: setas/Esc no teclado e swipe no touch.
const ViewerNav = {
  mounted() {
    this.onKey = (e) => {
      if (e.key === "ArrowLeft") this.pushEvent("prev", {});
      if (e.key === "ArrowRight") this.pushEvent("next", {});
      if (e.key === "Escape") this.pushEvent("close", {});
    };
    window.addEventListener("keydown", this.onKey);

    this.startX = null;
    this.startY = null;
    this.el.addEventListener(
      "touchstart",
      (e) => {
        this.startX = e.touches[0].clientX;
        this.startY = e.touches[0].clientY;
      },
      { passive: true },
    );
    this.el.addEventListener(
      "touchend",
      (e) => {
        if (this.startX === null) return;
        const dx = e.changedTouches[0].clientX - this.startX;
        const dy = e.changedTouches[0].clientY - this.startY;
        // Só gesto horizontal troca de foto; rolagem vertical não.
        if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) {
          if (dx > 0) this.pushEvent("prev", {});
          else this.pushEvent("next", {});
        }
        this.startX = null;
        this.startY = null;
      },
      { passive: true },
    );
  },
  updated() {
    // Mantém a foto atual visível no meio da trilha. Aqui é só posicionamento
    // de scroll, sem animação (o movimento é do CSS).
    const current = this.el.querySelector(
      '.viewer__rail-item[aria-current="true"]',
    );
    if (current) current.scrollIntoView({ inline: "center", block: "nearest" });
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey);
  },
};

// Realce visual da dropzone durante o arrasto (o upload em si é o
// live_file_input com phx-drop-target).
const DragClass = {
  mounted() {
    const toggle = (on) => this.el.classList.toggle("is-dragover", on);
    this.el.addEventListener("dragover", (e) => {
      e.preventDefault();
      toggle(true);
    });
    this.el.addEventListener("dragleave", (e) => {
      // Transição para um elemento interno da dropzone não é saída.
      if (this.el.contains(e.relatedTarget)) return;
      toggle(false);
    });
    this.el.addEventListener("drop", () => toggle(false));
  },
};

// Web Share API (mobile): compartilha o link do convite pelo app que a
// comunidade já usa. Sem suporte (desktop), o LiveView esconde o botão? Não,
// degradamos copiando o link.
const Share = {
  mounted() {
    this.el.addEventListener("click", () => {
      const { title, url } = this.el.dataset;
      if (navigator.share) {
        navigator.share({ title, url }).catch((err) => {
          // AbortError: a pessoa cancelou o compartilhamento, nada a fazer.
          if (err?.name === "AbortError") return;
          // Outro erro cai no fallback de copiar o link.
          writeClipboard(url)
            .then(() => this.pushEvent("copied", {}))
            .catch(() => this.pushEvent("copy-failed", {}));
        });
      } else {
        writeClipboard(url)
          .then(() => this.pushEvent("copied", {}))
          .catch(() => this.pushEvent("copy-failed", {}));
      }
    });
  },
};

// Arrastar-e-soltar no navegador de arquivos: arrasta itens com [data-drag-id]
// e solta sobre pastas (ou o "Início") marcadas com [data-drop-folder].
// Delegação de eventos no container, um hook só cobre a lista inteira.
const DnD = {
  mounted() {
    let dragged = null;
    const clearDragState = () => {
      dragged = null;
      this.el
        .querySelectorAll(".is-drop")
        .forEach((el) => el.classList.remove("is-drop"));
    };

    this.el.addEventListener("dragstart", (e) => {
      const item = e.target.closest("[data-drag-id]");
      if (!item) return;
      dragged = { id: item.dataset.dragId, kind: item.dataset.dragKind };
      e.dataTransfer.effectAllowed = "move";
    });

    this.el.addEventListener("dragover", (e) => {
      const drop = e.target.closest("[data-drop-folder]");
      if (!drop || !dragged || drop.dataset.dropFolder === dragged.id) return;
      e.preventDefault();
      drop.classList.add("is-drop");
    });

    this.el.addEventListener("dragleave", (e) => {
      const drop = e.target.closest("[data-drop-folder]");
      if (drop) drop.classList.remove("is-drop");
    });

    this.el.addEventListener("drop", (e) => {
      const drop = e.target.closest("[data-drop-folder]");
      if (!drop || !dragged) return clearDragState();
      e.preventDefault();
      drop.classList.remove("is-drop");
      const target = drop.dataset.dropFolder;
      if (target !== dragged.id) {
        this.pushEvent("move-item", { id: dragged.id, kind: dragged.kind, target });
      }
      clearDragState();
    });

    this.el.addEventListener("dragend", () => clearDragState());
  },
};

// Auto-fecha o flash acionando o próprio phx-click do botão (que limpa no
// servidor e esconde). O aviso de erro fica mais tempo: é o que a pessoa
// precisa ler com calma. Cancela o timer se o elemento sair antes e re-arma
// quando a mensagem muda.
const FlashAutoDismiss = {
  mounted() {
    this.arm();
  },
  updated() {
    // O LiveView reusa o mesmo elemento entre avisos (o id é fixo), então o
    // timer do aviso anterior já disparou ou foi cancelado: precisa de um novo.
    this.arm();
  },
  destroyed() {
    clearTimeout(this.timer);
  },
  arm() {
    clearTimeout(this.timer);
    // Aviso novo no mesmo elemento: o `JS.hide()` de um clique anterior deixou
    // `display: none` inline, que o patch do LiveView não remove.
    this.el.style.display = "";
    const fallback = this.el.classList.contains("flash--error") ? 8000 : 4000;
    this.timer = setTimeout(
      () => this.el.click(),
      Number(this.el.dataset.timeout) || fallback,
    );
  },
};

// Atalhos de navegação Cmd/Ctrl+1..5 (briefing, desktop): só empurra o número
// para o servidor, que resolve o destino. O hook não guarda estado de
// navegação; a tela Conta documenta os pares.
const NavShortcuts = {
  mounted() {
    this.onKey = (e) => {
      // e.repeat: tecla segurada não pode spammar o servidor.
      if (e.repeat || e.altKey || !(e.metaKey || e.ctrlKey)) return;
      const index = Number(e.key);
      if (index >= 1 && index <= 5) {
        e.preventDefault();
        this.pushEvent("shortcut", { index });
      }
    };
    window.addEventListener("keydown", this.onKey);
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey);
  },
};

export default {
  Clipboard,
  ViewerNav,
  DragClass,
  Share,
  FlashAutoDismiss,
  DnD,
  NavShortcuts,
};
