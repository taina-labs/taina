import {
  activatePending,
  createQueue,
  enqueue,
  cancelPending,
  pendingSnapshot,
  settle,
  snapshotItem,
} from "./upload_queue.js";

const terminalOutcomes = new Set(["complete", "consumed", "failed", "cancelled"]);
const releaseEventName = "upload-queue:release";

// Integration contract:
// - Put this hook on the element containing all native file inputs.
// - Mark each native input with data-upload-queue-input="stable-key". The
//   optional data-upload-queue-input-selector on the hook element overrides
//   the default [data-upload-queue-input] selector.
// - Set data-upload-queue-max-concurrent on the hook element.
// - The hook sends upload-queue:item with queue_id, input_key,
//   destination_folder, relative_path, client_name, and client_size before it
//   dispatches one public input event for that file. The server should retain
//   that metadata in per-input order and correlate it with the next native
//   upload entry for that input. queue_id, not the filename, is the identity.
// - After queue changes, upload_queue_pending reports pending item snapshots
//   with a monotonically increasing revision. The server may send
//   upload_queue_cancel with a queue_id to cancel a pending or active item.
// - Keep each reserved/active queue_id in the hook element's
//   data-upload-queue-active-ids attribute until its native entry is consumed.
//   The value is a whitespace- or comma-separated list. Removing an observed
//   id frees its slot. Alternatively, configure
//   data-upload-queue-entry-selector to select entry elements carrying
//   data-upload-queue-id and optional data-upload-queue-status. Each id must
//   appear at least once so a later disappearance can be distinguished from a
//   not-yet-accepted selection.
// - For an explicit error or cancellation, either render a terminal status
//   ("failed", "cancelled", "complete", or "consumed") on the selected entry,
//   or dispatch upload-queue:release on the hook element with
//   {detail: {id: queue_id, outcome: "failed" | "cancelled"}}.
//
// Native input/change/drop events are intercepted in capture phase. Only
// synthetic input events created here are allowed through to LiveView.
export const UploadQueueHook = {
  mounted() {
    const maxConcurrent = Number(this.el.dataset.uploadQueueMaxConcurrent) || 1;
    this.queue = createQueue(maxConcurrent);
    this.inputSelector =
      this.el.dataset.uploadQueueInputSelector || "[data-upload-queue-input]";
    this.entrySelector = this.el.dataset.uploadQueueEntrySelector || null;
    this.syntheticEvents = new WeakSet();
    this.reportedIds = new Set();
    this.dispatchChain = Promise.resolve();
    this.pendingRevision = 0;

    this.onInput = (event) => this.captureInput(event);
    this.onDrop = (event) => this.captureDrop(event);
    this.onRelease = (event) => this.release(event.detail);
    this.onPageLoadingStart = (event) => {
      if (event.detail?.kind === "redirect") this.setManagerVisibility(false);
    };

    this.el.addEventListener("input", this.onInput, true);
    this.el.addEventListener("change", this.onInput, true);
    this.el.addEventListener("drop", this.onDrop, true);
    this.el.addEventListener(releaseEventName, this.onRelease);
    window.addEventListener("phx:page-loading-start", this.onPageLoadingStart);
    this.cancelHandleRef = this.handleEvent("upload_queue_cancel", ({queue_id}) => {
      this.cancelQueueItem(queue_id);
    });
    this.visibilityHandleRef = this.handleEvent(
      "upload_manager_visibility",
      ({visible}) => this.setManagerVisibility(visible),
    );

    if (typeof MutationObserver !== "undefined") {
      this.observer = new MutationObserver(() => this.reconcile());
      this.observer.observe(this.el, {
        attributes: true,
        childList: true,
        subtree: true,
      });
    }
  },

  updated() {
    this.reconcile();
  },

  destroyed() {
    this.el.removeEventListener("input", this.onInput, true);
    this.el.removeEventListener("change", this.onInput, true);
    this.el.removeEventListener("drop", this.onDrop, true);
    this.el.removeEventListener(releaseEventName, this.onRelease);
    window.removeEventListener("phx:page-loading-start", this.onPageLoadingStart);
    this.removeHandleEvent(this.cancelHandleRef);
    this.removeHandleEvent(this.visibilityHandleRef);
    this.observer?.disconnect();
  },

  captureInput(event) {
    if (this.syntheticEvents.has(event)) return;

    const input = event.target;
    if (!this.isQueueInput(input)) return;

    const files = Array.from(input.files || []);
    if (files.length === 0) return;

    event.preventDefault();
    event.stopImmediatePropagation();

    this.queueFiles(input, files);
    this.replaceFiles(input, []);
  },

  captureDrop(event) {
    const files = Array.from(event.dataTransfer?.files || []);
    if (files.length === 0) return;

    const dropTarget = event.target?.closest?.("[phx-drop-target]");
    const targetId = dropTarget?.getAttribute("phx-drop-target");
    const input = targetId
      ? this.inputs().find((candidate) => candidate.id === targetId)
      : null;
    if (!input) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    this.queueFiles(input, files);
  },

  queueFiles(input, files) {
    const inputKey = this.inputKey(input);
    if (!inputKey) return;

    const destinationFolder = this.destinationFolder(input);
    const items = files.map((file) =>
      snapshotItem({
        id: this.newId(),
        inputKey,
        file,
        destinationFolder,
      }),
    );

    this.queue = enqueue(this.queue, items);
    this.pump();
  },

  pump() {
    const transition = activatePending(this.queue);
    this.queue = transition.queue;
    this.reportPending();

    for (const item of transition.activated) {
      this.dispatchChain = this.dispatchChain
        .then(() => this.forward(item))
        .catch(() => this.release({ id: item.id, outcome: "failed" }));
    }
  },

  async forward(item) {
    if (!this.isActive(item.id)) return;

    try {
      await this.pushEvent(this.el.dataset.uploadQueueEvent || "upload-queue:item", {
        queue_id: item.id,
        input_key: item.inputKey,
        destination_folder: item.destinationFolder,
        relative_path: item.relativePath,
        client_name: item.metadata.name,
        client_size: item.metadata.size,
      });
    } catch {
      this.release({ id: item.id, outcome: "failed" });
      return;
    }

    if (!this.isActive(item.id)) return;

    const input = this.inputs().find((candidate) => this.inputKey(candidate) === item.inputKey);
    if (!input || !this.replaceFiles(input, [item.file])) {
      this.release({ id: item.id, outcome: "failed" });
      return;
    }

    const event = new Event("input", { bubbles: true });
    this.syntheticEvents.add(event);
    input.dispatchEvent(event);
  },

  release(detail) {
    if (!detail?.id) return;
    const outcome = terminalOutcomes.has(detail.outcome) ? detail.outcome : "failed";
    const transition = settle(this.queue, detail.id, outcome);
    if (!transition.released) return;

    this.queue = transition.queue;
    this.reportedIds.delete(detail.id);
    this.pump();
  },

  cancelQueueItem(id) {
    if (!id) return;

    const pending = cancelPending(this.queue, id);
    if (pending.cancelled) {
      this.queue = pending.queue;
      this.pump();
      return;
    }

    const active = settle(this.queue, id, "cancelled");
    if (!active.released) return;

    this.queue = active.queue;
    this.reportedIds.delete(id);
    this.pump();
  },

  reportPending() {
    const event = this.el.dataset.uploadQueuePendingEvent || "upload_queue_pending";
    const revision = ++this.pendingRevision;
    this.pushEvent(event, { revision, items: pendingSnapshot(this.queue) }).catch(() => {});
  },

  setManagerVisibility(visible) {
    if (typeof visible !== "boolean") return;

    const container = this.el.closest("#upload-manager");
    if (!container) return;

    const hidden = !visible;
    container.hidden = hidden;
    container.inert = hidden;
    container.setAttribute("aria-hidden", String(hidden));
    container.style.display = hidden ? "none" : "";
  },

  reconcile() {
    const reports = this.readReports();
    if (!reports) return;

    for (const id of reports.ids) this.reportedIds.add(id);

    for (const item of [...this.queue.active]) {
      const status = reports.statuses.get(item.id);
      if (terminalOutcomes.has(status)) {
        this.release({ id: item.id, outcome: status });
      } else if (this.reportedIds.has(item.id) && !reports.ids.has(item.id)) {
        this.release({ id: item.id, outcome: "consumed" });
      }
    }
  },

  readReports() {
    if (this.entrySelector) {
      let entries;
      try {
        entries = this.el.querySelectorAll(this.entrySelector);
      } catch {
        return null;
      }

      const ids = new Set();
      const statuses = new Map();
      for (const entry of entries) {
        const id = entry.dataset.uploadQueueId;
        if (!id) continue;
        ids.add(id);
        statuses.set(id, entry.dataset.uploadQueueStatus || "active");
      }
      return { ids, statuses };
    }

    if (!this.el.hasAttribute("data-upload-queue-active-ids")) return null;

    const ids = new Set(
      this.el
        .getAttribute("data-upload-queue-active-ids")
        .split(/[,\s]+/)
        .filter(Boolean),
    );
    return { ids, statuses: new Map() };
  },

  inputs() {
    try {
      return Array.from(this.el.querySelectorAll(this.inputSelector)).filter((input) =>
        this.isFileInput(input),
      );
    } catch {
      return [];
    }
  },

  isQueueInput(input) {
    return this.isFileInput(input) && this.inputs().includes(input);
  },

  isFileInput(input) {
    return (
      typeof HTMLInputElement !== "undefined" &&
      input instanceof HTMLInputElement &&
      input.type === "file"
    );
  },

  inputKey(input) {
    return input.dataset.uploadQueueInput || input.id || null;
  },

  destinationFolder(input) {
    if (input.hasAttribute("data-upload-queue-folder")) {
      return input.dataset.uploadQueueFolder || null;
    }
    return this.el.dataset.uploadQueueFolder || null;
  },

  replaceFiles(input, files) {
    if (typeof DataTransfer === "undefined") return false;

    try {
      const transfer = new DataTransfer();
      for (const file of files) transfer.items.add(file);
      input.files = transfer.files;
      return true;
    } catch {
      return false;
    }
  },

  newId() {
    const crypto = globalThis.crypto;
    if (crypto?.randomUUID) return crypto.randomUUID();
    if (!crypto?.getRandomValues) throw new Error("secure UUID generation is unavailable");

    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
    return [
      hex.slice(0, 4).join(""),
      hex.slice(4, 6).join(""),
      hex.slice(6, 8).join(""),
      hex.slice(8, 10).join(""),
      hex.slice(10, 16).join(""),
    ].join("-");
  },

  isActive(id) {
    return this.queue.active.some((item) => item.id === id);
  },
};

export default UploadQueueHook;
