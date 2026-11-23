#!/bin/bash
# Усі заміри автоматично (Cloud Shell):  bash tools/run_all.sh
# Запуск з кореня репозиторію (потрібні solution.py, sequential.py, input/input_*.txt)
# Результати: папка results/ і файл results/summary.csv
REPEATS=${REPEATS:-3}
MASTER=parcs-master
ZONE=europe-central2-a
URL=http://127.0.0.1:8080
mkdir -p results

# 1. тунель до вебінтерфейсу PARCS
if ! curl -s -m 5 $URL/ >/dev/null; then
  echo "Starting SSH tunnel..."
  gcloud compute ssh $MASTER --zone=$ZONE -- -f -N -L 127.0.0.1:8080:localhost:8080
  sleep 3
fi
curl -s -m 5 $URL/ >/dev/null || { echo "ERROR: PARCS master is not reachable"; exit 1; }

# 2. ID воркерів
IDS=$(curl -s $URL/api/worker | python3 -c "import sys,json; print(' '.join(str(w['id']) for w in json.load(sys.stdin)['workers']))")
NW=$(echo $IDS | wc -w)
echo "Workers registered: $NW (ids: $IDS)"
[ "$NW" -ge 4 ] || echo "WARNING: less than 4 workers registered"

set_workers() {  # залишити увімкненими перші $1 воркерів
  local i=0
  for id in $IDS; do
    i=$((i+1))
    if [ $i -le $1 ]; then st=enable; else st=disable; fi
    curl -s -o /dev/null -X POST $URL/api/worker/$id/$st
  done
}

last_job_id() {
  curl -s $URL/jobs | grep -o 'data-job-id="[0-9]*"' | grep -o '[0-9]*' | sort -n | tail -1
}

run_job() {  # $1 = name, $2 = input file, $3 = output file
  local before=$(last_job_id)
  curl -s -o /dev/null -F job_name=$1 -F solution_file=@solution.py -F input_file=@$2 $URL/api/job
  local id=""
  for t in $(seq 1 30); do
    id=$(last_job_id)
    [ -n "$id" ] && [ "$id" != "$before" ] && break
    sleep 1
  done
  for t in $(seq 1 300); do
    code=$(curl -s -o $3 -w '%{http_code}' $URL/api/job/$id/output)
    [ "$code" = "200" ] && break
    sleep 1
  done
  if [ "$code" != "200" ]; then echo "  job $id ($1) FAILED or timeout"; rm -f $3; return; fi
  echo "  job $id $1: $(grep -E 'Workers|Total time' $3 | tr '\n' ' ')"
}

# 3. паралельна версія: 4, 3, 2, 1 воркер
for p in 4 3 2 1; do
  echo "=== $p worker(s) ==="
  set_workers $p
  sleep 1
  for n in 10M 20M 40M; do
    for r in $(seq 1 $REPEATS); do
      run_job "W${p}_${n}_R${r}" input/input_$n.txt results/par_w${p}_${n}_r${r}.txt
    done
  done
done
set_workers 4

# 4. послідовна версія на майстрі (той самий Python 2.7)
echo "=== sequential ==="
gcloud compute scp sequential.py $MASTER:~ --zone=$ZONE >/dev/null
for r in $(seq 1 $REPEATS); do
  gcloud compute ssh $MASTER --zone=$ZONE \
    --command='docker cp ~/sequential.py parcs:/tmp/ && docker exec parcs python /tmp/sequential.py' \
    | tee results/seq_r$r.txt
done

# 5. зведена таблиця
python3 - <<'EOF'
import glob, re, statistics as st
rows = []
for f in sorted(glob.glob("results/par_*.txt")):
    t = open(f).read()
    w = int(re.search(r"Workers: (\d+)", t).group(1))
    n = int(re.search(r"Points N: (\d+)", t).group(1))
    par = float(re.search(r"Parallel compute\+comm time: ([\d.]+)", t).group(1))
    tot = float(re.search(r"Total time: ([\d.]+)", t).group(1))
    pi = float(re.search(r"Pi estimate: ([\d.]+)", t).group(1))
    rows.append(("par", w, n, par, tot, pi, f))
for f in sorted(glob.glob("results/seq_*.txt")):
    for m in re.finditer(r"N=(\d+): pi=([\d.]+), error=[\d.]+, time=([\d.]+)", open(f).read()):
        rows.append(("seq", 0, int(m.group(1)), 0.0, float(m.group(3)), float(m.group(2)), f))
with open("results/summary.csv", "w") as out:
    out.write("mode,workers,N,par_time,total_time,pi,file\n")
    for r in rows: out.write(",".join(map(str, r)) + "\n")
groups = {}
for r in rows: groups.setdefault((r[0], r[1], r[2]), []).append(r[4])
print("\nmode workers N        median_total  runs")
for k in sorted(groups): print("%-4s %-7d %-9d %-12.3f %s" % (k[0], k[1], k[2], st.median(groups[k]), groups[k]))
EOF
echo; echo "Done. Send results/summary.csv"
