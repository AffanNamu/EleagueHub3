(self.webpackChunk_N_E=self.webpackChunk_N_E||[]).push([[377],{5718:function(e,t,r){Promise.resolve().then(r.bind(r,2632)),Promise.resolve().then(r.t.bind(r,231,23))},2632:function(e,t,r){"use strict";r.d(t,{SearchBar:function(){return o}});var n=r(7437),a=r(2265),u=r(6463),s=r(4817);function o(e){var t;let{placeholder:r}=e,o=(0,u.useRouter)(),i=(0,u.usePathname)(),c=(0,u.useSearchParams)(),[l,m]=(0,a.useState)(null!==(t=c.get("q"))&&void 0!==t?t:""),[,d]=(0,a.useTransition)();return(0,n.jsxs)("form",{onSubmit:function(e){e.preventDefault();let t=new URLSearchParams(c.toString());l.trim()?t.set("q",l.trim()):t.delete("q"),d(()=>{o.push("".concat(i,"?").concat(t.toString()))})},className:"flex max-w-sm items-center gap-2 rounded-sm border border-base-border bg-base-raised px-3 py-1.5",children:[(0,n.jsx)(s.Z,{size:15,className:"text-ink-muted"}),(0,n.jsx)("input",{type:"text",value:l,onChange:e=>m(e.target.value),placeholder:r,className:"w-full bg-transparent text-sm text-ink-primary placeholder:text-ink-muted focus:outline-none"})]})}},8030:function(e,t,r){"use strict";r.d(t,{Z:function(){return i}});var n=r(2265);/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let a=e=>e.replace(/([a-z0-9])([A-Z])/g,"$1-$2").toLowerCase(),u=function(){for(var e=arguments.length,t=Array(e),r=0;r<e;r++)t[r]=arguments[r];return t.filter((e,t,r)=>!!e&&r.indexOf(e)===t).join(" ")};/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */var s={xmlns:"http://www.w3.org/2000/svg",width:24,height:24,viewBox:"0 0 24 24",fill:"none",stroke:"currentColor",strokeWidth:2,strokeLinecap:"round",strokeLinejoin:"round"};/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let o=(0,n.forwardRef)((e,t)=>{let{color:r="currentColor",size:a=24,strokeWidth:o=2,absoluteStrokeWidth:i,className:c="",children:l,iconNode:m,...d}=e;return(0,n.createElement)("svg",{ref:t,...s,width:a,height:a,stroke:r,strokeWidth:i?24*Number(o)/Number(a):o,className:u("lucide",c),...d},[...m.map(e=>{let[t,r]=e;return(0,n.createElement)(t,r)}),...Array.isArray(l)?l:[l]])}),i=(e,t)=>{let r=(0,n.forwardRef)((r,s)=>{let{className:i,...c}=r;return(0,n.createElement)(o,{ref:s,iconNode:t,className:u("lucide-".concat(a(e)),i),...c})});return r.displayName="".concat(e),r}},4817:function(e,t,r){"use strict";r.d(t,{Z:function(){return n}});/**
 * @license lucide-react v0.417.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */let n=(0,r(8030).Z)("Search",[["circle",{cx:"11",cy:"11",r:"8",key:"4ej97u"}],["path",{d:"m21 21-4.3-4.3",key:"1qie3q"}]])},6463:function(e,t,r){"use strict";var n=r(1169);r.o(n,"usePathname")&&r.d(t,{usePathname:function(){return n.usePathname}}),r.o(n,"useRouter")&&r.d(t,{useRouter:function(){return n.useRouter}}),r.o(n,"useSearchParams")&&r.d(t,{useSearchParams:function(){return n.useSearchParams}})}},function(e){e.O(0,[231,971,23,744],function(){return e(e.s=5718)}),_N_E=e.O()}]);