import {cpSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=join(root,'tres_pisos_app/assets/pos');
mkdirSync(out,{recursive:true});
for(const dir of ['js','css','assets'])cpSync(join(root,'restaurante-app',dir),join(out,dir),{recursive:true});
let html=readFileSync(join(root,'restaurante-app/index.html'),'utf8');
html=html.replace('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css','/vendor/fontawesome/css/all.min.css').replace('https://cdn.jsdelivr.net/npm/chart.js','/vendor/chart.umd.js').replace('<script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>','<script src="/js/local-transport.js"></script>').replace('</body>','<script src="/js/local-pos.js"></script></body>');
writeFileSync(join(out,'index.html'),html);
let css=readFileSync(join(out,'css/estilos.css'),'utf8').replace(/@import url\('https:\/\/fonts\.googleapis\.com[^\n]+\n/,'');
mkdirSync(join(out,'fonts'),{recursive:true});
for(const [font,weights] of [['outfit',[300,400,500,600,700]],['cinzel',[600,700,900]]]){
 for(const w of weights){const file=`${font}-latin-${w}-normal.woff2`;cpSync(join(root,'node_modules/@fontsource',font,'files',file),join(out,'fonts',file));css=`@font-face{font-family:'${font==='outfit'?'Outfit':'Cinzel'}';font-style:normal;font-weight:${w};font-display:swap;src:url('/fonts/${file}') format('woff2')}\n`+css;}
 cpSync(join(root,'node_modules/@fontsource',font,'LICENSE'),join(out,'fonts',`${font}-LICENSE`));
}
writeFileSync(join(out,'css/estilos.css'),css);const vendor=join(out,'vendor');mkdirSync(vendor,{recursive:true});
cpSync(join(root,'node_modules/chart.js/dist/chart.umd.js'),join(vendor,'chart.umd.js'));cpSync(join(root,'node_modules/chart.js/LICENSE.md'),join(vendor,'chart-LICENSE.md'));
for(const dir of ['css','webfonts'])cpSync(join(root,'node_modules/@fortawesome/fontawesome-free',dir),join(vendor,'fontawesome',dir),{recursive:true});
cpSync(join(root,'node_modules/@fortawesome/fontawesome-free/LICENSE.txt'),join(vendor,'fontawesome/LICENSE.txt'));
console.log('Web completa empaquetada con fuentes, gráficas, iconos y logo locales.');
