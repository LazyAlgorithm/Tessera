#!/usr/bin/env python3
"""Package historical benchmark data without publishing build/runtime binaries."""
from pathlib import Path
from collections import defaultdict
import argparse,hashlib,json,tarfile,zipfile,os,re,shutil,datetime
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--physics-zip',type=Path,required=True);a=p.parse_args();S=a.source.resolve();O=a.output.resolve();O.mkdir(parents=True,exist_ok=True);A=O/'archives';A.mkdir(exist_ok=True)
SKIP={'build','builds','source','snapshot','unity','assets','__pycache__','.git','confirmation-engine-source','confirmation-native-build','third_party'}
EXT={'.md','.csv','.json','.jsonl','.log','.tprofile','.png','.svg','.txt','.patch','.py','.bf','.toml','.cpp','.h','.cs','.sh'}
files=[]
for kind in ['full-engine','softbody','voxel']:
 base=S/kind
 for f in sorted(base.rglob('*')):
  if f.is_file() and not any(x in SKIP for x in f.relative_to(base).parts) and f.suffix in EXT:files.append(f)
# Preserve measured source snapshots for the major historical runs (not their compiled archives/binaries).
for folder in ['full-engine/final-comparison-20261028-202825/snapshot','softbody/results-20261029-094437/snapshot','voxel/results-20261029-191142/snapshot']:
 base=S/folder
 for f in sorted(base.rglob('*')):
  if f.is_file() and not any(x in {'build','.git','__pycache__'} for x in f.relative_to(base).parts) and f.suffix in EXT:files.append(f)
files=sorted(set(files));records=[];archive_map={};groups=defaultdict(list)
for f in files:groups[f.relative_to(S).parts[0]].append(f)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
archives=[]
for category,items in groups.items():
 batches=[];batch=[];size=0
 for f in items:
  n=f.stat().st_size
  if batch and size+n>16*1048576:batches.append(batch);batch=[];size=0
  batch.append(f);size+=n
 if batch:batches.append(batch)
 for index,batch in enumerate(batches,1):
  dest=A/f'{category}-{index:02d}.tar.gz'
  with tarfile.open(dest,'w:gz',compresslevel=6) as tar:
   for f in batch:
    rel=str(f.relative_to(S));info=tar.gettarinfo(str(f),arcname=rel);info.uid=info.gid=0;info.uname=info.gname=''
    with f.open('rb') as stream:tar.addfile(info,stream)
    archive_map[f]=dest;records.append({'path':rel,'bytes':f.stat().st_size,'sha256':sha(f),'archive':str(dest.relative_to(O))})
  archives.append({'path':str(dest.relative_to(O)),'bytes':dest.stat().st_size,'sha256':sha(dest),'files':len(batch)})
  print('ARCHIVE',dest.name,dest.stat().st_size,flush=True)
# Directly browsable reports, plots, summaries and essential provenance. Raw originals remain in archives.
direct={}
important={'REPORT.md','report.md','COMPARISON.md','CONFIRMATION.md','TEST_STATUS.md','WORK_LOG.md','LATEST_COMPARISON.md','README.md','METHODOLOGY.md','workload-audit.md','snapshot-notes.txt','EXCLUDED.md'}
metadata={'summary.csv','comparison.csv','supplemental.csv','processes.csv','manifest.json','unity-baselines.json','definition-checks.json','validation.json','diagnostics.json','environment.json','builds.json','snapshot-sha256.json','source-sha256.json','quality-summary.csv','failures.json'}
for f in files:
 rel=f.relative_to(S)
 if 'snapshot' in rel.parts:continue
 if f.name in important or f.name in metadata or f.suffix in {'.png','.svg'}:
  d=O/rel;d.parent.mkdir(parents=True,exist_ok=True);direct[f]=d
# Physics comparison is standalone; preserve the original user-facing bundle exactly.
physics=O/'physics-comparison';physics.mkdir(exist_ok=True);bundle=physics/'physics-engine-results.zip';shutil.copy(a.physics_zip,bundle)
with zipfile.ZipFile(a.physics_zip) as z:
 for name in ['REPORT.md','METHODOLOGY.md','README.md','comparison.png','stack-quality.png','quality-table.md','results/summary.csv','results/summary.json','results/metadata.json','results/quality-summary.csv']:
  if name in z.namelist():
   d=physics/name;d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(z.read(name))
