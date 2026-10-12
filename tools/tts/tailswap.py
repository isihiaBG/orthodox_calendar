"""Опашката на парче от стария звук: python3 tailswap.py <снимка> <беседа|абзац|парче> <откъде> <№ за слушане> <начало на изречението>"""
import json,hashlib,array,shutil,sys
sys.path.insert(0,'.')
import eleven as E, splice_many as M
snap,name,w,n,first=sys.argv[1:6]
S='/tmp/claude-1000/-home-mypc-orthodox-calendar/223dc8d5-53b4-4c02-b3de-a1e756d7eff4/scratchpad'
ch,bi,ci=name.split('|')
c=[c for c in json.load(open('work/razgovori_marked.json')) if c['file']==ch][0]
bl=c['blocks'][int(bi)]; new=E.chunks_of(bl)[int(ci)][0]
old=json.load(open(snap))[name]
k=lambda t:hashlib.sha1(json.dumps([E.VOICES[bl['speaker']]['voice_id'],E.MODEL,E.settings(bl['speaker'],bl['kind'],t),E.SEED,t],ensure_ascii=False).encode()).hexdigest()[:20]
ho,hn=k(old),k(new)
for x in ('pcm','json'): shutil.copy(E.CACHE/f'{hn}.{x}',f'{S}/{name.replace("|","_")}_backup.{x}')
oal=json.loads((E.CACHE/f'{ho}.json').read_text()); op=(E.CACHE/f'{ho}.pcm').read_bytes()
nal=json.loads((E.CACHE/f'{hn}.json').read_text()); np_=(E.CACHE/f'{hn}.pcm').read_bytes()
ot,nt=''.join(oal['chars']),''.join(nal['chars'])
assert ot.count(w)==1==nt.count(w) and ot[ot.index(w):]==nt[nt.index(w):], 'опашките се различават'
oi,ni=ot.index(w),nt.index(w)
R=E.RATE; s=lambda t:int(round(t*R))*2
# шевът — в паузата пред думата
oa=(oal['end'][oi-1]+oal['start'][oi])/2; na=(nal['end'][ni-1]+nal['start'][ni])/2
F=int(0.004*R)
def fade(b,inn):
    x=array.array('h',b)
    for q in range(min(F,len(x))):
        g=q/F
        if inn: x[q]=int(x[q]*g)
        else: x[-1-q]=int(x[-1-q]*g)
    return x.tobytes()
pcm=fade(np_[:s(na)],False)+fade(op[s(oa):],True)
sh=na-oa
al={'chars':nal['chars'],'start':nal['start'][:ni]+[t+sh for t in oal['start'][oi:]],'end':nal['end'][:ni]+[t+sh for t in oal['end'][oi:]]}
(E.CACHE/f'{hn}.pcm').write_bytes(pcm); (E.CACHE/f'{hn}.json').write_text(json.dumps(al,ensure_ascii=False))
a=nt.index(first); end=nt.find('.',ni)+1 or len(nt)
M.mp3(M.clip(pcm,al,a,end),M.OUT/f'{int(n):02d}_novo.mp3')
print('ok',hn)
