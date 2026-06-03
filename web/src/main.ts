import { loadFormatter, formatJson } from "./wasm_bridge";

const btn    = document.getElementById("btn") as HTMLButtonElement;
const input  = document.getElementById("input") as HTMLTextAreaElement;
const output = document.getElementById("output") as HTMLPreElement;
const status = document.getElementById("status") as HTMLSpanElement;

try {
  await loadFormatter();
  btn.textContent = "Format";
  btn.disabled    = false;
  status.textContent = "WASM ready";
  status.className   = "ok";
} catch (e) {
  status.textContent = `Failed to load WASM: ${e}`;
  status.className   = "error";
}

btn.addEventListener("click", () => {
  try {
    output.textContent = formatJson(input.value);
    status.textContent = "OK";
    status.className   = "ok";
  } catch (e) {
    output.textContent = "";
    status.textContent = `${e}`;
    status.className   = "error";
  }
});

input.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) btn.click();
});