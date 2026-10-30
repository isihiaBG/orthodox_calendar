#!/usr/bin/env python3
"""Преходът в края на четивата (житията): звън + пеене (30.10.2026, автор).

Звънът (камбани или клепало) влиза сам, след няколко секунди пеенето се
наслагва, звънът заглъхва плавно и остава едва доловим зад пеенето, накрая
двете затихват заедно. Смесването е В ПРИЛОЖЕНИЕТО (lib/audio_prehod.dart) —
тук само се режат и изравняват частите, така че 9 звъна × 4 пеения = 36
комбинации без умножаване на мегабайтите.

Изворите са в tools/tts/work/prehod_src/ (в .gitignore):
  nikolaev.ogg      — камбаните на казашката катедрала „Св. Николай“, Николаев
                      (Zabuhailo, Commons, CC0), 7 мин — 4 парчета от различни места
  plovdiv.webm      — „Св. Богородица“, Пловдив (Jon Jensen, Commons, CC BY 3.0)
  sv_nedelya.opus   — „Св. Неделя“, София (Bin im Garten, Commons, CC BY-SA 3.0)
  kazan1/2.webm     — Казанският Богородичен манастир (Вячеслав Кирилин,
                      Commons, CC BY-SA 4.0)
  hilendar_klepalo.mp3 — клепалото на Хилендар (дадено от автора)
  viz_part1/2.ogg   — византийско пеене, по 22,5 мин (Commons, CC0):
                      Byzantine_Ecclesiastical_Hymn_part1 / _Hymns_Part2

Изход: assets/audio_prehod/zvan_<N>.mp3 (стерео 96 kbps) и pesen_<N>.mp3
(моно 64 kbps — записите са моно), БЕЗ влизане и
затихване (те са в смесването), изравнени по средна сила (линейно, без
динамично нормализиране — то дърпа звъна надолу, когато пеенето влезе).
Клепалото е удължено (средата му повторена с плавни шевове) и ограничено
по върхове — ударите му са остри.

⚠ Влизането и затихването НЕ са тук — само веднъж, в смесването
(двойното затихване изяждаше пеенето до 5–10 s, 30.10.2026).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'tools/tts/work/prehod_src')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'assets/audio_prehod')

ZVAN_LEN = 50  # звънът стига до края: влизане на пеенето ~8–9 s + пеене 40 s
PESEN_LEN = 40
MEAN_DB = -24  # средна сила на всяка част (смесването после ги балансира)

# (изход, извор, начало s). Клепалото е отделно — удължава се.
ZVAN = [
    ('zvan_1', 'nikolaev.ogg', 5),
    ('zvan_2', 'nikolaev.ogg', 60),
    ('zvan_3', 'nikolaev.ogg', 190),
    ('zvan_4', 'nikolaev.ogg', 300),
    ('zvan_5', 'plovdiv.webm', 0),
    ('zvan_6', 'sv_nedelya.opus', 0),
    ('zvan_7', 'kazan1.webm', 0),
    ('zvan_8', 'kazan2.webm', 0),
]
KLEPALO = 'zvan_9'
# (запис 1/2, начало s) — всеки от началото на фраза, след пауза.
PESEN = [(1, 3), (1, 123), (1, 214), (1, 335), (1, 451), (1, 687), (1, 982),
         (1, 1086), (1, 1175), (1, 1250), (2, 185), (2, 518), (2, 830),
         (2, 983), (2, 1308)]


def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    return r.stderr


def mean_db(inp, pre=()):
    err = run(['ffmpeg', '-hide_banner', *pre, '-i', inp, '-af', 'volumedetect', '-f', 'null', '-'])
    get = lambda k: float(err.split(k + ': ')[1].split()[0])
    return get('mean_volume'), get('max_volume')


def save(name, inp, pre=(), mono=False):
    m, peak = mean_db(inp, pre)
    g = MEAN_DB - m
    # Не над -1 dBFS — иначе ограничител (клепалото и шумните видеа).
    lim = ',alimiter=limit=0.89:attack=1:release=50:level=false' if peak + g > -1 else ''
    out = os.path.join(OUT, name + '.mp3')
    run(['ffmpeg', '-y', '-loglevel', 'error', *pre, '-i', inp, '-af',
         f'aformat=channel_layouts={"mono" if mono else "stereo"},volume={g:.2f}dB{lim}',
         '-ar', '44100', '-b:a', '64k' if mono else '96k', out])
    print(f'{name}: {g:+.1f} dB{" (ограничител)" if lim else ""}')


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, src, start in ZVAN:
        save(name, os.path.join(SRC, src), ('-ss', str(start), '-t', str(ZVAN_LEN)))
    # Клепалото (22 s): началото + средата му (4–19 s) още два пъти.
    k = os.path.join(SRC, 'hilendar_klepalo.mp3')
    tmp = os.path.join(OUT, '_klepalo.wav')
    run(['ffmpeg', '-y', '-loglevel', 'error', '-i', k, '-i', k, '-i', k, '-filter_complex',
         '[0]atrim=0:19,asetpts=PTS-STARTPTS[p];[1]atrim=4:19,asetpts=PTS-STARTPTS[q];'
         '[2]atrim=4:22.3,asetpts=PTS-STARTPTS[r];[p][q]acrossfade=d=1:c1=qsin:c2=qsin[pq];'
         '[pq][r]acrossfade=d=1:c1=qsin:c2=qsin', '-c:a', 'pcm_s16le', tmp])
    save(KLEPALO, tmp)
    os.remove(tmp)
    for n, (part, start) in enumerate(PESEN, 1):
        # Записите на пеенето са моно — стерео би било два еднакви канала.
        save(f'pesen_{n}', os.path.join(SRC, f'viz_part{part}.ogg'),
             ('-ss', str(start), '-t', str(PESEN_LEN)), mono=True)


if __name__ == '__main__':
    main()
