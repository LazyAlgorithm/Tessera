from pathlib import Path
import subprocess,time,sys,json,os,csv
R=Path(__file__).resolve().parents[2]; O=Path(sys.argv[1]);O.mkdir(parents=True,exist_ok=True);B=R/'Benchmarks/water-network/network/build/Release_Linux64/Benchmark/Benchmark';env={**os.environ,'TESSERA_ROOT':str(R)};jobs=[];rows=[]
cases=[]
def add(n,p='default',w='waves',c=1,lag=0,jit=0,loss=0):cases.append((n,p,w,c,lag,jit,loss))
for p in ['default','optimized']:
 for w in ['none','waves']:add(0,p,w)
 for n in [64,256,1024]:add(n,p)
for p in ['default','exact','body','framed','budget','optimized']:add(256,p,'none')
for lag,jit,loss in [(75,25,5),(150,50,10)]:
 for p in ['default','optimized']:add(64,p,lag=lag,jit=jit,loss=loss)
for c,n in [(3,256),(7,256),(7,1024),(15,64),(31,64)]:add(n,'optimized',c=c)
for n,c in [(64,1),(256,7)]:add(n,'mixed',c=c)
add(1024,'budget')
if '--after-fix' in sys.argv:
 cases=[(n,p,'waves',c,lag,jit,loss) for n,p,c,lag,jit,loss in [(64,'default',1,0,0,0),(256,'default',1,0,0,0),(1024,'default',1,0,0,0),(64,'default',1,75,25,5),(64,'default',1,150,50,10),(64,'optimized',31,0,0,0),(256,'mixed',7,0,0,0),(1024,'budget',1,0,0,0)]]
for index,(n,p,w,c,lag,jit,loss) in enumerate(cases):
 name=f'{index:02}-{n}-{p}-{w}-{c}-{lag}-{jit}-{loss}';port=19800+index;processes=[];files=[];logs=[];start=time.monotonic()
 for role in ['server']+['client']*c:
  label=f'{role}-{len(processes)}';path=O/f'{name}-{label}.log';f=path.open('w');files.append(f);logs.append(path)
  processes.append(subprocess.Popen([str(B),role,str(n),p,w,str(c),str(port),str(lag),str(jit),str(loss)],cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT));time.sleep(.3 if role=='server' else .08)
 for proc in processes:
  try:proc.wait(timeout=max(1,55-(time.monotonic()-start)))
  except subprocess.TimeoutExpired:proc.kill();proc.wait()
 for f in files:f.close()
 valid=True
 for i,(proc,path) in enumerate(zip(processes,logs)):
  out=path.read_text();checks={l.split(',')[1]:l.split(',',2)[2] for l in out.splitlines() if l.startswith('CHECK,')};metrics=[l.split(',') for l in out.splitlines() if l.startswith('METRICS,')];ok=proc.returncode==0 and checks.get('valid')=='True' and checks.get('truth')=='True' and (i!=0 or float(checks.get('effective_tick_hz',0))>=55);valid &=ok
  for line in out.splitlines():
   if line.startswith('TRAFFIC,'):
    a=line.split(',');rows.append(dict(case=name,role='server' if i==0 else 'client',peer=i,count=n,profile=p,water=w,clients=c,lag=lag,jitter=jit,loss=loss,phase=int(a[1]),app_sent_Bps=float(a[2]),app_received_Bps=float(a[3]),transport_sent_Bps=float(a[4]),wire_sent_Bps=float(a[5]),wire_received_Bps=float(a[6])))
  jobs.append(dict(case=name,peer=i,valid=ok,exit=proc.returncode,checks=checks,metrics=metrics,log=path.name))
 (O/'manifest.json').write_text(json.dumps(jobs,indent=2))
 if rows:
  with (O/'traffic.csv').open('w') as f:writer=csv.DictWriter(f,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
 print('DONE' if valid else 'FAILED',name,round(time.monotonic()-start,1),flush=True)
print('NETWORK COMPLETE',len(cases),'cases',sum(not j['valid'] for j in jobs),'failed processes',flush=True)

sys.exit(0 if all(j['valid'] for j in jobs) else 1)
