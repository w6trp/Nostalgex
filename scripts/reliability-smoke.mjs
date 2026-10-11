#!/usr/bin/env node
// Offline regressions: synthetic media, stubbed browser/fetch, no server or credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import './nostalgex-playback-core.js';
import './nostalgex-daily-manifest.js';
import { accessPolicy, allowedRequest } from './devtools/lib/access.mjs';
import { buildScheduleRange } from './devtools/lib/schedule.mjs';
import subscribe from '../api/subscribe.js';
const C = globalThis.NostalgexPlaybackCore, M = globalThis.NostalgexDailyManifest;
const source = fs.readFileSync(new URL('../plex-tuner.html', import.meta.url), 'utf8');
function extract(start, end) { const a = source.indexOf(start); assert(a >= 0); const b = source.indexOf(end, a); assert(b > a); return source.slice(a,b); }
let checks = 0;
function check(name, fn) { fn(); checks++; console.log('PASS', name); }
let clock = 0, pulse, reports = [], scrobbles = 0, hidden = false;
const video = { currentTime: 0, paused: false, ended: false, readyState: 4, playbackRate: 1 };
const tracker = C.tracker({video,item:{duration:1,offsetSeconds:0},hidden:()=>hidden,
  send:(...args)=>reports.push(args),scrobble:()=>scrobbles++,now:()=>clock,every:fn=>{pulse=fn;return 1;},cancel:()=>{}});
tracker.onReady(); clock=10000;video.currentTime=10;pulse();
video.paused=true;tracker.onPause();clock=20000;pulse();
check('pause reports paused at actual position',()=>assert.deepEqual(reports.at(-1).slice(0,2),['paused',10000]));
video.currentTime=40;tracker.onSeek();
check('seek reports actual media position',()=>assert.equal(reports.at(-1)[1],40000));
video.paused=false;tracker.onResume();tracker.onWaiting();clock=100000;pulse();
check('buffering is reported and cannot mark watched',()=>{assert.equal(reports.at(-1)[0],'buffering');assert.equal(scrobbles,0);});
tracker.onResume();hidden=true;tracker.onVisibility();clock=160000;video.currentTime=60;pulse();
check('hidden playback cannot pass watched gate',()=>assert.equal(scrobbles,0));
tracker.stop(true);
check('exit sends stopped with keepalive and actual position',()=>assert.deepEqual(reports.at(-1),['stopped',60000,60000,true]));
clock=170000;pulse();
check('stopped tracker sends no later reports',()=>assert.equal(reports.at(-1)[0],'stopped'));
{
 let now=0,run,marked=0;const v={currentTime:0,paused:false,ended:false,readyState:4,playbackRate:1};
 const t=C.tracker({video:v,item:{duration:1},hidden:()=>false,now:()=>now,every:fn=>{run=fn;return 1;},cancel:()=>{},send:()=>{},scrobble:()=>{marked++;return Promise.resolve(marked>1);}});
 t.onReady();for(let i=0;i<6;i++){now+=10000;v.currentTime+=10;run();await new Promise(resolve=>setImmediate(resolve));}
 t.stop();await new Promise(resolve=>setImmediate(resolve));
 check('failed scrobble retries and stops retrying only after acknowledgement',()=>assert.equal(marked,2));
}
check('legacy sync opt-in is not inherited',()=>{
 const declaration=source.match(/let syncPlexActivity = [^;]+;/)[0];
 const ctx=vm.createContext({localStorage:{getItem:k=>k==='plex90_sync_activity'?'true':null}});
 vm.runInContext(declaration+';result=syncPlexActivity;',ctx);assert.equal(ctx.result,false);
});
check('unknown codecs and incompatible audio cannot direct-play',()=>{
 const v={canPlayType:()=> 'probably'};
 assert.equal(C.canDirectPlay({partKey:'x',container:'mp4'},v),false);
 assert.equal(C.canDirectPlay({partKey:'x',container:'mp4',videoCodec:'h264',audioCodec:'truehd'},v),false);
 assert.equal(C.canDirectPlay({partKey:'x',container:'mp4',videoCodec:'h264',audioCodec:'aac'},v),true);
 assert.equal(C.canDirectPlay({partKey:'x',container:'mp4',videoCodec:'h264',audioCodec:'aac'},{canPlayType:()=>''}),false);
});
const pool=[{ratingKey:'1',title:'A',serverId:'A',duration:60,type:'movie'},{ratingKey:'1',title:'B',serverId:'B',duration:60,type:'movie'}];
check('server-local IDs remain distinct in schedules',()=>{
 const blocks=M.getManifestBlocks({id:1},pool,Date.UTC(2026,9,11,12),'fixture');
 assert.deepEqual(new Set(blocks.map(b=>b.item.serverId)),new Set(['A','B']));
});
check('filler blocks preserve offsets and devtools uses shared engine',()=>{
 const start=new Date(2026,9,11).getTime()/1000,day=M.localDayNumber(start*1000);
 const blocks=M.packDay(pool,start,day,1,new Set(pool.map(M.itemKey)),false,null);
 assert(blocks.some(b=>b.sourceOffsetSeconds>0));
 const expected=M.packDay(pool,start,day,1,new Set(),false,null);
 const actual=buildScheduleRange({id:1},pool,start,start+86400);
 assert.deepEqual(actual.map(b=>[b.ratingKey,b.startSec,b.endSec]),expected.map(b=>[b.ratingKey,b.startSec,b.endSec]));
});
const store={};
const cache=vm.createContext({Date,crypto:webcrypto,TextEncoder,Uint8Array,
  selectedServers:[{url:'https://synthetic.invalid',machineIdentifier:'server',token:'fake-one'}],
  plexServerUrl:'https://synthetic.invalid',plexToken:'fake-one',mediaBackend:'plex',jellyfinUserId:'',
  libraryGeneration:0,LIBRARY_CACHE_KEY:'cache',LIBRARY_CACHE_TTL:86400000,
  localStorage:{setItem:(k,v)=>store[k]=v,getItem:k=>store[k],removeItem:k=>delete store[k]}});
