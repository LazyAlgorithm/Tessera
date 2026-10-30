from pathlib import Path
import csv,sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
O=Path(sys.argv[1]);rs=list(csv.DictReader((O/'summary.csv').open()));rs=[r for r in rs if r['profile']=='False']
def get(case,n,res,hits=0,mode='render'):return next(r for r in rs if r['case']==case and int(r['count'])==n and int(r['resolution'])==res and int(r['hits'])==hits and r['mode']==mode)
fig,ax=plt.subplots(2,2,figsize=(12,9))
for res in [16,24]:
 counts=[100,500,1000];ax[0,0].plot(counts,[float(get('idle',n,res)['worst_process_frame_p95_ms']) for n in counts],marker='o',label=f'Unique voxels, res {res}');ax[0,0].plot(counts,[float(get('shared',n,res)['worst_process_frame_p95_ms']) for n in counts],ls='--',label=f'Shared mesh, res {res}')
ax[0,0].set(title='Intact objects: normal steady rendering',xlabel='visible objects',ylabel='worst-process frame p95 (ms)');ax[0,0].legend(fontsize=8)
for res in [16,24,32]:
 counts=[1,4,16];ax[0,1].plot(counts,[float(get('blast',n,res,n)['worst_process_frame_p95_ms']) for n in counts],marker='o',label=f'resolution {res}')
ax[0,1].axhline(16.667,color='r',ls=':',label='Entire 60 FPS frame');ax[0,1].set(title='Explosion fan-out: immediate rebuilds',xlabel='affected objects',ylabel='worst-process frame p95 (ms)');ax[0,1].legend(fontsize=8)
x=list(range(3));resolutions=[16,24,32]
for case,shift,label in [('burst',-.18,'Immediate: 16 rebuilds'),('batch',.18,'Coalesced: 1 rebuild')]:ax[1,0].bar([v+shift for v in x],[float(get(case,1,res,16)['worst_process_frame_p95_ms']) for res in resolutions],width=.36,label=label)
ax[1,0].set_xticks(x,[str(v) for v in resolutions]);ax[1,0].set(title='16 edits to the same object',xlabel='voxel resolution',ylabel='worst-process frame p95 (ms)');ax[1,0].legend(fontsize=8)
for case,shift,label in [('idle',-.18,'Unique voxels'),('shared',.18,'Shared mesh control')]:ax[1,1].bar([v+shift for v in [0,1]],[float(get(case,1000,res)['rss_mib'])/1024 for res in [16,24]],width=.36,label=label)
ax[1,1].set_xticks([0,1],['16','24']);ax[1,1].set(title='1,000 objects: process memory',xlabel='voxel resolution',ylabel='peak resident GiB (not VRAM)');ax[1,1].legend(fontsize=8)
for a in ax.ravel():a.grid(axis='y',alpha=.2)
fig.suptitle('Tessera voxel shooter feasibility — Ryzen 9 7900X / RTX 3070\n720p, simple material, no shadows/AA; event frames include benchmark reset/validation overhead',fontsize=12);fig.tight_layout(rect=[0,0,1,.92]);fig.savefig(O/'voxel-capacity.png',dpi=160);fig.savefig(O/'voxel-capacity.svg');plt.close(fig)
