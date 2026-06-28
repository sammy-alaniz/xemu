#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  BlobBlockDevice,
  MemoryBlockDevice,
  OverlayBlockDevice,
  SyncMemoryBlockDevice,
  overlayFromSnapshot,
  serializeOverlaySnapshot,
} from "../browser/xbox-boot/block-storage.mjs";

const sectorSize = 512;
const imageSize = 16 * 1024 * 1024;
const randomReadCount = 96;
const randomReadSectors = 3;

function makeImage(size) {
  const bytes = new Uint8Array(size);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 31 + (i >>> 8) * 17 + 0xa5) & 0xff;
  }
  return bytes;
}

function hash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertEqual(name, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${name}: expected=${expected} actual=${actual}`);
  }
}

function assertBytes(name, actual, expected) {
  assertEqual(`${name}.length`, actual.byteLength, expected.byteLength);
  const actualHash = hash(actual);
  const expectedHash = hash(expected);
  if (actualHash !== expectedHash) {
    throw new Error(`${name}: expected_sha256=${expectedHash} actual_sha256=${actualHash}`);
  }
}

function lcg(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
  };
}

async function expectRangeFailure(device) {
  try {
    await device.readAt(device.size - 16, 32);
  } catch (error) {
    if (error instanceof RangeError) {
      return;
    }
    throw error;
  }
  throw new Error("expected out-of-range read to fail");
}

const image = makeImage(imageSize);
const blobDevice = new BlobBlockDevice(new Blob([image]), { name: "selftest-hdd" });
const maxLba = Math.floor(imageSize / sectorSize) - randomReadSectors;
const next = lcg(0x58454d55);
const hashes = [];

for (let i = 0; i < randomReadCount; i++) {
  const lba = next() % maxLba;
  const actual = await blobDevice.readSectors(lba, randomReadSectors);
  const offset = lba * sectorSize;
  const expected = image.slice(offset, offset + randomReadSectors * sectorSize);
  assertBytes(`random-read-${i}`, actual, expected);
  hashes.push(hash(actual).slice(0, 12));
}

const sparseOffset = 7 * 1024 * 1024 + 123;
const sparseLength = 4099;
const sparseActual = await blobDevice.readAt(sparseOffset, sparseLength);
const sparseExpected = image.slice(sparseOffset, sparseOffset + sparseLength);
assertBytes("sparse-byte-read", sparseActual, sparseExpected);

await expectRangeFailure(blobDevice);

const memoryBase = new MemoryBlockDevice(image.slice(), { name: "overlay-base" });
const overlay = new OverlayBlockDevice(memoryBase, { chunkSize: 4096 });
const writeOffset = 4096 - 37;
const writeBytes = new Uint8Array(8192 + 73);
for (let i = 0; i < writeBytes.length; i++) {
  writeBytes[i] = (0x5a ^ (i * 13)) & 0xff;
}

await overlay.writeAt(writeOffset, writeBytes);
const overlayActual = await overlay.readAt(writeOffset - 128, writeBytes.length + 256);
const overlayExpected = image.slice(writeOffset - 128, writeOffset + writeBytes.length + 128);
overlayExpected.set(writeBytes, 128);
assertBytes("overlay-readback", overlayActual, overlayExpected);

const flush = await overlay.flush();
assertEqual("overlay.flush.writes", flush.writes, 1);

const snapshot = overlay.exportChunks();
const reloadedOverlay = new OverlayBlockDevice(
  new BlobBlockDevice(new Blob([image]), { name: "reloaded-base" }),
  { chunkSize: 4096, chunks: snapshot },
);
const reloadedActual = await reloadedOverlay.readAt(writeOffset - 128, writeBytes.length + 256);
assertBytes("overlay-reloaded-readback", reloadedActual, overlayExpected);

const serializedSnapshot = serializeOverlaySnapshot(overlay);
const serializedSnapshotText = JSON.stringify(serializedSnapshot);
const persistedOverlay = overlayFromSnapshot(
  new BlobBlockDevice(new Blob([image]), { name: "persisted-base" }),
  JSON.parse(serializedSnapshotText),
);
const persistedActual = await persistedOverlay.readAt(writeOffset - 128, writeBytes.length + 256);
assertBytes("overlay-persisted-readback", persistedActual, overlayExpected);

const syncDevice = new SyncMemoryBlockDevice(image.slice(), { name: "sync-callback-memory", chunkSize: 4096 });
const syncWriteOffset = 4096 * 5 - 19;
const syncWriteBytes = new Uint8Array(4096 * 3 + 211);
for (let i = 0; i < syncWriteBytes.length; i++) {
  syncWriteBytes[i] = (0xc3 + i * 7 + (i >>> 3)) & 0xff;
}
syncDevice.writeFrom(syncWriteBytes, syncWriteOffset);
const syncReadback = new Uint8Array(syncWriteBytes.length);
syncDevice.readInto(syncReadback, syncWriteOffset);
assertBytes("sync-memory-readback", syncReadback, syncWriteBytes);

const syncSnapshot = syncDevice.flushSnapshot();
if (!syncSnapshot) {
  throw new Error("expected sync memory snapshot after write");
}
const syncSnapshotText = JSON.stringify(syncSnapshot);
const syncPersistedOverlay = overlayFromSnapshot(
  new BlobBlockDevice(new Blob([image]), { name: "sync-persisted-base" }),
  JSON.parse(syncSnapshotText),
);
const syncPersistedActual = await syncPersistedOverlay.readAt(syncWriteOffset - 64, syncWriteBytes.length + 128);
const syncPersistedExpected = image.slice(syncWriteOffset - 64, syncWriteOffset + syncWriteBytes.length + 64);
syncPersistedExpected.set(syncWriteBytes, 64);
assertBytes("sync-memory-persisted-readback", syncPersistedActual, syncPersistedExpected);

const totalRequested = blobDevice.stats.bytesRead;
const maxExpectedRead = randomReadCount * randomReadSectors * sectorSize + sparseLength;
assertEqual("blob.bytesRead", totalRequested, maxExpectedRead);

console.log([
  "BROWSER_BLOCK_SELFTEST",
  "result=pass",
  `image_bytes=${imageSize}`,
  `sector_size=${sectorSize}`,
  `random_reads=${randomReadCount}`,
  `blob_read_calls=${blobDevice.stats.readCalls}`,
  `blob_bytes_read=${blobDevice.stats.bytesRead}`,
  `overlay_chunks=${flush.chunks}`,
  `overlay_bytes_written=${flush.bytesWritten}`,
  `overlay_snapshot_chunks=${snapshot.length}`,
  "overlay_reload_readback=yes",
  `overlay_serialized_bytes=${serializedSnapshotText.length}`,
  "overlay_persisted_readback=yes",
  `sync_snapshot_chunks=${syncSnapshot.chunks.length}`,
  `sync_snapshot_bytes=${syncSnapshotText.length}`,
  "sync_snapshot_readback=yes",
  `first_hash=${hashes[0]}`,
  `last_hash=${hashes[hashes.length - 1]}`,
].join(" "));
