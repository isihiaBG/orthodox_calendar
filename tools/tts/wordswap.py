"""Дума от стария звук в новия: python3 wordswap.py <стар кеш> <нов кеш> <дума>"""
import sys,json,array
sys.path.insert(0,'.')
import eleven as E
old,new,w=sys.argv[1:4]
R=E.RATE
def load(h): return json.loads((E.CACHE/f'{h}.json').read_text()), (E.CACHE/f'{h}.pcm').read_bytes()
oal,op=load(old); nal,np_=load(new)
ot,nt=''.join(oal['chars']),''.join(nal['chars'])
oi,ni=ot.index(w),nt.index(w)
assert ot.count(w)==1 and nt.count(w)==1
def span(al,i,n):
    a=al['start'][i]
    j=i+n
    while al['chars'][j]==' ': j+=1
    b=al['start'][j]
    return a,b
oa,ob=span(oal,oi,len(w)); na,nb=span(nal,ni,len(w))
s=lambda t:int(round(t*R))*2
seg=op[s(oa):s(ob)]
# 4 ms плавно преливане на шевовете
F=int(0.004*R)
def fade(pcm,inn):
    x=array.array('h',pcm)
    for k in range(min(F,len(x))):
        g=k/F
        if inn: x[k]=int(x[k]*g)
        else: x[-1-k]=int(x[-1-k]*g)
    return x.tobytes()
seg=fade(fade(seg,True),False)
head=fade(np_[:s(na)],False); tail=fade(np_[s(nb):],True)
pcm=head+seg+tail
d=(ob-oa)-(nb-na)
j=ni+len(w)
while nal['chars'][j]==' ': j+=1
st=nal['start'][:ni]+[t-oa+na for t in oal['start'][oi:oi+len(w)]]+nal['start'][ni+len(w):j]+[t+d for t in nal['start'][j:]]
en=nal['end'][:ni]+[t-oa+na for t in oal['end'][oi:oi+len(w)]]+nal['end'][ni+len(w):j]+[t+d for t in nal['end'][j:]]
# интервалите между думата и следващия знак — в новия отрязък
for k in range(ni+len(w),j): st[k]=na+(ob-oa); en[k]=na+(ob-oa)
assert len(st)==len(nt)
(E.CACHE/f'{new}.pcm').write_bytes(pcm)
(E.CACHE/f'{new}.json').write_text(json.dumps({'chars':nal['chars'],'start':st,'end':en},ensure_ascii=False))
print('стара дума',round(ob-oa,3),'s; нова',round(nb-na,3),'s; разлика',round(d,3))