archives.append({'path':str(bundle.relative_to(O)),'bytes':bundle.stat().st_size,'sha256':sha(bundle),'files':len(zipfile.ZipFile(bundle).namelist()),'format':'zip; original standalone comparison bundle'})
# Resolve local links against the original location; raw-only links now download their containing archive.
def rewrite(f,text):
 def link(m):
  label,target=m.groups();target=target.strip('<>')
  if target.startswith(('https://','http://','mailto:','#','data:')):return m.group(0)
  path,_,anchor=target.partition('#');original=(f.parent/path).resolve() if not path.startswith('/') else Path(path)
  if original in direct:dest=direct[original];suffix=('#'+anchor) if anchor else ''
  elif original in archive_map:dest=archive_map[original];suffix=''
  elif original.exists() and S in original.parents:dest=O/'README.md';suffix='#artifact-policy'
  elif path.startswith('/') or ':' in path:dest=O/'README.md';suffix='#artifact-policy'
  else:
   candidate=direct[f].parent/path
   if candidate.exists():return m.group(0)
   dest=O/'README.md';suffix='#artifact-policy'
  result=os.path.relpath(dest,direct[f].parent)+suffix
  return label+'('+result+')'
 text=re.sub(r'(!?\[[^\]]*\])\(([^)]+)\)',link,text)
 text=text.replace(str(S),'historical benchmark root').replace(str(S.parent),'<local-tessera>')
 return ('> **Excluded or superseded run:** see [EXCLUDED.md](EXCLUDED.md).\n\n' if f.name=='report.md' and (f.parent/'EXCLUDED.md').exists() else '')+'> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.\n\n'+text
for f,d in direct.items():
 if f.suffix=='.md':d.write_text(rewrite(f,f.read_text(errors='replace')))
 else:shutil.copy(f,d)
# Restore enough raw-only references in the standalone comparison to make browser navigation unambiguous.
for f in physics.rglob('*.md'):
 text=f.read_text();text=re.sub(r'(!?\[[^\]]*\])\(([^)]+)\)',lambda m:m.group(0) if m.group(2).startswith(('http:','https:','#')) or (f.parent/m.group(2)).exists() else m.group(1)+'('+os.path.relpath(bundle,f.parent)+')',text)
 f.write_text('> Historical standalone backend benchmark; no Tessera runtime. Full source/data bundle: [physics-engine-results.zip]('+os.path.relpath(bundle,f.parent)+').\n\n'+text)
manifest={'packaged_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'historical_result_files':len(records),'raw_bytes':sum(r['bytes'] for r in records),'archives':archives,'files':records,'source_policy':'Captured source snapshots for major local runs are included where present. Compiled binaries, native archives, vendored dependencies, Unity players and duplicate intermediate source trees are omitted.','provenance':'Older runs are local snapshots; do not attribute them to the latest engine commit. Source/binary hashes and original failure/exclusion records are retained where available.'}
(O/'inventory.json').write_text(json.dumps(manifest,indent=2)+'\n')
summary=['# Historical benchmark archive','','These are the earlier results from this session, preserved with their original raw data and available provenance. **They were not rerun on the latest Tessera commit.** The commit-verified voxel run remains in [the main benchmark index](../README.md).','','## Main reports','','- [Final full-engine versus saved Unity comparison](full-engine/final-comparison-20261028-202825/REPORT.md) — physics, rendering, navigation, skinning, animation, audio and assets.','- [Ropes and all softbody types](softbody/results-20261029-094437/REPORT.md) — 829 primary timing processes plus 69 geometry/variant checks; includes rejected unstable configurations.','- [Standalone Jolt / Box3D / Rapier / Bullet comparison](physics-comparison/REPORT.md) — separate C ABI harness, not Tessera runtime timings.','- [Earlier voxel/destruction run](voxel/results-20261029-191142/REPORT.md).','','## Navigation and optimization history','']
for f in sorted((O/'full-engine').glob('*/REPORT.md')):
 if f.parent.name.startswith('final-comparison'):continue
 summary.append(f'- [{f.parent.name}]({f.relative_to(O)})')
summary+=['','## Earlier full-engine reports','','- [Original engine/Unity comparison](full-engine/COMPARISON.md).','- [Confirmation](full-engine/CONFIRMATION.md), [test status](full-engine/TEST_STATUS.md), [work log](full-engine/WORK_LOG.md).','- [All dated raw-run reports](full-engine/results/) — intermediate, failed and superseded results are retained with their status; they are not all current recommendations.','','## Downloadable raw data','',f'{len(records):,} historical artifact files, {sum(r["bytes"] for r in records)/1048576:.1f} MiB before compression. The [inventory](inventory.json) records every file path, SHA-256, size and containing archive.','']
for item in archives:summary.append(f'- [{item["path"]}]({item["path"]}) — {item["bytes"]/1048576:.2f} MiB; {item["files"]} files.')
summary+=['','## Artifact policy','','Extract all `.tar.gz` files into this directory to restore the original `full-engine/`, `softbody/` and `voxel/` result layout. Raw originals are byte-preserved; directly browsable Markdown copies have local filesystem links rewritten for GitHub and include a historical banner. The standalone physics ZIP is preserved exactly.','','Included: raw sample/check CSVs, summary tables, original failure/exclusion metadata, profiler captures/reports, build/run logs, graphics, benchmark scripts and captured source snapshots for the major runs where available.','','Omitted: executable players, shared/static libraries, object files, generated build caches, vendor dependencies/assets, and duplicate intermediate source copies. Original local paths may remain in raw provenance metadata. An old local source hash is not proof of a Git commit; only the separately labelled commit-verified run has that claim.','','The data includes failed, superseded and exploratory runs deliberately. Use the main reports and their comparability warnings before drawing conclusions.','']
(O/'README.md').write_text('\n'.join(summary))
print('PACKAGED',len(records),'raw files;',len(direct),'direct files;',sum(x['bytes'] for x in archives),'archive bytes',flush=True)
