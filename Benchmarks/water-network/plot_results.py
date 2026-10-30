from pathlib import Path
import csv,sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
O=Path(sys.argv[1]);P=O/'plots';P.mkdir(exist_ok=True)
W=list(csv.DictReader((O/'water/summary.csv').open()));N=list(csv.DictReader((O/'network/summary.csv').open()))
fig,ax=plt.subplots(figsize=(9,5))
for k,d,label in [('bodies','0.5','Rigid boxes'),('cloth','16','Cloth 289 vertices'),('cloth','32','Cloth 1089 vertices'),('jelly','8','Jelly 386 vertices'),('rope','32','Ropes 32 segments')]:
 rows=[r for r in W if r['case']==k and r['detail']==d and r['profile']=='False' and r['mode']=='cpu'];ax.plot([int(r['count']) for r in rows],[float(r['total_p95_ms']) for r in rows],marker='o',label=label)
ax.axhline(4,color='gray',linestyle='--',label='Example 4 ms subsystem budget');ax.axhline(16.67,color='red',linestyle=':',label='Entire 60 FPS frame budget');ax.set(xscale='log',xlabel='Separated floating objects (log scale)',ylabel='CPU total p95 (ms)',title='Water + physics + component mesh updates — Ryzen 7900X');ax.legend(fontsize=8);ax.grid(alpha=.2);fig.tight_layout();fig.savefig(P/'water-cpu-scaling.png',dpi=160);plt.close(fig)
fig,ax=plt.subplots(figsize=(8,4.6));counts=[64,256,1024];x=list(range(3))
for offset,profile,label in [(-.19,'default','Default body replication'),(.19,'optimized','Optional optimized configuration')]:
 vals=[float(next(r for r in N if r['profile']==profile and r['count']==str(n) and r['phase']=='moving' and r['remote_clients']=='1' and r['water']=='waves')['client_wire_received_mean_Bps'])/1024 for n in counts];bars=ax.bar([a+offset for a in x],vals,width=.38,label=label)
 for b,v in zip(bars,vals):ax.text(b.get_x()+b.get_width()/2,v+12,f'{v:.0f}',ha='center',fontsize=9)
ax.set(xticks=x,xticklabels=counts,xlabel='Moving floating props; one remote client',ylabel='Client received ENet UDP payload (KiB/s)',title='Baseline networking: precision/rate/prediction/compression settings differ');ax.legend();ax.grid(axis='y',alpha=.2);ax.set_axisbelow(True);fig.tight_layout();fig.savefig(P/'network-bandwidth.png',dpi=160);plt.close(fig)
