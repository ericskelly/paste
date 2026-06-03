interface FormatterExports {
  memory: WebAssembly.Memory;
  getInputPtr: () => number;
  getOutputPtr: () => number;
  getOutputLen: () => number;
  formatJson: (inputLen: number) => number;
  reset: () => void;
}

const importObject = {
  env: {
    js_log: (ptr: number, len: number) => {
      const bytes = new Uint8Array((wasm as any).memory.buffer, ptr, len);
      console.log("[zig]", new TextDecoder().decode(bytes));
    },
  },
};

let wasm: FormatterExports | null = null;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export async function loadFormatter() {
    console.log("fetching wasm...");
    const result = await WebAssembly.instantiateStreaming(fetch("/main.wasm"), importObject);
    console.log("wasm loaded", result.instance.exports);
    wasm = result.instance.exports as unknown as FormatterExports;
}

function callFormatter(
    input: string,
    fn: (len: number) => number
): string {
    if (!wasm) throw new Error("WASM not loaded");

    wasm.reset();

    const inputBytes = encoder.encode(input);
    const inputPtr = wasm.getInputPtr();
    const memView = new Uint8Array(wasm.memory.buffer);
    memView.set(inputBytes, inputPtr);

    const code = fn(inputBytes.length);
    if (code !== 0) {
        throw new Error(`Formatter error: code ${code}`);
    }

    const outputPtr = wasm.getOutputPtr();
    const outputLen = wasm.getOutputLen();
    const outputBytes = new Uint8Array(wasm.memory.buffer, outputPtr, outputLen);

    return decoder.decode(outputBytes);
}

export function formatJson(input: string): string {
    console.log(`Formatting json with input ${input}`)
    const response = callFormatter(input, (len) => wasm!.formatJson(len));
    console.log(`Formatting response ${response}`);
    return response;
}