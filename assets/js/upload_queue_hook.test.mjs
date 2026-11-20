import assert from "node:assert/strict";
import test from "node:test";

import UploadQueueHook from "./upload_queue_hook.js";

test("visibility updates the existing sticky manager container in place", () => {
  const attributes = new Map();
  const container = {
    hidden: false,
    inert: false,
    style: { display: "block" },
    setAttribute(name, value) {
      attributes.set(name, value);
    },
  };
  const hook = {
    el: {
      closest(selector) {
        assert.equal(selector, "#upload-manager");
        return container;
      },
    },
  };

  UploadQueueHook.setManagerVisibility.call(hook, false);
  assert.equal(container.hidden, true);
  assert.equal(container.inert, true);
  assert.equal(attributes.get("aria-hidden"), "true");
  assert.equal(container.style.display, "none");

  UploadQueueHook.setManagerVisibility.call(hook, true);
  assert.equal(container.hidden, false);
  assert.equal(container.inert, false);
  assert.equal(attributes.get("aria-hidden"), "false");
  assert.equal(container.style.display, "");
});

test("invalid visibility messages do not change the sticky container", () => {
  let lookups = 0;
  const hook = {
    el: {
      closest() {
        lookups += 1;
        return null;
      },
    },
  };

  UploadQueueHook.setManagerVisibility.call(hook, "false");
  assert.equal(lookups, 0);
});
