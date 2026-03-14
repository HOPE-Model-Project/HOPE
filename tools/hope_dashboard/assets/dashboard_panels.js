(function () {
  const PANEL_MAX_Z = 200;
  const LAYOUT_STORAGE_KEY = "hope-dashboard-panel-layout-v1";
  let panelZSeed = 10;

  function px(value) {
    return Number(String(value || "").replace("px", "")) || 0;
  }

  function clamp(value, minValue, maxValue) {
    return Math.max(minValue, Math.min(maxValue, value));
  }

  function dispatchResize() {
    window.dispatchEvent(new Event("resize"));
  }

  function rememberDefaults(panel) {
    if (panel.dataset.hopeDefaultsReady === "1") {
      return;
    }
    panel.dataset.defaultTop = panel.style.top || "0px";
    panel.dataset.defaultLeft = panel.style.left || "0px";
    panel.dataset.defaultWidth = panel.style.width || "320px";
    panel.dataset.defaultHeight = panel.style.height || "220px";
    panel.dataset.defaultZIndex = panel.style.zIndex || "1";
    panel.dataset.hopeDefaultsReady = "1";
  }

  function restoreDefaults(panel) {
    if (!panel) {
      return;
    }
    rememberDefaults(panel);
    panel.style.top = panel.dataset.defaultTop;
    panel.style.left = panel.dataset.defaultLeft;
    panel.style.width = panel.dataset.defaultWidth;
    panel.style.height = panel.dataset.defaultHeight;
    panel.style.zIndex = panel.dataset.defaultZIndex;
  }

  function snapshotPanel(panel) {
    return {
      id: panel.id,
      top: panel.style.top || "0px",
      left: panel.style.left || "0px",
      width: panel.style.width || "320px",
      height: panel.style.height || "220px",
      zIndex: panel.style.zIndex || "1"
    };
  }

  function saveLayout(canvas) {
    if (!canvas || !window.localStorage) {
      return;
    }
    const panels = Array.from(canvas.querySelectorAll(".floating-panel")).map(snapshotPanel);
    try {
      window.localStorage.setItem(LAYOUT_STORAGE_KEY, JSON.stringify(panels));
    } catch (_err) {
    }
  }

  function loadSavedLayout() {
    if (!window.localStorage) {
      return null;
    }
    try {
      const raw = window.localStorage.getItem(LAYOUT_STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (_err) {
      return null;
    }
  }

  function applyLayout(canvas, layout) {
    if (!canvas || !Array.isArray(layout)) {
      return;
    }
    layout.forEach(function (item) {
      if (!item || !item.id) {
        return;
      }
      const panel = document.getElementById(item.id);
      if (!panel) {
        return;
      }
      panel.style.top = item.top || panel.style.top;
      panel.style.left = item.left || panel.style.left;
      panel.style.width = item.width || panel.style.width;
      panel.style.height = item.height || panel.style.height;
      panel.style.zIndex = item.zIndex || panel.style.zIndex;
    });
    dispatchResize();
    window.setTimeout(dispatchResize, 60);
  }

  function initPanel(panel, canvas) {
    if (!panel || panel.dataset.hopePanelReady === "1") {
      return;
    }
    const handle = panel.querySelector(".panel-drag-handle");
    if (!handle) {
      return;
    }

    panel.dataset.hopePanelReady = "1";
    rememberDefaults(panel);

    let dragging = false;
    let startX = 0;
    let startY = 0;
    let startLeft = 0;
    let startTop = 0;

    handle.addEventListener("pointerdown", function (event) {
      if (window.innerWidth <= 1100) {
        return;
      }
      if (event.target.closest("input,button,.Select-control,.Select-menu-outer,.js-plotly-plot")) {
        return;
      }
      dragging = true;
      startX = event.clientX;
      startY = event.clientY;
      startLeft = panel.offsetLeft;
      startTop = panel.offsetTop;
      panelZSeed = Math.min(panelZSeed + 1, PANEL_MAX_Z);
      panel.style.zIndex = String(panelZSeed);
      handle.setPointerCapture(event.pointerId);
      event.preventDefault();
    });

    handle.addEventListener("pointermove", function (event) {
      if (!dragging) {
        return;
      }
      const maxLeft = Math.max(0, canvas.clientWidth - panel.offsetWidth);
      const maxTop = Math.max(0, canvas.clientHeight - panel.offsetHeight);
      const nextLeft = clamp(startLeft + event.clientX - startX, 0, maxLeft);
      const nextTop = clamp(startTop + event.clientY - startY, 0, maxTop);
      panel.style.left = nextLeft + "px";
      panel.style.top = nextTop + "px";
      dispatchResize();
    });

    function stopDragging(event) {
      if (!dragging) {
        return;
      }
      dragging = false;
      try {
        handle.releasePointerCapture(event.pointerId);
      } catch (_err) {
      }
      dispatchResize();
    }

    handle.addEventListener("pointerup", stopDragging);
    handle.addEventListener("pointercancel", stopDragging);

    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(function () {
        dispatchResize();
      });
      observer.observe(panel);
    }
  }

  function initPanels() {
    const canvas = document.getElementById("panel-canvas");
    if (!canvas) {
      return;
    }
    canvas.querySelectorAll(".floating-panel").forEach(function (panel) {
      initPanel(panel, canvas);
    });
    dispatchResize();
  }

  function initResetButton() {
    const button = document.getElementById("reset-layout");
    const canvas = document.getElementById("panel-canvas");
    if (!button || !canvas || button.dataset.hopeResetReady === "1") {
      return;
    }
    button.dataset.hopeResetReady = "1";
    button.addEventListener("click", function () {
      canvas.querySelectorAll(".floating-panel").forEach(function (panel) {
        restoreDefaults(panel);
      });
      panelZSeed = 10;
      dispatchResize();
      window.setTimeout(dispatchResize, 60);
    });
  }

  function initLayoutButtons() {
    const canvas = document.getElementById("panel-canvas");
    const saveButton = document.getElementById("save-layout");
    const restoreButton = document.getElementById("restore-saved-layout");

    if (saveButton && saveButton.dataset.hopeSaveReady !== "1") {
      saveButton.dataset.hopeSaveReady = "1";
      saveButton.addEventListener("click", function () {
        saveLayout(canvas);
      });
    }

    if (restoreButton && restoreButton.dataset.hopeRestoreReady !== "1") {
      restoreButton.dataset.hopeRestoreReady = "1";
      restoreButton.addEventListener("click", function () {
        applyLayout(canvas, loadSavedLayout());
      });
    }
  }

  function copyComputedStyles(source, target) {
    const computed = window.getComputedStyle(source);
    for (let i = 0; i < computed.length; i += 1) {
      const prop = computed[i];
      target.style.setProperty(
        prop,
        computed.getPropertyValue(prop),
        computed.getPropertyPriority(prop)
      );
    }
  }

  function cloneWithStyles(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return document.createTextNode(node.textContent || "");
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return document.createTextNode("");
    }

    const clone = node.cloneNode(false);
    copyComputedStyles(node, clone);

    if (node instanceof HTMLCanvasElement) {
      const img = document.createElement("img");
      try {
        img.src = node.toDataURL();
      } catch (_err) {
        img.alt = "canvas";
      }
      img.width = node.width;
      img.height = node.height;
      copyComputedStyles(node, img);
      return img;
    }

    if (node instanceof HTMLInputElement || node instanceof HTMLTextAreaElement) {
      clone.setAttribute("value", node.value);
    }

    if (node instanceof HTMLSelectElement) {
      Array.from(clone.options || []).forEach(function (option, idx) {
        option.selected = node.options[idx] && node.options[idx].selected;
      });
    }

    Array.from(node.childNodes).forEach(function (child) {
      clone.appendChild(cloneWithStyles(child));
    });
    return clone;
  }

  function downloadDataUrl(dataUrl, filename) {
    const link = document.createElement("a");
    link.href = dataUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  function computeCaptureSize(element) {
    const rootRect = element.getBoundingClientRect();
    let maxBottom = 0;

    const candidates = [];
    const toolbar = document.getElementById("dashboard-toolbar");
    if (toolbar) {
      candidates.push(toolbar);
    }
    element.querySelectorAll(".floating-panel").forEach(function (panel) {
      candidates.push(panel);
    });
    const toggle = document.getElementById("collapse-toggle");
    if (toggle) {
      candidates.push(toggle);
    }

    candidates.forEach(function (node) {
      if (!node) {
        return;
      }
      const rect = node.getBoundingClientRect();
      const bottom = rect.bottom - rootRect.top;
      if (bottom > maxBottom) {
        maxBottom = bottom;
      }
    });

    const width = Math.ceil(Math.max(element.clientWidth, rootRect.width));
    const height = Math.ceil(Math.max(320, maxBottom + 24));
    return { width: width, height: height };
  }

  function captureElementAsPng(element, filename) {
    if (!element) {
      return;
    }
    const captureSize = computeCaptureSize(element);
    const width = captureSize.width;
    const height = captureSize.height;
    const clone = cloneWithStyles(element);
    clone.setAttribute("xmlns", "http://www.w3.org/1999/xhtml");
    clone.style.margin = "0";
    clone.style.width = width + "px";
    clone.style.height = height + "px";

    const svg = `
      <svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">
        <foreignObject x="0" y="0" width="100%" height="100%">
          ${new XMLSerializer().serializeToString(clone)}
        </foreignObject>
      </svg>
    `;
    const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const img = new Image();
    img.onload = function () {
      const canvas = document.createElement("canvas");
      const scale = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.max(1, Math.floor(width * scale));
      canvas.height = Math.max(1, Math.floor(height * scale));
      const ctx = canvas.getContext("2d");
      ctx.scale(scale, scale);
      ctx.fillStyle = window.getComputedStyle(document.body).backgroundColor || "#ffffff";
      ctx.fillRect(0, 0, width, height);
      ctx.drawImage(img, 0, 0, width, height);
      URL.revokeObjectURL(url);
      downloadDataUrl(canvas.toDataURL("image/png"), filename);
    };
    img.onerror = function () {
      URL.revokeObjectURL(url);
    };
    img.src = url;
  }

  function ensureHtml2Canvas() {
    if (window.html2canvas) {
      return Promise.resolve(window.html2canvas);
    }
    if (window.__hopeHtml2CanvasPromise) {
      return window.__hopeHtml2CanvasPromise;
    }
    window.__hopeHtml2CanvasPromise = new Promise(function (resolve, reject) {
      const script = document.createElement("script");
      script.src = "https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js";
      script.async = true;
      script.onload = function () {
        if (window.html2canvas) {
          resolve(window.html2canvas);
        } else {
          reject(new Error("html2canvas loaded but unavailable"));
        }
      };
      script.onerror = function () {
        reject(new Error("Failed to load html2canvas"));
      };
      document.head.appendChild(script);
    });
    return window.__hopeHtml2CanvasPromise;
  }

  function initScreenshotButton() {
    const button = document.getElementById("screenshot-dashboard");
    if (!button || button.dataset.hopeScreenshotReady === "1") {
      return;
    }
    button.dataset.hopeScreenshotReady = "1";
    button.addEventListener("click", function () {
      const root = document.getElementById("app-root");
      const filename = "hope-dashboard-screenshot.png";
      button.disabled = true;
      ensureHtml2Canvas()
        .then(function (html2canvas) {
          const captureSize = computeCaptureSize(root);
          return html2canvas(root, {
            backgroundColor: null,
            useCORS: true,
            scale: Math.min(window.devicePixelRatio || 1, 2),
            scrollX: 0,
            scrollY: -window.scrollY,
            width: captureSize.width,
            height: captureSize.height,
            windowWidth: captureSize.width,
            windowHeight: captureSize.height
          });
        })
        .then(function (canvas) {
          downloadDataUrl(canvas.toDataURL("image/png"), filename);
        })
        .catch(function (_err) {
          captureElementAsPng(root, filename);
        })
        .finally(function () {
          button.disabled = false;
        });
    });
  }

  function initMapClickBridge() {
    const graph = document.getElementById("network-graph");
    if (!graph || graph.dataset.hopeMapClickReady === "1") {
      return;
    }
    const plot = graph.querySelector(".js-plotly-plot");
    if (!plot || typeof plot.on !== "function") {
      return;
    }
    graph.dataset.hopeMapClickReady = "1";
    plot.on("plotly_click", function (eventData) {
      if (!eventData || !eventData.points || !eventData.points.length) {
        return;
      }
      const point = eventData.points[0];
      const custom = point.customdata;
      if (!Array.isArray(custom) || custom[0] !== "bus") {
        return;
      }
      if (window.dash_clientside && typeof window.dash_clientside.set_props === "function") {
        window.dash_clientside.set_props("map-click-store", {
          data: {
            bus: custom[1],
            shiftKey: !!(eventData.event && eventData.event.shiftKey),
            ts: Date.now()
          }
        });
      }
    });
  }

  document.addEventListener("DOMContentLoaded", initPanels);
  document.addEventListener("DOMContentLoaded", initResetButton);
  document.addEventListener("DOMContentLoaded", initLayoutButtons);
  document.addEventListener("DOMContentLoaded", initScreenshotButton);
  document.addEventListener("DOMContentLoaded", initMapClickBridge);
  document.addEventListener("dashrendered", function () {
    initPanels();
    initResetButton();
    initLayoutButtons();
    initScreenshotButton();
    initMapClickBridge();
  });
  setInterval(function () {
    initPanels();
    initResetButton();
    initLayoutButtons();
    initScreenshotButton();
    initMapClickBridge();
  }, 1200);
})();
