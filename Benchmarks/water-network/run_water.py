from pathlib import Path
import sys,subprocess,json,statistics as st,csv,math,os,datetime,hashlib
ROOT=Path(__file__).resolve().parents[2];O=Path(sys.argv[1]);O.mkdir(parents=True,exist_ok=True);B=ROOT/'Benchmarks/water-network/water/build/Release_Linux64/Benchmark/Benchmark';env={**os.environ,'TESSERA_ROOT':str(ROOT)};M={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'binary_sha256':hashlib.sha256(B.read_bytes()).hexdigest(),'jobs':[]};rows=[]
def pct(v,p):return sorted(v)[math.ceil(len(v)*p)-1]
def save():
 (O/'manifest.json').write_text(json.dumps(M,indent=2))
 if rows:
  with (O/'summary.csv').open('w') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def run(k,n=0,d=.5,look='real',mode='render',width=1920,warm=120,samples=300,reps=3,profile=False):
 if '--spot-only' in sys.argv and (profile or not ((k=='bodies' and n==1000) or (k=='ocean' and width==1920 and look=='real'))):return None
 if '--shell-only' in sys.argv and k!='shell':return None
 if '--render-only' in sys.argv and mode!='render':return None
 vals=[]
 for rep in range(reps):
  name=f'{k}-{n}-{d}-{look}-{mode}-{width}-{rep}'+('-profile' if profile else '');args=[str(B),k,str(n),str(d),look,mode,str(width),str(warm),str(samples)];args += [str(O/(name+'.tprofile'))] if profile else []
  try:p=subprocess.run(['/usr/bin/time','-f','RESOURCE,%M,%e',*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=180);out=p.stdout+'\n'+p.stderr;code=p.returncode
  except subprocess.TimeoutExpired:code=-1;out='TIMEOUT'
  (O/(name+'.log')).write_text(out);checks={l.split(',')[1]:l.split(',',2)[2] for l in out.splitlines() if l.startswith('CHECK,')};data=[list(map(float,l.split(',')[2:])) for l in out.splitlines() if l.startswith('SAMPLE,')];frames=[float(l.split(',')[2]) for l in out.splitlines() if l.startswith('FRAME,')];gpu=[float(l.split(',')[2]) for l in out.splitlines() if l.startswith('GPU,')]
  valid=code==0 and len(data)==samples and checks.get('valid')=='True' and all(math.isfinite(x) and x>=0 for v in data for x in v) and (mode=='cpu' or len(frames)==samples) and 'capacity exceeded' not in out.lower() and (mode=='cpu' or (checks.get('render_width')==str(width) and checks.get('render_height')==str(2160 if width==3840 else 1080 if width==1920 else 720)));M['jobs'].append({'name':name,'args':args,'exit':code,'valid':valid,'checks':checks});save()
  if not valid:print('INVALID',name,code,checks,flush=True);return None
  resource=next(l.split(',') for l in out.splitlines() if l.startswith('RESOURCE,'));r={'case':k,'count':n,'detail':d,'look':look,'mode':mode,'width':width,'profile':profile,'repeat':rep,'setup_ms':float(checks['setup_ms']),'rss_mib':int(resource[1])/1024,'floating':int(checks['floating']),'grid_cache':int(checks.get('grid_cache_count',0)),'vertices':int(checks.get('water_vertices',0))}
  for i,key in enumerate(['water','physics','update','total']):r[key+'_median_ms']=st.median(v[i] for v in data);r[key+'_p95_ms']=pct([v[i] for v in data],.95);r[key+'_p99_ms']=pct([v[i] for v in data],.99)
  r.update(frame_median_ms=st.median(frames) if frames else 0,frame_p95_ms=pct(frames,.95) if frames else 0,frame_p99_ms=pct(frames,.99) if frames else 0,gpu_median_ms=st.median(gpu) if gpu else 0);vals.append(r)
 # One summary per workload; process manifests/raw samples preserve variation.
 a={k:vals[0][k] for k in ['case','count','detail','look','mode','width','profile','vertices']}
 for key in vals[0]:
  if key not in a and key!='repeat':a[key]=st.median(v[key] for v in vals)
 a['worst_frame_p95_ms']=max(v['frame_p95_ms'] for v in vals);a['worst_water_p95_ms']=max(v['water_p95_ms'] for v in vals);a['repeats']=len(vals);rows.append(a);save();print('DONE',k,n,d,look,mode,width,'water95',round(a['water_p95_ms'],3),'frame95',round(a['frame_p95_ms'],3),flush=True);return a
for width in [1280,1920,3840]:
 run('baseline',width=width)
 for look in ['real','low']:
  for k in ['ocean','underwater','waterline']:run(k,look=look,width=width)
for k in ['lake','large-lake','no-ssr','travel','far']:run(k)
for spacing in [.1,2,8]:run('travel',d=spacing)
run('travel',samples=10000,reps=1)
for n in [1,10,100,500,1000,5000]:run('bodies',n,mode='cpu')
run('dry',1000,mode='cpu');run('bodies',100,mode='render');run('bodies',1000,mode='render')
for k,details in [('cloth',[8,16,32]),('jelly',[4,8]),('rope',[16,32,64])]:
 for d in details:
  for n in [1,10,50,100,250]:
   a=run(k,n,d,mode='cpu')
   if not a or a['total_p95_ms']>12:break
for n in [100,1000,10000]:
 run('queries',n,mode='cpu',warm=30,samples=120);run('queries-day',n,mode='cpu',warm=30,samples=120)
for k,n,d in [('bodies',1000,.5),('cloth',100,32),('rope',100,32)]:run(k,n,d,mode='cpu',samples=120,reps=1,profile=True)
if '--shell-only' in sys.argv:
 for d in [4,8]:
  for n in [1,10,50,100,250]:
   a=run('shell',n,d,mode='cpu')
   if not a or a['total_p95_ms']>12:break
M['finished']=datetime.datetime.now().isoformat();save();print('WATER COMPLETE',len(M['jobs']),flush=True)

sys.exit(0 if all(j['valid'] for j in M['jobs']) else 1)