vm.runInContext(extract('  async function libraryCacheScope()', '  async function repopulateChannelsFromLibrary'),cache);
await vm.runInContext("saveLibraryCache([{serverId:'server',serverUrl:plexServerUrl,serverToken:plexToken,ratingKey:'1'}])",cache);
const loaded=await vm.runInContext('loadLibraryCache()',cache);
check('cache stores no usable server token and reinjects scoped credentials',()=>{assert(!store.cache.includes('fake-one'));assert.equal(loaded.items[0].serverToken,'fake-one');});
cache.selectedServers[0].token='fake-two';cache.plexToken='fake-two';
const stale=await vm.runInContext('loadLibraryCache()',cache);
check('token/account changes invalidate old library cache',()=>assert.equal(stale,null));
check('devtools defaults to loopback and rejects unconfigured LAN',()=>{
 assert.equal(accessPolicy({}).host,'127.0.0.1');assert.throws(()=>accessPolicy({DEVTOOLS_HOST:'0.0.0.0'}));
 const policy=accessPolicy({DEVTOOLS_HOST:'0.0.0.0',DEVTOOLS_TOKEN:'a'.repeat(32)});
 assert.equal(allowedRequest({headers:{host:'fixture:3030'}},policy),false);
 assert.equal(allowedRequest({headers:{host:'fixture:3030',authorization:'Bearer '+'a'.repeat(32)}},policy),true);
 assert.equal(allowedRequest({headers:{host:'fixture:3030',origin:'https://untrusted.invalid',authorization:'Bearer '+'a'.repeat(32)}},policy),false);
 assert.equal(allowedRequest({headers:{host:'rebind.invalid:3030'}},accessPolicy({})),false);
});
// Exercise real browser scheduling/error callbacks with only rendering/clock stubbed.
let nextCallback, played;
const channel={id:1,itemPool:[{ratingKey:'bad',duration:60,title:'Bad'},{ratingKey:'good',duration:60,title:'Good'}]};
const skip=vm.createContext({Date:{now:()=>100000},plexServerUrl:'fixture',channel,
 failedPlaybackItems:new Set(),mediaIdentity:C.identity,getTimeFilteredPool:c=>c.itemPool,
 NostalgexDailyManifest:{getManifestBlocks:(c,p)=>p.map((item,i)=>({item,startSec:i*3600,endSec:(i+1)*3600}))},
 formatTime:String,currentChannel:1,consecutivePlaybackFailures:0,MAX_CONSECUTIVE_FAILURES:3,
 playbackGeneration:0,stopVideo:()=>{skip.playbackGeneration++;},console:{warn:()=>{}},
 showPlaybackFailure:()=>{},clearVideoError:()=>{},showVideoError:()=>{},setTimeout:fn=>nextCallback=fn,
 playCurrentItem:i=>{played=i.ratingKey;},document:{getElementById:()=>({})},showNowPlaying:()=>{},renderActiveGuide:()=>{}});
