export const DEFAULT_SECTOR_SIZE = 512;

function assertInteger(name, value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative safe integer`);
  }
}

function assertRange(size, offset, length) {
  assertInteger("offset", offset);
  assertInteger("length", length);
  if (offset + length > size) {
    throw new RangeError(`read outside block device: offset=${offset} length=${length} size=${size}`);
  }
}

function sectorOffset(lba, count, sectorSize) {
  assertInteger("lba", lba);
  assertInteger("count", count);
  return { offset: lba * sectorSize, length: count * sectorSize };
}

function bytesToBase64(bytes) {
  if (!(bytes instanceof Uint8Array)) {
    throw new TypeError("bytesToBase64 requires Uint8Array bytes");
  }
  if (typeof Buffer !== "undefined") {
    return Buffer.from(bytes).toString("base64");
  }
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  if (typeof base64 !== "string") {
    throw new TypeError("base64ToBytes requires a string");
  }
  if (typeof Buffer !== "undefined") {
    return new Uint8Array(Buffer.from(base64, "base64"));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export class BlobBlockDevice {
  constructor(blob, options = {}) {
    if (!blob || typeof blob.size !== "number" || typeof blob.slice !== "function") {
      throw new TypeError("BlobBlockDevice requires a Blob or File-like object");
    }
    this.blob = blob;
    this.name = options.name || blob.name || "blob";
    this.size = blob.size;
    this.sectorSize = options.sectorSize || DEFAULT_SECTOR_SIZE;
    this.stats = { readCalls: 0, bytesRead: 0 };
  }

  async readAt(offset, length) {
    assertRange(this.size, offset, length);
    const buffer = await this.blob.slice(offset, offset + length).arrayBuffer();
    if (buffer.byteLength !== length) {
      throw new Error(`short read: expected=${length} actual=${buffer.byteLength}`);
    }
    this.stats.readCalls += 1;
    this.stats.bytesRead += length;
    return new Uint8Array(buffer);
  }

  async readSectors(lba, count = 1) {
    const range = sectorOffset(lba, count, this.sectorSize);
    return this.readAt(range.offset, range.length);
  }
}

export class MemoryBlockDevice {
  constructor(bytes, options = {}) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("MemoryBlockDevice requires Uint8Array bytes");
    }
    this.bytes = bytes;
    this.name = options.name || "memory";
    this.size = bytes.byteLength;
    this.sectorSize = options.sectorSize || DEFAULT_SECTOR_SIZE;
    this.stats = { readCalls: 0, bytesRead: 0, writeCalls: 0, bytesWritten: 0 };
  }

  async readAt(offset, length) {
    assertRange(this.size, offset, length);
    this.stats.readCalls += 1;
    this.stats.bytesRead += length;
    return this.bytes.slice(offset, offset + length);
  }

  async readSectors(lba, count = 1) {
    const range = sectorOffset(lba, count, this.sectorSize);
    return this.readAt(range.offset, range.length);
  }

  async writeAt(offset, bytes) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("writeAt requires Uint8Array bytes");
    }
    assertRange(this.size, offset, bytes.byteLength);
    this.bytes.set(bytes, offset);
    this.stats.writeCalls += 1;
    this.stats.bytesWritten += bytes.byteLength;
  }

  async flush() {
    return { writes: this.stats.writeCalls, bytesWritten: this.stats.bytesWritten };
  }
}

export class SyncMemoryBlockDevice {
  constructor(bytes, options = {}) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("SyncMemoryBlockDevice requires Uint8Array bytes");
    }
    this.bytes = bytes;
    this.name = options.name || "sync-memory";
    this.size = bytes.byteLength;
    this.sectorSize = options.sectorSize || DEFAULT_SECTOR_SIZE;
    this.chunkSize = options.chunkSize || 64 * 1024;
    this.dirtyChunkStarts = new Set();
    this.stats = { readCalls: 0, bytesRead: 0, writeCalls: 0, bytesWritten: 0 };
  }

  chunkStart(offset) {
    return Math.floor(offset / this.chunkSize) * this.chunkSize;
  }

  markDirtyRange(offset, length) {
    let cursor = offset;
    const end = offset + length;
    while (cursor < end) {
      const start = this.chunkStart(cursor);
      this.dirtyChunkStarts.add(start);
      cursor = Math.min(start + this.chunkSize, end);
    }
  }

  readInto(target, offset) {
    if (!(target instanceof Uint8Array)) {
      throw new TypeError("readInto requires Uint8Array target");
    }
    assertRange(this.size, offset, target.byteLength);
    target.set(this.bytes.subarray(offset, offset + target.byteLength));
    this.stats.readCalls += 1;
    this.stats.bytesRead += target.byteLength;
  }

  writeFrom(source, offset) {
    if (!(source instanceof Uint8Array)) {
      throw new TypeError("writeFrom requires Uint8Array source");
    }
    assertRange(this.size, offset, source.byteLength);
    this.bytes.set(source, offset);
    this.markDirtyRange(offset, source.byteLength);
    this.stats.writeCalls += 1;
    this.stats.bytesWritten += source.byteLength;
  }

  exportChunks() {
    return Array.from(this.dirtyChunkStarts)
      .sort((a, b) => a - b)
      .map((start) => {
        const end = Math.min(start + this.chunkSize, this.size);
        return [start, this.bytes.slice(start, end)];
      });
  }

  flushSnapshot() {
    if (this.dirtyChunkStarts.size === 0) {
      return null;
    }
    return serializeOverlaySnapshot(this);
  }
}

export class OverlayBlockDevice {
  constructor(base, options = {}) {
    if (!base || typeof base.readAt !== "function" || !Number.isSafeInteger(base.size)) {
      throw new TypeError("OverlayBlockDevice requires a readable block device");
    }
    this.base = base;
    this.name = options.name || `${base.name || "base"}+overlay`;
    this.size = base.size;
    this.sectorSize = base.sectorSize || DEFAULT_SECTOR_SIZE;
    this.chunkSize = options.chunkSize || 64 * 1024;
    this.chunks = new Map();
    this.stats = { readCalls: 0, bytesRead: 0, writeCalls: 0, bytesWritten: 0 };

    if (options.chunks) {
      for (const [start, bytes] of options.chunks) {
        this.importChunk(start, bytes);
      }
    }
  }

  chunkStart(offset) {
    return Math.floor(offset / this.chunkSize) * this.chunkSize;
  }

  async loadChunk(start) {
    const length = Math.min(this.chunkSize, this.size - start);
    return this.base.readAt(start, length);
  }

  async mutableChunk(start) {
    let chunk = this.chunks.get(start);
    if (!chunk) {
      chunk = await this.loadChunk(start);
      this.chunks.set(start, chunk);
    }
    return chunk;
  }

  async readAt(offset, length) {
    assertRange(this.size, offset, length);
    const out = await this.base.readAt(offset, length);
    let cursor = offset;
    const end = offset + length;

    while (cursor < end) {
      const start = this.chunkStart(cursor);
      const chunk = this.chunks.get(start);
      const chunkEnd = Math.min(start + this.chunkSize, this.size, end);
      if (chunk) {
        const fromChunk = cursor - start;
        const fromOut = cursor - offset;
        out.set(chunk.subarray(fromChunk, fromChunk + (chunkEnd - cursor)), fromOut);
      }
      cursor = chunkEnd;
    }

    this.stats.readCalls += 1;
    this.stats.bytesRead += length;
    return out;
  }

  async readSectors(lba, count = 1) {
    const range = sectorOffset(lba, count, this.sectorSize);
    return this.readAt(range.offset, range.length);
  }

  async writeAt(offset, bytes) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("writeAt requires Uint8Array bytes");
    }
    assertRange(this.size, offset, bytes.byteLength);
    let sourceOffset = 0;
    let cursor = offset;
    const end = offset + bytes.byteLength;

    while (cursor < end) {
      const start = this.chunkStart(cursor);
      const chunk = await this.mutableChunk(start);
      const chunkEnd = Math.min(start + this.chunkSize, this.size, end);
      const length = chunkEnd - cursor;
      chunk.set(bytes.subarray(sourceOffset, sourceOffset + length), cursor - start);
      sourceOffset += length;
      cursor = chunkEnd;
    }

    this.stats.writeCalls += 1;
    this.stats.bytesWritten += bytes.byteLength;
  }

  async flush() {
    return {
      chunks: this.chunks.size,
      writes: this.stats.writeCalls,
      bytesWritten: this.stats.bytesWritten,
    };
  }

  importChunk(start, bytes) {
    assertInteger("start", start);
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("importChunk requires Uint8Array bytes");
    }
    if (start % this.chunkSize !== 0) {
      throw new RangeError(`chunk start is not aligned: start=${start} chunkSize=${this.chunkSize}`);
    }
    const expectedLength = Math.min(this.chunkSize, this.size - start);
    if (expectedLength <= 0 || bytes.byteLength !== expectedLength) {
      throw new RangeError(`bad chunk length: start=${start} expected=${expectedLength} actual=${bytes.byteLength}`);
    }
    this.chunks.set(start, bytes.slice());
  }

  exportChunks() {
    return Array.from(this.chunks.entries())
      .sort(([a], [b]) => a - b)
      .map(([start, bytes]) => [start, bytes.slice()]);
  }
}

export function serializeOverlaySnapshot(overlay) {
  if (!overlay || typeof overlay.exportChunks !== "function") {
    throw new TypeError("serializeOverlaySnapshot requires an OverlayBlockDevice");
  }
  return {
    version: 1,
    size: overlay.size,
    sectorSize: overlay.sectorSize,
    chunkSize: overlay.chunkSize,
    chunks: overlay.exportChunks().map(([start, bytes]) => ({
      start,
      bytes: bytesToBase64(bytes),
    })),
  };
}

export function chunksFromOverlaySnapshot(snapshot, options = {}) {
  if (!snapshot || snapshot.version !== 1 || !Array.isArray(snapshot.chunks)) {
    throw new TypeError("unsupported overlay snapshot");
  }
  if (Number.isSafeInteger(options.size) && snapshot.size !== options.size) {
    throw new RangeError(`snapshot size mismatch: expected=${options.size} actual=${snapshot.size}`);
  }
  if (Number.isSafeInteger(options.chunkSize) && snapshot.chunkSize !== options.chunkSize) {
    throw new RangeError(`snapshot chunk size mismatch: expected=${options.chunkSize} actual=${snapshot.chunkSize}`);
  }
  return snapshot.chunks.map((chunk) => {
    if (!chunk || !Number.isSafeInteger(chunk.start)) {
      throw new TypeError("snapshot chunk has invalid start");
    }
    return [chunk.start, base64ToBytes(chunk.bytes)];
  });
}

export function overlayFromSnapshot(base, snapshot, options = {}) {
  return new OverlayBlockDevice(base, {
    ...options,
    chunkSize: snapshot.chunkSize,
    chunks: chunksFromOverlaySnapshot(snapshot, {
      size: base.size,
      chunkSize: snapshot.chunkSize,
    }),
  });
}
