import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dequantize,unweld,normals} from '@gltf-transform/functions';
import {MeshoptDecoder} from 'meshoptimizer';
await MeshoptDecoder.ready;
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({'meshopt.decoder':MeshoptDecoder});
const [src,dst]=process.argv.slice(2);
const doc=await io.read(src);
const keep=new Set(['idle','walk','sprint','die','holding-both']);
for(const a of doc.getRoot().listAnimations()) if(!keep.has(a.getName())) a.dispose();
await doc.transform(dequantize(),unweld());
for(const m of doc.getRoot().listMaterials()){
  const info=m.getBaseColorTextureInfo(); const tr=info&&info.getExtension('KHR_texture_transform');
  const ofs=tr?tr.getOffset():[0,0], sc=tr?tr.getScale():[1,1]; console.log('uv transform',ofs,sc,tr?tr.getRotation():0);
  for(const mesh of doc.getRoot().listMeshes()) for(const p of mesh.listPrimitives()){ if(p.getMaterial()!==m) continue;
    const uv=p.getAttribute('TEXCOORD_0'); const seen=new Set();
    if(uv&&!seen.has(uv)){ seen.add(uv); const e=[0,0]; for(let i=0;i<uv.getCount();i++){uv.getElement(i,e); uv.setElement(i,[e[0]*sc[0]+ofs[0],e[1]*sc[1]+ofs[1]]);} }
  }
  m.setBaseColorTexture(null);
}
for(const t of doc.getRoot().listTextures()) t.dispose();
await doc.transform(normals({overwrite:true}));
for(const e of doc.getRoot().listExtensionsUsed()) if(['EXT_meshopt_compression','KHR_materials_unlit','KHR_texture_transform','KHR_mesh_quantization'].includes(e.extensionName)) e.dispose();
await io.write(dst,doc);
let n=[]; doc.getRoot().listMeshes().forEach(m=>m.listPrimitives().forEach(p=>{const u=p.getAttribute('TEXCOORD_0'),e=[0,0];let a=[9,9,-9,-9];for(let i=0;i<u.getCount();i++){u.getElement(i,e);a=[Math.min(a[0],e[0]),Math.min(a[1],e[1]),Math.max(a[2],e[0]),Math.max(a[3],e[1])]} n.push(m.getName()+':'+p.getAttribute('POSITION').getCount()+' uv '+a.map(x=>x.toFixed(3)))}));
console.log(doc.getRoot().listAnimations().map(a=>a.getName()),'\n',n.join('\n '),'\n',doc.getRoot().listNodes().map(x=>x.getName()+(x.getMesh()?'*':'')).join(','));
