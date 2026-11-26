(function () {
  var mq = function (q) { return window.matchMedia && window.matchMedia(q).matches; };
  var reduce = mq("(prefers-reduced-motion: reduce)");

  var items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0.06 });
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
    var preload = function (src) {
      if (cache[src]) return;
      var i = new Image();
      i.src = src;
      cache[src] = i;
    };
    var render = function () {
      var src = "img/" + shots[state.de][state.layout];
      if (img.getAttribute("src") === src) return;
      img.classList.add("fading");
      var next = new Image();
      next.onload = next.onerror = function () {
        img.src = src;
        img.alt = deNames[state.de] + " in the " + layoutNames[state.layout] + " layout";
        cap.textContent = deNames[state.de] + ", " + layoutNames[state.layout] + " layout";
        img.classList.remove("fading");
      };
      next.src = src;
    };
    box.querySelectorAll("button").forEach(function (b) {
      var key = b.hasAttribute("data-layout") ? "layout" : "de";
      b.addEventListener("click", function () {
        state[key] = b.getAttribute("data-" + key);
        b.parentNode.querySelectorAll("button").forEach(function (o) {
          o.setAttribute("aria-pressed", o === b ? "true" : "false");
        });
        render();
      });
      b.addEventListener("pointerenter", function () {
        preload("img/" + shots[b.getAttribute("data-de") || state.de][b.getAttribute("data-layout") || state.layout]);
      });
    });
  });

  var menu = document.querySelector("[data-menu]");
  if (menu) {
    var setMenu = function (open) {
      menu.setAttribute("aria-expanded", open ? "true" : "false");
      document.body.classList.toggle("menu-open", open);
    };
    menu.addEventListener("click", function () { setMenu(menu.getAttribute("aria-expanded") !== "true"); });
    document.getElementById(menu.getAttribute("aria-controls")).addEventListener("click", function (e) {
      if (e.target.closest("a")) setMenu(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && document.body.classList.contains("menu-open")) { setMenu(false); menu.focus(); }
    });
    window.matchMedia("(min-width: 901px)").addEventListener("change", function (m) { if (m.matches) setMenu(false); });
  }

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

  var hero = document.querySelector("[data-hero]");
  var cv = hero && hero.querySelector("[data-field]");
  if (!cv) return;
  var visible = true;
  var send = function () {};
  var setIdle = function () {
    var on = visible && !document.hidden;
    hero.classList.toggle("idle", !on);
    send({ t: "run", on: on });
  };
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (e) { visible = e[0].isIntersecting; setIdle(); }).observe(hero);
  }
  document.addEventListener("visibilitychange", setIdle);

  var conn = navigator.connection || {};
  var low = reduce || conn.saveData || /2g/.test(conn.effectiveType || "") ||
    mq("(pointer: coarse)") || window.innerWidth < 760 ||
    (navigator.deviceMemory && navigator.deviceMemory < 4) ||
    (navigator.hardwareConcurrency && navigator.hardwareConcurrency < 4);
  if (low) return;

  function field(cv, out) {
    var VS = "attribute vec2 a;void main(){gl_Position=vec4(a,0.,1.);}";
    var FS = [
      "#ifdef GL_FRAGMENT_PRECISION_HIGH",
      "precision highp float;",
      "#else",
      "precision mediump float;",
      "#endif",
      "uniform vec3 R;uniform float T;uniform vec3 M;",
      "vec3 pal(float s){",
      "vec3 a=vec3(.10,.92,.84),b=vec3(.24,.76,.95),c=vec3(.45,.50,.95),d=vec3(.64,.32,.98);",
      "s=clamp(s,0.,1.)*3.;",
      "return s<1.?mix(a,b,s):s<2.?mix(b,c,s-1.):mix(c,d,s-2.);}",
      "float h(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}",
      "void main(){",
      "vec2 o=vec2(.5*R.x,R.y-.5*R.z);",
      "vec2 p=(gl_FragCoord.xy-o)/R.z;",
      "float cs=.9,sn=.436;",
      "vec2 q=vec2(cs*p.x+sn*p.y,-sn*p.x+cs*p.y);",
      "vec2 m=(M.xy-o)/R.z;m=vec2(cs*m.x+sn*m.y,-sn*m.x+cs*m.y);",
      "vec3 col=vec3(.014,.016,.04)+vec3(.012,.004,.03)*clamp(.6-p.y,0.,2.);",
      "col+=vec3(.04,.36,.38)*.12*exp(-dot(p-vec2(-.95,.5),p-vec2(-.95,.5))*1.4);",
      "col+=vec3(.36,.16,.7)*.16*exp(-dot(p-vec2(.95,-.45),p-vec2(.95,-.45))*1.2);",
      "float sc=1.-.7*exp(-(p.x*p.x*.95+(p.y+.02)*(p.y+.02)*3.6));",
      "vec3 acc=vec3(0.);",
      "for(int i=0;i<5;i++){",
      "float f=float(i);",
      "float x=q.x;",
      "float y=-.06+(f-2.)*.075+.2*sin(x*.85+T*.14+f*.32)+.085*sin(x*1.9-T*.21+f*.8)+.03*sin(x*3.6+T*.33+f*1.9);",
      "vec2 dm=q-m;float pull=M.z*exp(-dot(dm,dm)*6.);",
      "y+=(m.y-y)*.2*pull;",
      "float d=q.y-y;",
      "float tw=abs(sin(x*1.15+T*.17+f*.55));",
      "float w=.004+.05*tw;",
      "float body=exp(-d*d/(w*w))*(.16+.5*(1.-tw));",
      "float haze=exp(-abs(d)*(9.-f*.6))*.05;",
      "float e1=abs(d)-w;float edge=exp(-e1*e1*14000.)*(.12+.3*tw);",
      "float pulse=.55+.45*sin(x*1.5-T*.6+f*.45);",
      "float spark=pow(max(0.,sin(x*.7-T*.75+f*.9)),28.);",
      "float fade=smoothstep(-1.7,-.5,x)*smoothstep(1.8,.6,x);",
      "vec3 c=pal(.5+x*.38+.1*sin(T*.09+f*.9));",
      "acc+=c*fade*((body+edge)*pulse+haze+(body+edge)*spark*1.4)*(1.+pull*.8);",
      "}",
      "col+=acc*sc;",
      "col=1.-exp(-col*1.6);",
      "col*=1.-.3*smoothstep(.6,1.5,length(p*vec2(.6,1.)));",
      "col+=(h(gl_FragCoord.xy+fract(T)*37.)-.5)/96.;",
      "gl_FragColor=vec4(col,1.);",
      "}"
    ].join("\n");
    var gl;
    try {
      gl = cv.getContext("webgl", { alpha: false, antialias: false, depth: false, stencil: false, premultipliedAlpha: false, preserveDrawingBuffer: false, powerPreference: "low-power", failIfMajorPerformanceCaveat: true });
    } catch (e) { gl = null; }
    var dbg = gl && gl.getExtension("WEBGL_debug_renderer_info");
    if (!gl || (dbg && /swiftshader|llvmpipe|softpipe|software|basic render/i.test(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL)))) { out("fail"); return function () {}; }
    var sh = function (type, src) {
      var o = gl.createShader(type);
      gl.shaderSource(o, src);
      gl.compileShader(o);
      return o;
    };
    var pr = gl.createProgram();
    gl.attachShader(pr, sh(gl.VERTEX_SHADER, VS));
    gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(pr);
    var par = gl.getExtension("KHR_parallel_shader_compile");
    var tick = typeof requestAnimationFrame === "function" ? function (f) { return requestAnimationFrame(f); } : function (f) { return setTimeout(function () { f(performance.now()); }, 16); };
    var scale = 0.75, cw = 0, ch = 0, vh = 0, w = 0, h = 0, uR, uT, uM;
    var px = 0.5, py = 0.5, tx = 0.5, ty = 0.5, pm = 0, tm = 0;
    var raf = 0, last = 0, t = 4, slow = 0, frames = 0, shown = false, dead = false, ready = false, run = false;
    var size = function () {
      var s = Math.min(scale, Math.sqrt(1200000 / Math.max(1, cw * ch)));
      w = cv.width = Math.max(2, Math.round(cw * s));
      h = cv.height = Math.max(2, Math.round(ch * s));
      gl.viewport(0, 0, w, h);
    };
    var setup = function () {
      if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return false;
      gl.useProgram(pr);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      var loc = gl.getAttribLocation(pr, "a");
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      uR = gl.getUniformLocation(pr, "R");
      uT = gl.getUniformLocation(pr, "T");
      uM = gl.getUniformLocation(pr, "M");
      return true;
    };
    var frame = function (now) {
      raf = 0;
      if (dead || !run || !cw) return;
      if (!ready) {
        if (par && !gl.getProgramParameter(pr, par.COMPLETION_STATUS_KHR)) { raf = tick(frame); return; }
        if (!setup()) { dead = true; out("fail"); return; }
        ready = true;
      }
      var dt = last ? Math.min(now - last, 100) : 16.7;
      last = now;
      t += dt / 1000;
      if (t > 4000) t = 4;
      px += (tx - px) * 0.045;
      py += (ty - py) * 0.045;
      pm += (tm - pm) * 0.03;
      gl.uniform3f(uR, w, h, Math.min(h, vh * h / ch));
      gl.uniform1f(uT, t);
      gl.uniform3f(uM, px * w, (1 - py) * h, pm);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!shown) { shown = true; out("on"); }
      if (++frames > 20) {
        slow = dt > 26 ? slow + 1 : Math.max(0, slow - 1);
        if (slow > 40) {
          slow = 0;
          if (scale > 0.4) { scale *= 0.75; size(); } else { dead = true; return; }
        }
      }
      raf = tick(frame);
    };
    if (cv.addEventListener) cv.addEventListener("webglcontextlost", function (e) { e.preventDefault(); dead = true; out("fail"); });
    return function (m) {
      if (m.t === "size") { cw = m.w; ch = m.h; vh = m.vh; scale = Math.min(m.dpr, 1) * 0.75; size(); }
      else if (m.t === "ptr") { tx = m.x; ty = m.y; tm = m.m; }
      else if (m.t === "run") run = m.on;
      if (run && !raf && !dead) { last = 0; raf = tick(frame); }
    };
  }

  var recv = function (m) {
    if (m === "on") cv.classList.add("on");
    else if (m === "fail") cv.classList.remove("on");
  };
  var start = function () {
    var worker = null;
    if (cv.transferControlToOffscreen && window.Worker && window.OffscreenCanvas) {
      try {
        var src = "var h;onmessage=function(e){var d=e.data;if(d.t==='init')h=(" + field.toString() + ")(d.c,function(m){postMessage(m)});else if(h)h(d)};";
        worker = new Worker(URL.createObjectURL(new Blob([src], { type: "text/javascript" })));
        var oc = cv.transferControlToOffscreen();
        worker.onmessage = function (e) { recv(e.data); };
        worker.postMessage({ t: "init", c: oc }, [oc]);
        send = function (m) { worker.postMessage(m); };
      } catch (e) { worker = null; }
    }
    if (!worker) send = field(cv, recv);
    var resize = function () {
      send({ t: "size", w: cv.clientWidth, h: cv.clientHeight, vh: window.innerHeight, dpr: window.devicePixelRatio || 1 });
    };
    resize();
    if ("ResizeObserver" in window) new ResizeObserver(resize).observe(cv);
    else window.addEventListener("resize", resize);
    if (mq("(hover: hover) and (pointer: fine)")) {
      hero.addEventListener("pointermove", function (e) {
        var r = cv.getBoundingClientRect();
        send({ t: "ptr", x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height, m: 1 });
      }, { passive: true });
      hero.addEventListener("pointerleave", function () { send({ t: "ptr", x: 0.5, y: 0.5, m: 0 }); });
    }
    setIdle();
  };

  var go = function () {
    if ("requestIdleCallback" in window) requestIdleCallback(start, { timeout: 1200 });
    else setTimeout(start, 200);
  };
  if (document.readyState === "complete") go();
  else window.addEventListener("load", go, { once: true });
})();
