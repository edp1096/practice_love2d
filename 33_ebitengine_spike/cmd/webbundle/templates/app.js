"use strict";

const boot = document.getElementById("boot");
const status = document.getElementById("boot-status");
const fullscreen = document.getElementById("fullscreen");
let canvasReadinessPending = false;

function fail(error) {
  console.error(error);
  boot.classList.add("error");
  status.textContent = `실행 실패: ${error instanceof Error ? error.message : String(error)}`;
  document.documentElement.dataset.recreateReady = "error";
}

function canvasReady(canvas) {
  if (
    !canvas ||
    canvasReadinessPending ||
    boot.classList.contains("ready")
  ) {
    return;
  }
  canvasReadinessPending = true;
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (document.documentElement.dataset.recreateReady === "error") {
        return;
      }
      boot.classList.add("ready");
      status.textContent = "실행 중";
      document.documentElement.dataset.recreateReady = "true";
      canvas.setAttribute("aria-label", "고요한 숲의 수호자 게임 화면");
      canvas.focus({ preventScroll: true });
    });
  });
}

const canvasObserver = new MutationObserver(() => {
  canvasReady(document.querySelector("canvas"));
});
canvasObserver.observe(document.body, { childList: true });

fullscreen.addEventListener("click", async () => {
  const canvas = document.querySelector("canvas");
  if (!canvas) {
    return;
  }
  try {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else {
      await canvas.requestFullscreen();
    }
  } catch (error) {
    fail(error);
  }
});

async function instantiate(go) {
  const response = await fetch("game.wasm", { cache: "no-cache" });
  if (!response.ok) {
    throw new Error(`game.wasm HTTP ${response.status}`);
  }
  if (WebAssembly.instantiateStreaming) {
    try {
      return await WebAssembly.instantiateStreaming(
        response.clone(),
        go.importObject,
      );
    } catch (error) {
      console.warn("스트리밍 WASM 로딩을 사용할 수 없어 ArrayBuffer로 재시도합니다.", error);
    }
  }
  return WebAssembly.instantiate(
    await response.arrayBuffer(),
    go.importObject,
  );
}

async function start() {
  if (!globalThis.WebAssembly) {
    throw new Error("이 브라우저는 WebAssembly를 지원하지 않습니다.");
  }
  if (typeof Go !== "function") {
    throw new Error("Go WebAssembly 지원 스크립트를 불러오지 못했습니다.");
  }
  status.textContent = "WebAssembly를 초기화하는 중…";
  const go = new Go();
  const result = await instantiate(go);
  status.textContent = "게임을 시작하는 중…";

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js", {
      updateViaCache: "none",
    }).catch((error) => {
      console.warn("오프라인 캐시를 등록하지 못했습니다.", error);
    });
  }
  await go.run(result.instance);
  if (document.documentElement.dataset.recreateReady !== "error") {
    fail(new Error("게임 실행이 예기치 않게 종료되었습니다."));
  }
}

window.addEventListener("error", (event) => {
  if (event.error) {
    fail(event.error);
  }
});
window.addEventListener("unhandledrejection", (event) => {
  fail(event.reason);
});

start().catch(fail);
