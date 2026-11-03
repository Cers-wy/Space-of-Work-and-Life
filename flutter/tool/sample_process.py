"""Read-only process CPU-time/RSS sampler. Never reads application data."""
import json,subprocess,time,statistics,sys
from pathlib import Path
suffix=sys.argv[1]
output=Path(sys.argv[2])
def processes():
 rows=subprocess.check_output(['ps','-axo','pid=,rss=,time=,args='],text=True).splitlines()
 result=[]
 for row in rows:
  parts=row.strip().split(None,3)
  if len(parts)==4 and parts[3].endswith(suffix):result.append(parts)
 return result
def seconds(value):
 parts=value.split(':');total=0
 for part in parts:total=total*60+float(part)
 return total
found=processes()
if len(found)!=1:raise RuntimeError(f'Expected one benchmark process, found {len(found)}')
pid=found[0][0];samples=[];previous=None
for _ in range(16):
 row=subprocess.check_output(['ps','-p',pid,'-o','rss=,time='],text=True).strip().split()
 now=time.monotonic();cpu=seconds(row[1]);rss=int(row[0])/1024
 if previous:samples.append({'rssMiB':rss,'intervalCPUPercent':(cpu-previous[1])/(now-previous[0])*100})
 previous=(now,cpu)
 time.sleep(1)
result={'pid':int(pid),'durationSeconds':len(samples),'method':'delta process CPU time / monotonic wall time; RSS from ps','rssMedianMiB':statistics.median(x['rssMiB'] for x in samples),'rssMaxMiB':max(x['rssMiB'] for x in samples),'cpuMedianPercent':statistics.median(x['intervalCPUPercent'] for x in samples),'cpuMaxPercent':max(x['intervalCPUPercent'] for x in samples),'samples':samples}
output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='samples'},indent=2))
