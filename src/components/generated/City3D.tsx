import React, { useEffect, useRef } from 'react';
export function City3D({
  city
}: {
  city: string;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const angle = useRef(0);
  const drag = useRef<{
    x: number;
    a: number;
  } | null>(null);
  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    const g = c.getContext('webgl', {
      antialias: true,
      alpha: true
    });
    if (!g) return;
    const v = `attribute vec3 p;attribute vec3 color;uniform float a;uniform float aspect;varying vec3 col;void main(){float ca=cos(a),sa=sin(a);float x=p.x*ca-p.z*sa;float z=p.x*sa+p.z*ca;float y=p.y*.84-z*.54;float d=18.0+z*.84+p.y*.54;gl_Position=vec4(x/(d*.70*aspect),y/(d*.70),.4/d,1.);col=color;}`;
    const f = `precision mediump float;varying vec3 col;void main(){gl_FragColor=vec4(col,1.);}`;
    const sh = (t: number, s: string) => {
      const q = g.createShader(t)!;
      g.shaderSource(q, s);
      g.compileShader(q);
      return q;
    };
    const pr = g.createProgram()!;
    g.attachShader(pr, sh(g.VERTEX_SHADER, v));
    g.attachShader(pr, sh(g.FRAGMENT_SHADER, f));
    g.linkProgram(pr);
    g.useProgram(pr);
    const arr: number[] = [];
    type P = [number, number, number];
    type C = [number, number, number];
    const tri = (a: P, b: P, c: P, k: C) => {
      [a, b, c].forEach(p => arr.push(...p, ...k));
    };
    const face = (a: P, b: P, c: P, d: P, k: C) => {
      tri(a, b, c, k);
      tri(a, c, d, k);
    };
    const cube = (x: number, y: number, z: number, w: number, h: number, d: number, k: C) => {
      let x0 = x - w / 2,
        x1 = x + w / 2,
        y0 = y,
        y1 = y + h,
        z0 = z - d / 2,
        z1 = z + d / 2;
      face([x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1], [Math.min(1, k[0] * 1.13), Math.min(1, k[1] * 1.13), Math.min(1, k[2] * 1.13)]);
      face([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [k[0] * .76, k[1] * .78, k[2] * .78]);
      face([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [k[0] * .87, k[1] * .88, k[2] * .87]);
      face([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [k[0] * .66, k[1] * .7, k[2] * .69]);
      face([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [k[0] * .83, k[1] * .85, k[2] * .82]);
    };
    cube(0, -.18, 0, 17, .25, 17, [.31, .41, .35]);
    for (let k = -7; k <= 7; k += 2) {
      cube(k, -.03, 0, .045, .02, 15, [.46, .54, .45]);
      cube(0, -.03, k, 15, .02, .045, [.46, .54, .45]);
    }
    cube(0, -.01, 0, 1, .035, 16, [.15, .21, .19]);
    cube(0, -.01, 0, 16, .035, 1, [.16, .22, .19]);
    let seed = city.split('').reduce((n, s) => n + s.charCodeAt(0), 17);
    const rand = () => {
      seed = seed * 1664525 + 1013904223 >>> 0;
      return seed / 4294967296;
    };
    const colors: C[] = [[.35, .48, .41], [.48, .57, .5], [.33, .43, .42], [.56, .58, .49], [.41, .51, .49], [.29, .39, .36]];
    for (let x = -6; x <= 6; x += 1.5) for (let z = -6; z <= 6; z += 1.5) {
      if (Math.abs(x) < 1.3 || Math.abs(z) < 1.3 || rand() < .16) continue;
      let w = .55 + rand() * .35,
        d = .55 + rand() * .35,
        h = .7 + Math.pow(rand(), 1.4) * 4.3;
      cube(x, .02, z, w, h, d, colors[Math.floor(rand() * colors.length)]);
      if (rand() > .6) cube(x, .02 + h, z, w * .82, .1, d * .82, [.77, .68, .45]);
    }
    cube(-2.3, .02, -2.4, .9, 5.6, .9, [.34, .46, .42]);
    cube(2.5, .02, -2.6, .8, 4.2, .8, [.51, .58, .5]);
    cube(-2.6, .02, 2.5, .7, 3.5, .8, [.44, .53, .48]);
    const data = new Float32Array(arr),
      buf = g.createBuffer()!;
    g.bindBuffer(g.ARRAY_BUFFER, buf);
    g.bufferData(g.ARRAY_BUFFER, data, g.STATIC_DRAW);
    const p = g.getAttribLocation(pr, 'p'),
      co = g.getAttribLocation(pr, 'color');
    g.enableVertexAttribArray(p);
    g.vertexAttribPointer(p, 3, g.FLOAT, false, 24, 0);
    g.enableVertexAttribArray(co);
    g.vertexAttribPointer(co, 3, g.FLOAT, false, 24, 12);
    const al = g.getUniformLocation(pr, 'a'),
      asp = g.getUniformLocation(pr, 'aspect');
    g.enable(g.DEPTH_TEST);
    g.clearColor(.77, .84, .78, 1);
    let raf = 0,
      last = 0;
    const resize = () => {
      const r = c.getBoundingClientRect(),
        dpr = Math.min(devicePixelRatio || 1, 1.5),
        w = Math.max(1, Math.floor(r.width * dpr)),
        h = Math.max(1, Math.floor(r.height * dpr));
      if (c.width !== w || c.height !== h) {
        c.width = w;
        c.height = h;
        g.viewport(0, 0, w, h);
      }
    };
    const draw = (t: number) => {
      resize();
      if (last && !drag.current) angle.current += (t - last) / 1000 * .045;
      last = t;
      g.clear(g.COLOR_BUFFER_BIT | g.DEPTH_BUFFER_BIT);
      g.uniform1f(al, angle.current);
      g.uniform1f(asp, c.width / Math.max(1, c.height));
      g.drawArrays(g.TRIANGLES, 0, data.length / 6);
      raf = requestAnimationFrame(draw);
    };
    const ro = new ResizeObserver(resize);
    ro.observe(c);
    raf = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      g.deleteBuffer(buf);
      g.deleteProgram(pr);
    };
  }, [city]);
  const start = (e: React.TouchEvent<HTMLCanvasElement>) => {
    e.stopPropagation();
    drag.current = {
      x: e.touches[0].clientX,
      a: angle.current
    };
  };
  const move = (e: React.TouchEvent<HTMLCanvasElement>) => {
    e.stopPropagation();
    if (drag.current) angle.current = drag.current.a + (e.touches[0].clientX - drag.current.x) * .008;
  };
  const end = (e: React.TouchEvent<HTMLCanvasElement>) => {
    e.stopPropagation();
    drag.current = null;
  };
  return <canvas ref={ref} className="city3d-canvas" aria-label={`Интерактивный 3D-город ${city}. Проведи пальцем для поворота камеры.`} onTouchStart={start} onTouchMove={move} onTouchEnd={end} onTouchCancel={end} />;
}