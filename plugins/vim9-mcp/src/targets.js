const compare = (a, b) => a.line - b.line || a.byte - b.byte;
const group = t => `${t.buffer}\0${t.revision}`;
const min = (a, b) => compare(a, b) <= 0 ? a : b;
const max = (a, b) => compare(a, b) >= 0 ? a : b;

export function combineTargets({ operation, left, right = [], buffers = [] }) {
  const revisions = new Map();
  for (const t of [...left, ...right]) {
    if (compare(t.start, t.end) > 0) throw new Error('invalid_range');
    if (revisions.has(t.buffer) && revisions.get(t.buffer) !== t.revision) throw new Error('stale_revision: target sets contain different revisions');
    revisions.set(t.buffer, t.revision);
  }
  if (operation === 'filter') return left.filter(t => buffers.includes(t.buffer));
  if (operation === 'union') {
    const sorted = [...left, ...right].sort((a, b) => group(a).localeCompare(group(b)) || compare(a.start, b.start));
    const result = [];
    for (const t of sorted) {
      const last = result.at(-1);
      if (last && group(last) === group(t) && compare(t.start, last.end) <= 0) last.end = max(last.end, t.end);
      else result.push(structuredClone(t));
    }
    return result;
  }
  if (operation === 'intersection') return combineTargets({ operation: 'union', left: left.flatMap(a => right.filter(b => group(a) === group(b)).map(b => ({ ...a, start: max(a.start, b.start), end: min(a.end, b.end) })).filter(t => compare(t.start, t.end) < 0)) });
  return left.flatMap(a => {
    let pieces = [a];
    for (const b of right.filter(b => group(a) === group(b))) pieces = pieces.flatMap(p => {
      if (compare(b.end, p.start) <= 0 || compare(b.start, p.end) >= 0) return [p];
      return [compare(p.start, b.start) < 0 ? { ...p, end: b.start } : null, compare(b.end, p.end) < 0 ? { ...p, start: b.end } : null].filter(Boolean);
    });
    return pieces;
  });
}
