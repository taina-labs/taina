import assert from "node:assert/strict";
import test from "node:test";

import {
  activatePending,
  cancelPending,
  createQueue,
  enqueue,
  pendingSnapshot,
  settle,
  snapshotItem,
} from "./upload_queue.js";

function item(id, inputKey = "files", destinationFolder = null, name = `${id}.txt`) {
  const file = {
    name,
    size: 12,
    type: "text/plain",
    lastModified: 123,
    webkitRelativePath: "",
  };
  return snapshotItem({ id, inputKey, file, destinationFolder });
}

test("one cap applies to pending files from every input", () => {
  let queue = createQueue(2);
  queue = enqueue(queue, [
    item("one", "files"),
    item("two", "folders"),
    item("three", "camera"),
  ]);

  const { queue: active, activated } = activatePending(queue);
  assert.deepEqual(activated.map(({ inputKey }) => inputKey), ["files", "folders"]);
  assert.equal(active.active.length, 2);
  assert.equal(active.pending.length, 1);
});

test("duplicate filenames remain separate items through UUID identity", () => {
  let queue = createQueue(3);
  queue = enqueue(queue, [
    item("uuid-one", "files", null, "photo.jpg"),
    item("uuid-two", "camera", null, "photo.jpg"),
  ]);

  const { queue: active, activated } = activatePending(queue);
  assert.equal(activated.length, 2);
  assert.notEqual(activated[0].id, activated[1].id);
  assert.equal(activated[0].metadata.name, activated[1].metadata.name);
  assert.equal(active.active.length, 2);
});

test("pending items become active only when a slot is available", () => {
  let queue = createQueue(1);
  queue = enqueue(queue, [item("first"), item("second")]);

  const first = activatePending(queue);
  assert.deepEqual(first.activated.map(({ id }) => id), ["first"]);
  assert.deepEqual(first.queue.pending.map(({ id }) => id), ["second"]);

  const noSlot = activatePending(first.queue);
  assert.deepEqual(noSlot.activated, []);
  assert.equal(noSlot.queue, first.queue);
});

test("pending snapshots expose display metadata without File contents", () => {
  let queue = createQueue(1);
  queue = enqueue(queue, [
    item("active", "files", null, "active.txt"),
    item("pending", "folders", "folder-at-selection", "same.txt"),
  ]);
  queue = activatePending(queue).queue;

  assert.deepEqual(pendingSnapshot(queue), [
    {
      queue_id: "pending",
      input_key: "folders",
      name: "same.txt",
      size: 12,
      destination_folder: "folder-at-selection",
      relative_path: "same.txt",
    },
  ]);
  assert.equal(Object.hasOwn(pendingSnapshot(queue)[0], "file"), false);
});

test("cancelling a pending duplicate name preserves the active and other item", () => {
  let queue = createQueue(1);
  queue = enqueue(queue, [
    item("active", "files", null, "same.txt"),
    item("cancel-me", "folders", null, "same.txt"),
    item("keep-me", "camera", null, "same.txt"),
  ]);
  queue = activatePending(queue).queue;

  const cancelled = cancelPending(queue, "cancel-me");
  assert.equal(cancelled.cancelled.id, "cancel-me");
  assert.deepEqual(cancelled.queue.active.map(({ id }) => id), ["active"]);
  assert.deepEqual(cancelled.queue.pending.map(({ id }) => id), ["keep-me"]);

  const released = settle(cancelled.queue, "active", "cancelled");
  assert.deepEqual(activatePending(released.queue).activated.map(({ id }) => id), ["keep-me"]);
});

test("completion frees a slot and the next pending item can start", () => {
  let queue = createQueue(1);
  queue = enqueue(queue, [item("first"), item("second")]);
  queue = activatePending(queue).queue;

  const completed = settle(queue, "first", "complete");
  const next = activatePending(completed.queue);
  assert.deepEqual(next.activated.map(({ id }) => id), ["second"]);
  assert.equal(next.queue.active.length, 1);
});

test("failure and cancellation free slots without blocking the queue", () => {
  for (const outcome of ["failed", "cancelled"]) {
    let queue = createQueue(1);
    queue = enqueue(queue, [item("first"), item("second")]);
    queue = activatePending(queue).queue;

    const released = settle(queue, "first", outcome);
    assert.equal(released.released.id, "first");
    const next = activatePending(released.queue);
    assert.deepEqual(next.activated.map(({ id }) => id), ["second"]);
  }
});

test("folder and relative-path values are snapshotted per selected file", () => {
  const file = {
    name: "image.jpg",
    size: 20,
    type: "image/jpeg",
    lastModified: 456,
    webkitRelativePath: "trip/day-one/image.jpg",
  };
  const selectedFolder = "folder-at-selection";
  const selected = snapshotItem({
    id: "uuid-folder",
    inputKey: "folders",
    file,
    destinationFolder: selectedFolder,
  });

  assert.equal(selected.file, file);
  assert.equal(selected.destinationFolder, "folder-at-selection");
  assert.equal(selected.relativePath, "trip/day-one/image.jpg");
  assert.deepEqual(selected.metadata, {
    name: "image.jpg",
    size: 20,
    type: "image/jpeg",
    lastModified: 456,
  });
});

test("enqueue ignores a repeated UUID without collapsing same-name files", () => {
  let queue = createQueue(3);
  queue = enqueue(queue, [item("same-id", "files", null, "same.txt")]);
  queue = enqueue(queue, [
    item("same-id", "camera", null, "other.txt"),
    item("other-id", "camera", null, "same.txt"),
  ]);

  assert.deepEqual(queue.pending.map(({ id }) => id), ["same-id", "other-id"]);
});
