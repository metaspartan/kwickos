(function () {
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    items.forEach(function (el) { io.observe(el); });
  }

  var shots = {
    kde: { macos: "layout-macos.png", windows: "layout-windows.png", linux: "layout-linux.png" },
    gnome: { macos: "vm-gnome-macos.png", windows: "vm-gnome-windows.png", linux: "vm-gnome-linux.png" },
    hypr: { macos: "vm-tiling-macos.png", windows: "vm-tiling-windows.png", linux: "vm-tiling-linux.png" }
  };
  var deNames = { kde: "KDE Plasma", gnome: "GNOME", hypr: "Hyprland" };
  var layoutNames = { macos: "macOS", windows: "Windows", linux: "Linux" };

  document.querySelectorAll("[data-switcher]").forEach(function (box) {
    var img = box.querySelector("[data-view]");
    var cap = box.querySelector("[data-caption]");
    var state = { layout: "macos", de: "kde" };
    var cache = {};
    function preload(src) {
      if (cache[src]) return;
      var i = new Image();
      i.src = src;
      cache[src] = i;
    }
    function render() {
      var src = "img/" + shots[state.de][state.layout];
      var label = deNames[state.de] + ", " + layoutNames[state.layout] + " layout";
      if (img.getAttribute("src") === src) return;
      img.classList.add("fading");
      var next = new Image();
      next.onload = next.onerror = function () {
        img.src = src;
        img.alt = deNames[state.de] + " in the " + layoutNames[state.layout] + " layout";
        cap.textContent = label;
        img.classList.remove("fading");
      };
      next.src = src;
    }
    box.querySelectorAll("button").forEach(function (b) {
      b.addEventListener("click", function () {
        var key = b.hasAttribute("data-layout") ? "layout" : "de";
        state[key] = b.getAttribute("data-" + (key === "layout" ? "layout" : "de"));
        b.parentNode.querySelectorAll("button").forEach(function (o) {
          o.setAttribute("aria-pressed", o === b ? "true" : "false");
        });
        render();
      });
      b.addEventListener("pointerenter", function () {
        var de = b.getAttribute("data-de") || state.de;
        var l = b.getAttribute("data-layout") || state.layout;
        preload("img/" + shots[de][l]);
      });
    });
  });

  document.querySelectorAll("[data-copy]").forEach(function (b) {
    b.addEventListener("click", function () {
      var el = document.getElementById(b.getAttribute("data-copy"));
      if (!el || !navigator.clipboard) return;
      navigator.clipboard.writeText(el.textContent).then(function () {
        b.textContent = "Copied";
        setTimeout(function () { b.textContent = "Copy"; }, 1600);
      });
    });
  });
})();
