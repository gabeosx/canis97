// Offline geometry/resource regression checks; never launches the app or a browser.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root));
const json = path => JSON.parse(read(path));
const bundled = 'SiriusMac/Skins/Bundled/';
const manifest = json(`${bundled}QuartzDeck.json`);
const scene = json(`${bundled}QuartzDeck.scene.json`);
const motion = json(`${bundled}QuartzDeck.motion.json`);
assert.equal(manifest.size, 'cinema448x360');
assert.deepEqual(scene.canvas, {width:448, height:360});
assert.deepEqual(motion.canvas, scene.canvas);
const afterglow = motion.layers[0];
const points = afterglow.paths.flatMap(path => path.points).map(p => ({
  x:p.x * afterglow.transform.scale.x + afterglow.transform.position.x,
  y:p.y * afterglow.transform.scale.y + afterglow.transform.position.y,
}));
assert.deepEqual([Math.min(...points.map(p=>p.x)),Math.max(...points.map(p=>p.x)),Math.min(...points.map(p=>p.y)),Math.max(...points.map(p=>p.y))], [92,212,288,348]);
const expected = {
  artwork:[24,296,48,48], channelIdentity:[92,288,120,28], metadata:[92,316,156,40],
  favorite:[216,284,32,32], status:[272,288,88,28], transport:[264,316,128,40],
  library:[396,288,32,32], overflowMenu:[396,324,32,32],
};
assert.equal(manifest.slots.length, Object.keys(expected).length);
assert.deepEqual(manifest.dragRegions, [{x:8,y:4,width:432,height:276}]);
const drag = manifest.dragRegions[0];
for (const [x,y] of [[20,20],[181.5,132.5],[350,180],[430,270]]) {
  assert(x >= drag.x && x < drag.x+drag.width && y >= drag.y && y < drag.y+drag.height);
}
for (const {semantic, frame:f} of manifest.slots) {
  assert.deepEqual([f.x,f.y,f.width,f.height], expected[semantic]);
  assert(Object.values(f).every(n => Number.isInteger(n) && n%4 === 0));
  assert(f.x >= 4 && f.y >= 4 && f.x+f.width <= 444 && f.y+f.height <= 356);
  assert(!(drag.x < f.x+f.width && drag.x+drag.width > f.x && drag.y < f.y+f.height && drag.y+drag.height > f.y), 'drag surface must not capture receiver controls');
}
const record = scene.layers.find(layer => layer.identifier === 'record_label');
assert.deepEqual(record.frame, {x:133,y:84,width:97,height:97});
assert.equal(record.frame.x+record.frame.width/2, 181.5);
assert.equal(record.frame.y+record.frame.height/2, 132.5);
assert(record.timeline.every(k => k.x === 0 && k.y === 0 && k.scaleX === 1 && k.scaleY === 1));
assert.equal(record.timeline.at(-1).time, 1.8);
for (const layer of scene.layers.filter(l => l.identifier !== 'record_label')) {
  const f = layer.frame;
  assert.equal(f.x+f.width/2, 232);
  assert.equal(f.y+f.height/2, layer.identifier.startsWith('song') ? 337 : 304);
  assert((layer.timeline ?? []).every(k => k.scaleX === k.scaleY));
}
for (const [name,width,height] of [['QuartzDeckFaceplate@2x.png',1344,1080], ['QuartzDeckSceneLabel@2x.png',291,291]]) {
  const png = read(`${bundled}Assets/QuartzDeck/${name}`);
  assert.equal(png.subarray(1,4).toString(), 'PNG');
  assert.equal(png.readUInt32BE(16), width);
  assert.equal(png.readUInt32BE(20), height);
  assert.equal(png[25], 6, 'RGBA PNG required');
}
const view = read('SiriusMac/Player/CompactPlayerView.swift').toString();
assert(view.includes('.frame(width: plan.presentationSize.width, height: plan.presentationSize.height, alignment: .topLeading)\n        .overlay(alignment: .topLeading)'));
assert(view.includes('Color.white.opacity(0.001)\n                    .frame(width: semanticMetric(CGFloat(drag.width)), height: semanticMetric(CGFloat(drag.height)))\n                    .contentShape(.rect)\n                    .gesture(WindowDragGesture())'));
assert(view.includes('.allowsWindowActivationEvents(true)\n                    .allowsHitTesting(true)'));
assert(view.includes('.scaleEffect(presentationScale, anchor: .topLeading)'));
assert(view.includes('width: semanticMetric(CGFloat(frame.width))'));
assert(!view.includes('.scaleEffect(renderingAppearance.layoutPlan.presentationScale, anchor: .topLeading)'));
assert(view.includes('minimumInterval: 1.0 / 120.0'));
assert(view.includes('(rawOffset * pixelScale).rounded() / pixelScale'));
assert(view.includes('width: renderingAppearance.layoutPlan.presentationSize.width'));
assert(view.includes('if !usesQuartzReceiverGeometry {\n                    surfaceBackground(.canvas)'));
assert(view.includes('if usesQuartzReceiverGeometry {\n                // Quartz supplies its own RGBA silhouette'));
assert(read('SiriusMac/Windows/CompactWindowController.swift').toString().includes('let size = appearance.layoutPlan.presentationSize'));
assert(read('SiriusMac/Skins/SkinAppearance.swift').toString().includes('self == .cinema448x360 ? 1.5 : 1'));
console.log('PASS: Quartz large canvas, final-pixel semantic slots, pixel-aligned marquee, fixed circular pivot, favorite alignment, and Retina RGBA resources');
