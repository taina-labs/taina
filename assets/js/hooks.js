// Hooks mínimos, todo o resto é LiveView. Antes de adicionar um hook novo,
// verifique se um binding nativo (phx-viewport-*, phx-drop-target, JS.*)
// já resolve.

// Escrita na área de transferência. navigator.clipboard só existe em origem
// segura e a instalação canônica é http://taina.local, então o caminho
// moderno nem sempre está lá; sem ele, cai para o execCommand (deprecado,
// mas universal e não exige origem segura; precisa rodar no gesto do clique,
// o que os dois hooks garantem, o handler é síncrono).
const legacyCopy = (text) => {
  const el = document.createElement("textarea");
  el.value = text;
  // display:none faz o iOS se recusar a copiar: fixo, invisível, intocável.
  el.style.position = "fixed";
  el.style.opacity = "0";
  el.style.pointerEvents = "none";
  document.body.appendChild(el);
  el.focus();
  el.select();
  el.setSelectionRange(0, text.length); // iOS exige o range explícito
  let ok = false;
  try {
    ok = document.execCommand("copy");
  } catch {
    ok = false;
  }
  el.remove();
  return ok;
};

const writeClipboard = (text) => {
  if (navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(text).catch(() => {
      if (!legacyCopy(text)) throw new Error("clipboard unavailable");
    });
  }
  return new Promise((resolve, reject) =>
    legacyCopy(text) ? resolve() : reject(new Error("clipboard unavailable")),
  );
};

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
    // Foco entra no visualizador: sem isso o Tab caminha pela tela atrás do
    // diálogo (role="dialog" aria-modal="true").
    this.el.querySelector("#viewer-close")?.focus();

    this.onKey = (e) => {
      // e.repeat: tecla segurada não pode spammar o servidor (cada seta é um
      // get_file + patch).
      if (e.repeat) return;
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
        // Gesto nascido na beira da tela é do navegador (voltar), não nosso:
        // no iOS/Android um swipe da borda dispara o histórico junto.
        const fromEdge =
          this.startX < 24 || this.startX > window.innerWidth - 24;
        // Só gesto horizontal troca de foto; rolagem vertical não.
        if (!fromEdge && Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) {
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

// Troca progressiva: o `md` entra primeiro e o original substitui quando
// baixa. Só age quando o servidor mandou `data-full` (dentro do orçamento).
const FullSwap = {
  mounted() {
    this.preload();
  },
  updated() {
    this.preload();
  },
  preload() {
    const full = this.el.dataset.full;
    if (!full) return;
    const img = new Image();
    img.onload = () => {
      if (this.el.isConnected && this.el.dataset.full === full) this.el.src = full;
    };
    img.src = full;
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
      // Arquivo vindo do sistema operacional (não é um item nosso): só evita
      // que o navegador navegue para o arquivo e derrube o LiveView.
      if (!dragged) return e.preventDefault();
      const drop = e.target.closest("[data-drop-folder]");
      if (!drop || drop.dataset.dropFolder === dragged.id) return;
      e.preventDefault();
      drop.classList.add("is-drop");
    });

    this.el.addEventListener("dragleave", (e) => {
      const drop = e.target.closest("[data-drop-folder]");
      if (drop) drop.classList.remove("is-drop");
    });

    this.el.addEventListener("drop", (e) => {
      // Mesmo caso do dragover: arquivo do SO não vira navegação.
      if (!dragged) {
        e.preventDefault();
        return;
      }
      const drop = e.target.closest("[data-drop-folder]");
      if (!drop) return clearDragState();
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

// Auto-fecha o flash acionando o phx-click do botão de fechar (que limpa no
// servidor e esconde). Cancela o timer se o elemento sair antes e re-arma
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
    this.timer = setTimeout(
      () => this.el.querySelector("button")?.click(),
      Number(this.el.dataset.timeout) || 4000,
    );
  },
};

// Armadilha de foco do modal: Tab circula só entre os controles do diálogo e
// o gatilho que abriu o modal recebe o foco de volta quando ele sai da árvore.
const ModalTrap = {
  mounted() {
    this.trigger = document.activeElement;
    const modal = this.el.querySelector(".modal");
    const focusables = modal
      ? modal.querySelectorAll(
          "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])",
        )
      : [];
    if (focusables.length > 0) focusables[0].focus();
    else modal?.focus();
    this.onKey = (e) => {
      if (e.key !== "Tab" || focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };
    this.el.addEventListener("keydown", this.onKey);
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKey);
    if (this.trigger?.isConnected) this.trigger.focus();
  },
};

// Mostrar/ocultar senha: alterna o type do input alvo entre "password" e
// "text". Estado no próprio botão (aria-pressed + rótulo vindo dos
// data-attrs, que chegam traduzidos do servidor). Puro cliente: a senha não
// sai da tela e não há nada a decidir no servidor.
const PasswordToggle = {
  mounted() {
    this.input = document.getElementById(this.el.dataset.target);
    this.sync = () => {
      if (!this.input) return;
      const shown = this.input.type === "text";
      this.el.setAttribute("aria-pressed", String(shown));
      this.el.setAttribute(
        "aria-label",
        shown ? this.el.dataset.labelHide : this.el.dataset.labelShow,
      );
    };
    this.el.addEventListener("click", () => {
      if (!this.input) return;
      this.input.type = this.input.type === "password" ? "text" : "password";
      this.sync();
    });
    this.sync();
  },
  updated() {
    // O patch do LiveView pode restaurar type="password" (o atributo vem do
    // servidor, no validate do wizard): re-sincroniza o botão com o estado
    // real do input. O input volta a existir junto, mas re-resolve o alvo
    // caso o patch o tenha trocado.
    this.input = document.getElementById(this.el.dataset.target) || this.input;
    this.sync();
  },
};

export default {
  Clipboard,
  ViewerNav,
  FullSwap,
  DragClass,
  Share,
  FlashAutoDismiss,
  DnD,
  ModalTrap,
  PasswordToggle,
};
