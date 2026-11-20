const outcomes = new Set(["complete", "consumed", "failed", "cancelled"]);

export function createQueue(maxConcurrent = 1) {
  if (!Number.isInteger(maxConcurrent) || maxConcurrent < 1) {
    throw new RangeError("maxConcurrent must be a positive integer");
  }

  return {
    maxConcurrent,
    pending: [],
    active: [],
  };
}

// Keep the File reference, but snapshot only the metadata needed after the
// user's route or selection changes. File contents are never read.
export function snapshotItem({ id, inputKey, file, destinationFolder = null }) {
  if (!id || !inputKey || !file) {
    throw new TypeError("id, inputKey, and file are required");
  }

  return {
    id,
    inputKey,
    file,
    destinationFolder,
    relativePath: file.webkitRelativePath || file.name,
    metadata: {
      name: file.name,
      size: file.size,
      type: file.type,
      lastModified: file.lastModified,
    },
  };
}

export function enqueue(queue, items) {
  const knownIds = new Set([
    ...queue.pending.map((item) => item.id),
    ...queue.active.map((item) => item.id),
  ]);
  const added = [];

  for (const item of items) {
    if (!item?.id) throw new TypeError("queued items must have an id");
    if (knownIds.has(item.id)) continue;
    knownIds.add(item.id);
    added.push(item);
  }

  return {
    ...queue,
    pending: [...queue.pending, ...added],
  };
}

export function activatePending(queue) {
  const available = Math.max(0, queue.maxConcurrent - queue.active.length);
  const activated = queue.pending.slice(0, available);

  if (activated.length === 0) return { queue, activated };

  return {
    queue: {
      ...queue,
      pending: queue.pending.slice(activated.length),
      active: [...queue.active, ...activated],
    },
    activated,
  };
}

export function settle(queue, id, outcome = "complete") {
  if (!outcomes.has(outcome)) {
    throw new TypeError(`unsupported queue outcome: ${outcome}`);
  }

  const activeItem = queue.active.find((item) => item.id === id);
  const pendingItem = queue.pending.find((item) => item.id === id);
  const released = activeItem || pendingItem;

  if (!released) return { queue, released: null, outcome };

  return {
    queue: {
      ...queue,
      pending: queue.pending.filter((item) => item.id !== id),
      active: queue.active.filter((item) => item.id !== id),
    },
    released,
    outcome,
  };
}