vm.runInContext(extract('  function manifestServerKey()', '  function rebuildAllSchedules()'),skip);
vm.runInContext(extract('  function failCurrentItem(', '  function stopVideo('),skip);
vm.runInContext('failCurrentItem(channel,channel.itemPool[0],{})',skip);nextCallback();
check('failed slot is excluded before rebuilding schedule',()=>assert.equal(played,'good'));
// Two delayed PlaybackInfo results: the first must never overwrite the newer channel.
const pending=[];const elements=new Map();
const el=()=>({classList:{add(){},remove(){}},style:{},canPlayType:()=> 'probably',addEventListener(){},play:()=>Promise.resolve()});
const browser=vm.createContext({NostalgexPlaybackCore:C,plexServerUrl:'https://synthetic.invalid',plexToken:'fake',mediaBackend:'jellyfin',
 playbackGeneration:0,playbackTracker:null,currentPlayingItem:null,hlsInstance:null,syncPlexActivity:false,videoMuted:false,
 stopVideo:()=>{browser.playbackGeneration++;},stopActiveTranscode(){},clearVideoError(){},clearSubtitleTracks(){},
 showVideoError(){},showPlaybackFailure(){},loadSubtitleForCurrentItem(){},getJellyfinTranscodeUrl:item=>new Promise(resolve=>pending.push(resolve)),
 document:{getElementById:id=>{if(!elements.has(id))elements.set(id,el());return elements.get(id);}},
 console,Date,setTimeout:()=>1,clearTimeout,getClientId:()=> 'client',jellyfinAuthHeader:()=> 'synthetic',pickAudioStream:()=>null});
vm.runInContext(extract('  async function playCurrentItem(', '  // A program that cannot play'),browser);
browser.first={ratingKey:'1',duration:60};browser.second={ratingKey:'2',duration:60};
const first=vm.runInContext('playCurrentItem(first,{id:1})',browser);const second=vm.runInContext('playCurrentItem(second,{id:2})',browser);
pending[1]('https://synthetic.invalid/second.m3u8');await second;pending[0]('https://synthetic.invalid/first.m3u8');await first;
check('late PlaybackInfo cannot overwrite newer channel',()=>assert.equal(browser.currentPlayingItem.ratingKey,'2'));
browser.mediaBackend='plex';browser.crypto={randomUUID:()=> 'synthetic-session'};
browser.third={ratingKey:'3',duration:60,partKey:'/library/parts/3/file',container:'mkv',mediaIndex:2,partIndex:1};
await vm.runInContext('playCurrentItem(third,{id:3})',browser);
check('Plex fallback preserves selected media and part and limits output codecs',()=>{
 const url=new URL(elements.get('plex-video').src);
 assert.equal(url.searchParams.get('mediaIndex'),'2');assert.equal(url.searchParams.get('partIndex'),'1');
 assert.equal(url.searchParams.get('videoCodec'),'h264');assert.equal(url.searchParams.get('audioCodec'),'aac');
});
// Subtitle body arrives after clear/channel switch; no obsolete track may attach.
let resolveBody, appended=0;
const subctx=vm.createContext({subtitleGeneration:1,currentPlayingItem:{subtitles:[{}]},subtitlesEnabled:true,mediaBackend:'jellyfin',
 shouldAutoEnableSubs:()=>false,pickSubtitle:()=>({}),buildSubtitleUrl:()=> 'https://synthetic.invalid/sub',
 document:{fullscreenElement:{},getElementById:()=>({appendChild:()=>appended++})},
 fetch:async()=>({ok:true,text:()=>new Promise(resolve=>resolveBody=resolve)}),console});
vm.runInContext(extract('  async function loadSubtitleForCurrentItem(', '  function setAudioLanguage('),subctx);
const sub=vm.runInContext('loadSubtitleForCurrentItem(currentPlayingItem)',subctx);await new Promise(resolve => setImmediate(resolve));subctx.subtitleGeneration++;resolveBody('WEBVTT');await sub;
check('late subtitle cannot attach after channel change',()=>assert.equal(appended,0));
process.env.RESEND_API_KEY='synthetic';process.env.RESEND_AUDIENCE_ID='synthetic';
const oldFetch=globalThis.fetch;let calls=0,status;
globalThis.fetch=async()=>{calls++;return {ok:false,status:calls===1?409:500,json:async()=>({})};};
await subscribe({method:'POST',body:{email:'fixture@example.invalid'}},{status(n){status=n;return this;},json(){}});
globalThis.fetch=oldFetch;
check('duplicate signup does not hide segment assignment failure',()=>assert.equal(status,500));

