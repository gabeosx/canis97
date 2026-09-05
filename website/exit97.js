// Decorative preview of the same bounded data used by the native Exit97 skin.
// The schedule is compiled by the native deterministic director, never randomized here.
(() => {
  'use strict';
  const canvas = document.querySelector('[data-exit97]');
  const toggle = document.querySelector('[data-animation-toggle]');
  if (!canvas || !toggle) return;
  const context = canvas.getContext('2d');
  if (!context) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let scene, schedule, images, visible = false, paused = false, loading = false;
  let frame = 0, previous = null, elapsed = 0, lastPaint = -Infinity;
  const canRun = () => visible && !paused && !reduced.matches && !document.hidden;
  const mix = (a, b, t) => a + (b - a) * t;
  function ease(x, kind) {
    if (kind === 'linear') return x;
    const curves = { easeIn: [.42, 0, 1, 1], easeOut: [0, 0, .58, 1], easeInOut: [.42, 0, .58, 1] };
    const [x1, y1, x2, y2] = curves[kind];
    const bezier = (t, a, b) => 3 * (1-t)**2*t*a + 3*(1-t)*t*t*b + t**3;
    let lo = 0, hi = 1;
    for (let i = 0; i < 12; i++) {const mid = (lo+hi)/2; if (bezier(mid,x1,x2) < x) lo=mid; else hi=mid;}
    return bezier((lo+hi)/2,y1,y2);
  }
  function value(keys, time) {
    if (time <= keys[0].time) return keys[0];
    if (time >= keys.at(-1).time) return keys.at(-1);
    const i = keys.findIndex((k) => k.time > time), a = keys[i-1], b = keys[i];
    const t = ease((time-a.time)/(b.time-a.time), a.easing);
    return Object.fromEntries(['x','y','scaleX','scaleY','rotation','opacity'].map(k => [k,mix(a[k],b[k],t)]));
  }
  function paint(time) {
    context.clearRect(0,0,canvas.width,canvas.height);
    const visit = schedule.findLast(v => v.start <= time);
    const performance = visit && time < visit.end ? scene.performances.find(p => p.identifier === visit.identifier) : null;
    const age = visit ? time - visit.start : 0;
    for (const layer of scene.layers) {
      const track = performance?.tracks.find(t => t.layerID === layer.identifier);
      if (layer.role.startsWith('persistent') || (layer.role === 'performance' && !track)) continue;
      const k = track ? value(track.timeline,age) : layer.timeline ? value(layer.timeline,time % layer.timeline.at(-1).time) : {x:0,y:0,scaleX:1,scaleY:1,rotation:0,opacity:1};
      if (k.opacity <= 0) continue;
      const r = layer.frame, image = images.get(layer.asset);
      let sx=0,sy=0,sw=image.width,sh=image.height;
      if (layer.atlas && track?.poseCycle) {
        const a=layer.atlas,p=track.poseCycle,n=Math.floor(age*p.framesPerSecond);
        const cell=p.frames[p.loops ? n%p.frames.length : Math.min(n,p.frames.length-1)];
        sw/=a.columns;sh/=a.rows;sx=cell%a.columns*sw;sy=Math.floor(cell/a.columns)*sh;
      }
      context.save();context.scale(canvas.width/448,canvas.height/228);
      context.globalAlpha=k.opacity;context.translate(r.x+r.width/2+k.x,r.y+r.height/2+k.y);
      context.rotate(k.rotation*Math.PI/180);context.scale(k.scaleX,k.scaleY);
      context.drawImage(image,sx,sy,sw,sh,-r.width/2,-r.height/2,r.width,r.height);context.restore();
    }
  }
  function tick(now) {
    frame=0;
    if (!canRun()) {previous=null;return;}
    if (previous !== null) elapsed += Math.min((now-previous)/1000,.1);
    previous=now;
    if (now-lastPaint >= 1000/24) {paint(elapsed % 28800);lastPaint=now;}
    frame=requestAnimationFrame(tick);
  }
  async function sync() {
    toggle.hidden=reduced.matches;
    if (!canRun()) {
      cancelAnimationFrame(frame);frame=0;previous=null;
      if (reduced.matches) canvas.hidden=true;
      return;
    }
    if (!scene) {
      if (loading) return;
      loading=true;
      try {
        const response=await fetch('/assets/exit97-v2/preview.json');
        if (!response.ok) throw new Error('Preview unavailable');
        const data=await response.json();
        const pairs=await Promise.all(data.assets.map(async name => {
          const img=new Image();img.src='/assets/exit97-v2/'+name;await img.decode();return [name,img];
        }));
        scene=data.scene;scene.layers.sort((a,b)=>a.zIndex-b.zIndex);schedule=data.schedule;images=new Map(pairs);
      } catch {toggle.hidden=true;return;} finally {loading=false;}
    }
    if (!canRun()) return;
    canvas.hidden=false;
    if (!frame) {previous=null;frame=requestAnimationFrame(tick);}
  }
  toggle.addEventListener('click',()=>{paused=!paused;toggle.textContent=paused?'Play animation':'Pause animation';toggle.setAttribute('aria-pressed',String(paused));sync();});
  reduced.addEventListener('change',sync);document.addEventListener('visibilitychange',sync);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;sync();},{threshold:.05}).observe(canvas.parentElement);
})();
