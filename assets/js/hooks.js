// Hooks mínimos, todo o resto é LiveView. Antes de adicionar um hook novo,
// verifique se um binding nativo (phx-viewport-*, phx-drop-target, JS.*)
// já resolve.

// Copia o atributo data-copy para a área de transferência e avisa o servidor
// (feedback "copiado!" fica por conta do LiveView).
const Clipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy;
      if (!text) return;
      navigator.clipboard
        .writeText(text)
        .then(() => this.pushEvent("copied", {}));
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
    this.el.addEventListener(
      "touchstart",
      (e) => {
        this.startX = e.touches[0].clientX;
      },
      { passive: true },
    );
    this.el.addEventListener(
      "touchend",
      (e) => {
        if (this.startX === null) return;
        const delta = e.changedTouches[0].clientX - this.startX;
        if (delta > 48) this.pushEvent("prev", {});
        if (delta < -48) this.pushEvent("next", {});
        this.startX = null;
      },
      { passive: true },
    );
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
    this.el.addEventListener("dragleave", () => toggle(false));
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
        navigator.share({ title, url }).catch(() => {});
      } else {
        navigator.clipboard
          .writeText(url)
          .then(() => this.pushEvent("copied", {}));
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

// Auto-fecha o flash após 4s acionando o próprio phx-click do botão (que
// limpa no servidor e esconde). Cancela o timer se o elemento sair antes.
const FlashAutoDismiss = {
  mounted() {
    this.timer = setTimeout(() => this.el.click(), 4000);
  },
  destroyed() {
    clearTimeout(this.timer);
  },
};

export default { Clipboard, ViewerNav, DragClass, Share, FlashAutoDismiss, DnD };
