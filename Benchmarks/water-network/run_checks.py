from pathlib import Path
import subprocess,json,sys,time,datetime
ROOT=Path(__file__).resolve().parents[2];O=Path(sys.argv[1]);O.mkdir(parents=True,exist_ok=True);jobs=[]
cases=[('water-debug',['BeefBuild','-workspace=Tests/Water','-config=Debug','-run']),('water-release',['BeefBuild','-workspace=Tests/Water','-config=Release','-run']),('maps',['BeefBuild',f'-workspace={ROOT}/Tests/Maps','-config=Debug','-run']),('dialogue',['BeefBuild','-workspace=Tests/Dialogue','-config=Debug','-run']),('sequencer',['BeefBuild','-workspace=Tests/Sequencer','-config=Debug','-run']),('network',['BeefBuild','-workspace=Tests/Network','-config=Debug','-run']),('bandwidth-debug',['BeefBuild','-workspace=Tests/NetworkBandwidth','-config=Debug','-run']),('bandwidth-release',[sys.executable,'tools/run_network_bandwidth_tests.py','--engine',str(ROOT)]),('prediction',['BeefBuild','-workspace=Tests/PhysicsPrediction','-config=Debug','-run']),('voice',['BeefBuild','-workspace=Tests/Voice','-config=Debug','-run']),('softbody',['BeefBuild','-workspace=Tests/SoftBodies','-config=Debug','-run']),('character',['BeefBuild','-workspace=Tests/CharacterController','-config=Debug','-run']),('anti-cheat',[sys.executable,'Tests/AntiCheat/run.py'])]
for name,args in cases:
 begin=time.monotonic()
 try:p=subprocess.run(args,cwd=ROOT/'Tests/Maps' if name=='maps' else ROOT,capture_output=True,text=True,errors='replace',timeout=600);text=p.stdout+p.stderr;code=p.returncode
 except subprocess.TimeoutExpired as e:text=(e.stdout or b'').decode(errors='replace')+(e.stderr or b'').decode(errors='replace');code=-1
 (O/(name+'.log')).write_text(text);fails=[x for x in text.splitlines() if x.startswith(('FAIL','ERROR'))];passes=[x for x in text.splitlines() if x.startswith('PASS')]
 r={'name':name,'args':args,'exit':code,'pass':code==0 and not fails,'pass_checks':len(passes),'failures':fails,'seconds':time.monotonic()-begin};jobs.append(r);(O/'checks.json').write_text(json.dumps({'jobs':jobs,'updated':datetime.datetime.now().isoformat()},indent=2));print(name,r['pass'],len(passes),'checks',round(r['seconds'],1),'s',fails[-5:],flush=True)
print('FUNCTIONAL CHECKS COMPLETE',flush=True)

sys.exit(0 if all(j['pass'] for j in jobs) else 1)
