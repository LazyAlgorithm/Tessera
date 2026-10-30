from pathlib import Path
import json,csv,statistics as st,sys
O=Path(sys.argv[1]);jobs=json.loads((O/'manifest.json').read_text());raw=list(csv.DictReader((O/'traffic.csv').open()));result=[]
for case in dict.fromkeys(j['case'] for j in jobs):
 js=[j for j in jobs if j['case']==case];server=next(j for j in js if j['peer']==0);m=server['metrics'][0] if server['metrics'] else None
 if not m:continue
 for phase,label in [(0,'moving'),(1,'idle-input')]:
  samples=[r for r in raw if r['case']==case and int(r['phase'])==phase];ss=[r for r in samples if r['role']=='server'];cs=[r for r in samples if r['role']=='client']
  if not ss or not cs:continue
  def mean(rows,key):return st.mean(float(r[key]) for r in rows)
  row=dict(case=case,phase=label,count=int(m[2]),profile=m[3],water=m[4],remote_clients=int(m[5]),passed=all(j['valid'] for j in js),server_hz=float(server['checks'].get('effective_tick_hz',0)),server_wire_sent_Bps=mean(ss,'wire_sent_Bps'),server_wire_received_Bps=mean(ss,'wire_received_Bps'),server_app_sent_Bps=mean(ss,'app_sent_Bps'),client_wire_received_mean_Bps=mean(cs,'wire_received_Bps'),client_wire_sent_mean_Bps=mean(cs,'wire_sent_Bps'),fixed_mean_ms=float(m[11]),fixed_worst_ms=float(m[12]),snapshot_build_mean_ms=float(m[16]),snapshot_read_mean_ms=max(float(j['metrics'][0][17]) for j in js if j['metrics']),max_truth_error_m=max(float(j['metrics'][0][13]) for j in js if j['metrics']),max_body_correction_m=max(float(j['checks'].get('max_body_correction',0)) for j in js),max_client_rollbacks=max(int(j['metrics'][0][15]) for j in js if j['metrics']),server_samples=len(ss),client_samples=len(cs));result.append(row)
with (O/'summary.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=result[0]);w.writeheader();w.writerows(result)
print(len(set(j['case'] for j in jobs)),'scenarios',len(jobs),'processes',sum(not j['valid'] for j in jobs),'failed')
for r in result:
 if r['phase']=='moving':print(r['case'],r['passed'],'downKiB',round(r['client_wire_received_mean_Bps']/1024,2),'serverMbps',round(r['server_wire_sent_Bps']*8/1e6,3),'Hz',round(r['server_hz'],2),'corr',round(r['max_body_correction_m'],4))
