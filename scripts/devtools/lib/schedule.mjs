// Use the same daily packing engine as the browser tuner, not the legacy loop.
// A generated snapshot starts with no prior watched/day cache. Real tvOS exports
// remain authoritative for that device's pool, timezone and manifest history.
import '../../nostalgex-daily-manifest.js';
const M = globalThis.NostalgexDailyManifest;
export function buildScheduleRange(channel, items, fromSec, toSec) {
  const pool = items.filter(item => item.duration > 0);
  if (!pool.length || toSec <= fromSec) return [];
  const lookup = new Map(pool.map(item => [M.itemKey(item), item]));
  const day = new Date(fromSec * 1000); day.setHours(0, 0, 0, 0);
  let previous = new Set(), last = null;
  const entries = [];
  while (day.getTime() / 1000 < toSec) {
    const start = day.getTime() / 1000;
    const blocks = M.packDay(pool, start, M.localDayNumber(day.getTime()), channel.id, previous,
      Boolean(channel.isPremiereChannel), last);
    for (const block of blocks) {
      if (block.endSec > fromSec && block.startSec < toSec) {
        entries.push({ ...block, id: `${block.ratingKey}_${block.startSec}`, item: lookup.get(block.ratingKey) });
      }
    }
    previous = new Set(blocks.map(block => block.ratingKey));
    last = blocks.at(-1)?.ratingKey || null;
    day.setDate(day.getDate() + 1);
  }
  return entries;
}
export function buildScheduleAt(channel, pool, atUnixSec) {
  return buildScheduleRange(channel, pool, atUnixSec, atUnixSec + 21600);
}
