#!/usr/bin/env python3
from pathlib import Path
import json,sys,csv,hashlib,subprocess,statistics as st,math,datetime
ROOT=Path(__file__).resolve().parents[2];O=Path(sys.argv[1]).resolve();O.mkdir(parents=True,exist_ok=True);B=ROOT/'Benchmarks/voxel/build/Release_Linux64/Benchmark/Benchmark';M={'engine_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'engine_tree':subprocess.check_output(['git','rev-parse','HEAD:Engine'],cwd=ROOT,text=True).strip(),'started':datetime.datetime.now().isoformat(),'binary_sha256':hashlib.sha256(B.read_bytes()).hexdigest(),'jobs':[]};rows=[];summaries=[]
def save():
 (O/'manifest.json').write_text(json.dumps(M,indent=2))
 for name,data in [('processes.csv',rows),('summary.csv',summaries)]:
  if data:
   with (O/name).open('w') as f:w=csv.DictWriter(f,fieldnames=list(data[0]));w.writeheader();w.writerows(data)
def quantile(v,p):return sorted(v)[math.ceil(len(v)*p)-1]
def run(k,n,res,hits=0,col='mesh',mode='cpu',warm=8,samples=40,reps=3,profile=False):
 group=[]
 for rep in range(reps):
  name=f'{k}-{n}-{res}-{hits}-{col}-{mode}-{rep}'+('-profile' if profile else '');args=[str(B),k,str(n),str(res),str(hits),col,mode,str(warm),str(samples)]
  if profile:args.append(str(O/(name+'.tprofile')))
  try:p=subprocess.run(['/usr/bin/time','-f','RESOURCE,%M,%e',*args],capture_output=True,text=True,timeout=120,cwd=ROOT);out=p.stdout+'\n'+p.stderr;code=p.returncode
  except subprocess.TimeoutExpired:out='TIMEOUT';code=-1
  (O/(name+'.log')).write_text(out)
  checks={x.split(',')[1]:x.split(',',2)[2] for x in out.splitlines() if x.startswith('CHECK,')};v=[list(map(float,x.split(',')[2:6])) for x in out.splitlines() if x.startswith('SAMPLE,')];frames=[float(x.split(',')[2]) for x in out.splitlines() if x.startswith('FRAME,')]
  valid=code==0 and len(v)==samples and checks.get('valid')=='True' and 'capacity exceeded' not in out.lower() and all(math.isfinite(y) and y>=0 for x in v for y in x) and (mode=='cpu' or (len(frames)==samples and int(checks.get('draws',0))>0))
  M['jobs'].append({'name':name,'args':args,'exit':code,'valid':valid,'checks':checks});save()
  if not valid:print('INVALID',name,code,checks,flush=True);return None
  resource=next(x.split(',') for x in out.splitlines() if x.startswith('RESOURCE,'));r={'case':k,'count':n,'resolution':res,'hits':hits,'collision':col,'mode':mode,'repeat':rep,'profile':profile,'setup_ms':float(checks['setup_ms']),'rss_mib':int(resource[1])/1024,'vertices':int(checks['vertices']),'triangles':int(checks['triangles']),'grid_samples':int(checks['grid_samples']),'density_hash':checks['density_hash'],'changed_carves':int(checks['changed_carves']),'spawned_fragments':int(checks['spawned_fragments'])}
  for i,label in enumerate(['action','physics','update','total']):
   for stat,fun in [('median',st.median),('p95',lambda v:quantile(v,.95)),('p99',lambda v:quantile(v,.99)),('max',max)]:r[label+'_'+stat+'_ms']=fun([x[i] for x in v])
  for stat,fun in [('median',st.median),('p95',lambda v:quantile(v,.95)),('p99',lambda v:quantile(v,.99)),('max',max)]:r['frame_'+stat+'_ms']=fun(frames) if frames else 0
  rows.append(r);group.append(r);save()
 a={key:group[0][key] for key in ['case','count','resolution','hits','collision','mode','profile','vertices','triangles','grid_samples','density_hash']}
 for key in ['setup_ms','rss_mib','changed_carves','spawned_fragments',*[k for k in r if k.endswith('_ms') and k!='setup_ms']]:a[key]=st.median(x[key] for x in group)
 a['worst_process_frame_p95_ms']=max(x['frame_p95_ms'] for x in group);a['worst_process_action_p95_ms']=max(x['action_p95_ms'] for x in group);a['repeats']=len(group);summaries.append(a);save();print('DONE',k,n,res,hits,col,mode,'p95',round(a['frame_p95_ms'] if mode!='cpu' else a['total_p95_ms'],3),flush=True);return a
# Real intact map pieces, plus same-geometry shared-mesh controls.
for res,counts in [(16,[100,500,1000]),(24,[100,500,1000]),(32,[100,500]),(48,[100])]:
 for n in counts:
  run('idle',n,res,mode='render',warm=40,samples=100)
  if res in [16,24]:run('shared',n,res,mode='render',warm=40,samples=100)
for n in [100,500]:run('idle',n,24,mode='hq',warm=40,samples=100)
run('shared',500,24,mode='hq',warm=40,samples=100)
for n in [100,500,1000]:run('rays',n,24,warm=20,samples=80)
# Productive bullet carves, digging through a wall, and the CPU/physics split.
for res in [8,16,24,32,48]:
 for col in ['none','mesh','dynamic']:run('shots',1,res,1,col)
 run('shots',1,res,1,mode='render')
 run('slab',1,res,1,mode='render')
 if res>=16:run('shots-split',1,res,1)
# Explosion fan-out: exact count of affected object meshes, no implicit whole-map rebuild.
for res in [16,24,32]:
 for affected in [1,4,16]:run('blast',affected,res,affected,mode='render')
# Repeated edits to one object: current immediate behavior versus benchmark-only coalescing.
for res in [16,24,32]:
 for hits in [4,16]:
  for kind in ['burst','batch']:run(kind,1,res,hits,mode='render')
# Disconnection and fragment creation: default resolution is validated. A lower-resolution check
# is expected to detect the existing fragment grid-size mismatch. Higher resolutions are not run
# because the source copies into default-sized fragment arrays.
for n in [1,4,16]:run('split',n,24,n,mode='render')
run('split',1,16,1,reps=1,warm=1,samples=3)
for res in [8,16,24]:
 for n in [100,500]:run('debris',n,res,col='dynamic',mode='render',warm=60,samples=120)
# Actual built-in model voxelization startup, measured separately from idle runtime.
for kind in ['model-cube','model-sphere']:
 for res in [16,24,32]:run(kind,1,res,warm=2,samples=10)
for k,n,res,hits,col in [('shots',1,24,1,'mesh'),('blast',16,24,16,'mesh'),('split',1,24,1,'mesh')]:run(k,n,res,hits,col,reps=1,warm=8,samples=40,profile=True)
# Independent implementation equivalence checks for the coalescing prototype.
for res in [16,24,32]:
 for hits in [4,16]:
  a=next(r for r in summaries if r['case']=='burst' and r['resolution']==res and r['hits']==hits);b=next(r for r in summaries if r['case']=='batch' and r['resolution']==res and r['hits']==hits)
  assert all(a[k]==b[k] for k in ['density_hash','vertices','triangles']),(res,hits,'coalesced output mismatch')
M['finished']=datetime.datetime.now().isoformat();save();print('COMPLETE',len(M['jobs']),flush=True)
