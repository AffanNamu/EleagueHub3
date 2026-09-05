(self.webpackChunk_N_E=self.webpackChunk_N_E||[]).push([[691],{7495:function(e,t,r){Promise.resolve().then(r.bind(r,3083)),Promise.resolve().then(r.t.bind(r,231,23))},3083:function(e,t,r){"use strict";r.d(t,{ReportReviewActions:function(){return u}});var n=r(7437),s=r(3231),i=r(1935),a=r(2265),o=r(6463);function u(e){let{reportId:t}=e,{submit:r,submitting:u,error:c}=function(e){let t=(0,o.useRouter)(),[r,n]=(0,a.useState)(!1),[s,i]=(0,a.useState)(null);return{submit:async function(r){n(!0),i(null);try{let a=await fetch("/api/admin/reports/".concat(e),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({decision:r})});if(!a.ok){var s;let e=await a.json().catch(()=>({}));return i(null!==(s=e.error)&&void 0!==s?s:"Something went wrong. Please try again."),n(!1),!1}return t.push("/moderation/reports"),t.refresh(),!0}catch(e){return i("Network error. Please check your connection and try again."),n(!1),!1}},submitting:r,error:s}}(t);return(0,n.jsxs)("div",{className:"space-y-2",children:[c&&(0,n.jsx)("div",{className:"rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger",children:c}),(0,n.jsxs)("button",{onClick:()=>r("reviewed"),disabled:u,className:"flex w-full items-center justify-center gap-2 rounded-sm bg-signal-success py-2 text-sm font-medium text-base disabled:opacity-60",children:[(0,n.jsx)(s.Z,{size:16})," Mark Reviewed"]}),(0,n.jsxs)("button",{onClick:()=>r("dismissed"),disabled:u,className:"flex w-full items-center justify-center gap-2 rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-ink-muted disabled:opacity-60",children:[(0,n.jsx)(i.Z,{size:16})," Dismiss"]})]})}},8030:function(e,t,r){"use strict";r.d(t,{Z:function(){return u}});var n=r(2265);/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let s=e=>e.replace(/([a-z0-9])([A-Z])/g,"$1-$2").toLowerCase(),i=function(){for(var e=arguments.length,t=Array(e),r=0;r<e;r++)t[r]=arguments[r];return t.filter((e,t,r)=>!!e&&r.indexOf(e)===t).join(" ")};/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */var a={xmlns:"http://www.w3.org/2000/svg",width:24,height:24,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor",strokeWidth:2,strokeLinecap:"round",strokeLinejoin:"round"};/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let o=(0,n.forwardRef)((e,t)=>{let{color:r="currentColor",size:s=24,strokeWidth:o=2,absoluteStrokeWidth:u,className:c="",children:l,iconNode:d,...m}=e;return(0,n.createElement)("svg",{ref:t,...a,width:s,height:s,stroke:r,strokeWidth:u?24*Number(o)/Number(s):o,className:i("lucide",c),...m},[...d.map(e=>{let[t,r]=e;return(0,n.createElement)(t,r)}),...Array.isArray(l)?l:[l]])}),u=(e,t)=>{let r=(0,n.forwardRef)((r,a)=>{let{className:u,...c}=r;return(0,n.createElement)(o,{ref:a,iconNode:t,className:i("lucide-".concat(s(e)),u),...c})});return r.displayName="".concat(e),r}},3231:function(e,t,r){"use strict";r.d(t,{Z:function(){return n}});/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let n=(0,r(8030).Z)("CircleCheck",[["circle",{cx:"12",cy:"12",r:"10",key:"1mglay"}],["path",{d:"m9 12 2 2 4-4",key:"dzmm74"}]])},1935:function(e,t,r){"use strict";r.d(t,{Z:function(){return n}});/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let n=(0,r(8030).Z)("CircleX",[["circle",{cx:"12",cy:"12",r:"10",key:"1mglay"}],["path",{d:"m15 9-6 6",key:"1uzhvr"}],["path",{d:"m9 9 6 6",key:"z0biqf"}]])},6463:function(e,t,r){"use strict";var n=r(1169);r.o(n,"usePathname")&&r.d(t,{usePathname:function(){return n.usePathname}}),r.o(n,"useRouter")&&r.d(t,{useRouter:function(){return n.useRouter}}),r.o(n,"useSearchParams")&&r.d(t,{useSearchParams:function(){return n.useSearchParams}})}},function(e){e.O(0,[231,971,23,744],function(){return e(e.s=7495)}),_N_E=e.O()}]);