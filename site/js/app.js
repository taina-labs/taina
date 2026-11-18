/* Ybaka, o site público do Tainá.
   Sem framework e sem dependência: só o que o HTML não faz sozinho.
   Functional core (funções puras) + imperative shell (DOM no fim). */
(() => {
  "use strict";

  const COPY_LABEL = "Copiar";
  const COPIED_LABEL = "Copiado";

  // ---------- abas (funções puras) ----------

  const activateTab = (list, panels, tab) => {
    list.querySelectorAll('[role="tab"]').forEach((el) => {
      const selected = el === tab;
      el.setAttribute("aria-selected", String(selected));
      el.tabIndex = selected ? 0 : -1;
    });
    panels.forEach((panel) => {
      panel.hidden = panel.id !== tab.getAttribute("aria-controls");
    });
  };

  const nextTabIndex = (key, current, total) => {
    if (key === "ArrowRight") return (current + 1) % total;
    if (key === "ArrowLeft") return (current - 1 + total) % total;
    if (key === "Home") return 0;
    if (key === "End") return total - 1;
    return null;
  };

  const initTabs = (root) => {
    const list = root.querySelector('[role="tablist"]');
    if (!list) return;
    const tabs = Array.from(list.querySelectorAll('[role="tab"]'));
    const panels = Array.from(root.querySelectorAll(".tabs__panel"));

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => activateTab(list, panels, tab));
      tab.addEventListener("keydown", (event) => {
        const target = nextTabIndex(event.key, tabs.indexOf(tab), tabs.length);
        if (target === null) return;
        event.preventDefault();
        tabs[target].focus();
        activateTab(list, panels, tabs[target]);
      });
    });
  };

  // ---------- copiar (funções puras) ----------

  const copyText = async (text) => {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    document.execCommand("copy");
    document.body.removeChild(area);
  };

  const initCopy = (button) => {
    const code = button.closest(".code")?.querySelector("code");
    if (!code) return;
    const label = button.querySelector("[data-copy-label]");

    button.addEventListener("click", async () => {
      try {
        await copyText(code.innerText);
        button.dataset.copied = "true";
        if (label) label.textContent = COPIED_LABEL;
        setTimeout(() => {
          button.dataset.copied = "false";
          if (label) label.textContent = COPY_LABEL;
        }, 2000);
      } catch (_error) {
        // Sem permissão de área de transferência: dá para selecionar à mão.
      }
    });
  };

  const wrapCodeBlock = (pre) => {
    if (pre.closest(".code") || !pre.querySelector("code")) return;

    const wrapper = document.createElement("div");
    wrapper.className = "code";

    const head = document.createElement("div");
    head.className = "code__head";

    const label = document.createElement("span");
    label.className = "code__label";
    label.textContent = "Código";

    const button = document.createElement("button");
    button.className = "copy-btn";
    button.type = "button";
    button.setAttribute("aria-label", "Copiar bloco de código");
    button.dataset.copy = "";

    const buttonLabel = document.createElement("span");
    buttonLabel.dataset.copyLabel = "";
    buttonLabel.textContent = COPY_LABEL;
    button.appendChild(buttonLabel);

    head.append(label, button);
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.append(head, pre);
  };

  const initCodeBlocks = (root) => {
    root.querySelectorAll(".prose pre").forEach(wrapCodeBlock);
  };

  const initTables = (root) => {
    root.querySelectorAll(".prose table").forEach((table) => {
      if (table.parentElement.classList.contains("prose__table-wrap")) return;

      const wrapper = document.createElement("div");
      wrapper.className = "prose__table-wrap";
      wrapper.tabIndex = 0;
      wrapper.setAttribute("role", "region");
      wrapper.setAttribute(
        "aria-label",
        table.caption?.textContent.trim() ||
          "Tabela ampla. Role horizontalmente para ver mais colunas.",
      );

      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  };

  // ---------- shell ----------

  const start = () => {
    initCodeBlocks(document);
    initTables(document);
    document.querySelectorAll("[data-tabs]").forEach(initTabs);
    document.querySelectorAll("[data-copy]").forEach(initCopy);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