check('DST days end at calendar midnight, with no overlapping primary block',()=>{
 const previousTZ=process.env.TZ;process.env.TZ='America/New_York';
 for (const [month,date,hours] of [[2,8,23],[10,1,25]]) {
  const start=new Date(2026,month,date).getTime()/1000;
  const next=new Date(2026,month,date+1).getTime()/1000;
  assert.equal(next-start,hours*3600);
  const blocks=M.packDay([{ratingKey:'long',type:'movie',title:'Long',duration:1800}],start,M.localDayNumber(start*1000),1,new Set(),false,null);
  assert.equal(blocks.at(-1).endSec,next);
 }
 if(previousTZ===undefined)delete process.env.TZ;else process.env.TZ=previousTZ;
});

{
 let resolveFirst;const requests=[];
 const q=C.transport((url,options)=>{requests.push({url,options});return requests.length===1?new Promise(resolve=>resolveFirst=resolve):Promise.resolve({ok:true});});
 const first=q.request('https://synthetic.invalid/playing');const second=q.request('https://synthetic.invalid/stopped');
 await new Promise(resolve=>setImmediate(resolve));
 check('transport serializes playing before stopped',()=>assert.equal(requests.length,1));
 resolveFirst({ok:true});await first;await second;
 check('transport delivers stop after first request acknowledgement',()=>assert.equal(requests[1].url,'https://synthetic.invalid/stopped'));
}
{
 const requests=[];const q=C.transport(async(url,options)=>{requests.push(url);return {ok:true};});
 const pending=q.request('https://synthetic.invalid/not-sent');q.cancel();
 assert.equal(await pending,false);
 check('privacy opt-out cancels reports that have not started',()=>assert.equal(requests.length,0));
}
{
 const requests=[];
 const ctx=vm.createContext({NostalgexPlaybackCore:{...C,tracker:options=>options},
  document:{getElementById:()=>({}),hidden:false},plexServerUrl:'https://synthetic.invalid',plexToken:'fake',
  mediaBackend:'plex',activeTranscodeSession:{id:'session'},getClientId:()=> 'client',URLSearchParams,
  fetch:async(url,options)=>{requests.push({url,options});return {ok:true};},console});
 vm.runInContext(extract('  function makePlaybackTracker(', '  async function playCurrentItem('),ctx);
 const reporter=vm.runInContext("makePlaybackTracker({ratingKey:'42'})",ctx);
 await reporter.send('playing',123456,987654,false);await reporter.scrobble();
 check('actual Plex reporter uses POST timeline and PUT scrobble with session header',()=>{
  assert.equal(requests[0].options.method,'POST');assert.equal(requests[1].options.method,'PUT');
  assert.equal(new URL(requests[1].url).searchParams.get('key'),'42');
  assert.equal(requests[1].options.headers['X-Plex-Session-Identifier'],'session');
 });
}
check('precise source duration wins; HLS remaining duration never replaces it',()=>{
 const reports=[];const v={currentTime:5,duration:12,paused:false,ended:false,readyState:4};
 const t=C.tracker({video:v,item:{duration:2,sourceDurationSeconds:119.321},hidden:()=>false,
  send:(...a)=>reports.push(a),scrobble:()=>true,every:()=>1,cancel:()=>{}});t.onReady();t.stop();
 assert.equal(reports[0][2],119321);
 const direct=C.tracker({video:v,item:{duration:2,_isDirectPlay:true},hidden:()=>false,
  send:(...a)=>reports.push(a),scrobble:()=>true,every:()=>1,cancel:()=>{}});direct.onReady();direct.stop();
 assert.equal(reports.at(-1)[2],12000);
});

{
 let now=0,pulse,attempts=0;const v={currentTime:0,paused:false,ended:false,readyState:4};
 const t=C.tracker({video:v,item:{duration:1},hidden:()=>false,now:()=>now,every:fn=>{pulse=fn;return 1;},cancel:()=>{},send:()=>{},scrobble:()=>{attempts++;return true;}});
 t.onReady();now=50000;v.currentTime=50;pulse();t.abandon();await new Promise(resolve=>setImmediate(resolve));
 check('privacy opt-out also cancels a just-scheduled scrobble',()=>assert.equal(attempts,0));
}
console.log(`${checks} reliability regressions passed`);
