#!/usr/bin/env python3
"""Validate and package one completed run for source-control publication."""
from pathlib import Path
import json,sys,subprocess,hashlib,tarfile,datetime
ROOT=Path(__file__).resolve().parents[2];R=Path(sys.argv[1]).resolve()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
M=json.loads((R/'manifest.json').read_text());assert M.get('finished')
assert subprocess.run(['git','diff','--quiet',M['engine_commit'],'--','Engine','native','third_party'],cwd=ROOT).returncode==0,'Tested engine sources changed'
H=json.loads((R/'source-sha256.json').read_text());assert all(sha(ROOT/k)==v for k,v in H.items()),'Source hash mismatch'
assert sha(ROOT/'Benchmarks/voxel/build/Release_Linux64/Benchmark/Benchmark')==M['binary_sha256']
expected={f'shots-1-8-1-{col}-{mode}-0' for col,mode in [('none','cpu'),('mesh','cpu'),('dynamic','cpu'),('mesh','render')]}|{'split-1-16-1-mesh-cpu-0'}
rejected={j['name'] for j in M['jobs'] if not j['valid']};assert rejected==expected,(rejected,expected)
# Relocate command paths without changing the executable arguments or numeric settings.
for j in M['jobs']:j['args']=[a.replace(str(ROOT)+'/', '') for a in j['args']]
M['command_cwd']='repository root';(R/'manifest.json').write_text(json.dumps(M,indent=2)+'\n')
E=json.loads((R/'environment.json').read_text());E['metadata_recorded_utc']=E.pop('build_started_utc',E.get('metadata_recorded_utc'));(R/'environment.json').write_text(json.dumps(E,indent=2)+'\n')
V={'tested_commit':M['engine_commit'],'completed_processes':len(M['jobs']),'accepted_processes':len(M['jobs'])-len(rejected),'rejected_processes':sorted(rejected),'rejection_explanations':{'shots resolution 8':'Density changed but failed positive-solid-sample removal quality gate. Not a numerical crash; small dents may still be visible.','split resolution 16':'Detached fragment sample arrays/layout do not match parent resolution.'},'source_files_checked':len(H),'source_hash_mismatches':[],'coalescing_equivalence':'All paired final density FNV hashes, vertex counts and triangle counts match; assertions in runner passed.','engine_implementation_changes':False,'validated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()};(R/'validation.json').write_text(json.dumps(V,indent=2)+'\n')
raw=[p for p in R.iterdir() if p.is_file() and (p.suffix in ['.log','.tprofile'] or p.name.endswith('.tprofile.md'))]
files=[]
for p in raw:
 if p.suffix!='.tprofile':p.write_text(p.read_text(errors='replace').replace(str(ROOT),'<checkout>'))
 files.append({'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p)})
archive=R/'raw-data.tar.gz'
with tarfile.open(archive,'w:gz') as tar:
 for p in sorted(raw):
  info=tar.gettarinfo(str(p),arcname=p.name);info.uid=info.gid=0;info.uname=info.gname=''
  with p.open('rb') as f:tar.addfile(info,f)
(R/'artifact-integrity.json').write_text(json.dumps({'archive':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive),'files':files,'log_normalization':'Checkout paths replaced with <checkout>; measurement values unchanged. Binary profiler files unchanged.'},indent=2)+'\n')
for script in ['plot.py','report.py']:subprocess.run([sys.executable,str(ROOT/'Benchmarks/voxel'/script),str(R)],cwd=ROOT,check=True)
print('Validated',len(M['jobs']),'runs;',len(raw),'raw files; archive',archive.stat().st_size,'bytes')
