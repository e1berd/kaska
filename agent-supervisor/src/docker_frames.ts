const HEADER_BYTES = 8;

export type StreamKind = "stdout" | "stderr";

export interface Frame {
  stream: StreamKind;
  payload: Uint8Array;
}

export class DockerFrameDecoder {
  #buffer: Uint8Array = new Uint8Array(0);

  push(chunk: Uint8Array): Frame[] {
    this.#buffer = concat(this.#buffer, chunk);
    const frames: Frame[] = [];

    while (this.#buffer.length >= HEADER_BYTES) {
      const size = new DataView(this.#buffer.buffer, this.#buffer.byteOffset + 4, 4).getUint32(0);
      if (this.#buffer.length < HEADER_BYTES + size) break;

      frames.push({
        stream: this.#buffer[0] === 2 ? "stderr" : "stdout",
        payload: this.#buffer.slice(HEADER_BYTES, HEADER_BYTES + size),
      });
      this.#buffer = this.#buffer.slice(HEADER_BYTES + size);
    }

    return frames;
  }
}

function concat(left: Uint8Array, right: Uint8Array): Uint8Array {
  if (left.length === 0) return right;
  const merged = new Uint8Array(left.length + right.length);
  merged.set(left, 0);
  merged.set(right, left.length);
  return merged;
}
