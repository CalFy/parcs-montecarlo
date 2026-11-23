# -*- coding: utf-8 -*-
"""
PARCS (Python 2.7, Pyro4): паралельне обчислення числа pi методом Монте-Карло.

Вхідний файл (input.txt):
    1-й рядок: N    - загальна кількість випадкових точок
    2-й рядок: seed - базове зерно генератора (необов'язково, за замовчуванням 42)

Майстер ділить N точок на p рівних частин (p - кількість воркерів) і асинхронно
викликає mymap() на кожному воркері з власним зерном seed + i. Воркер генерує
точки (x, y) у квадраті [0,1)x[0,1) і рахує, скільки з них потрапило в чверть
кола x^2 + y^2 <= 1. Майстер підсумовує лічильники (reduce) і обчислює
pi ~ 4 * M / N, стандартну похибку та 95% довірчий інтервал.
"""
from Pyro4 import expose
import random
import time
import math

try:
    xrange
except NameError:  # Python 3 (локальне тестування)
    xrange = range


class Solver:
    def __init__(self, workers=None, input_file_name=None, output_file_name=None):
        self.input_file_name = input_file_name
        self.output_file_name = output_file_name
        self.workers = workers
        print("Inited")

    def solve(self):
        print("Job Started")
        t_start = time.time()
        p = len(self.workers)
        print("Workers %d" % p)

        n_total, seed = self.read_input()

        # розбиття N точок на p частин (остача - останньому воркеру)
        chunk = n_total // p
        sizes = [chunk] * p
        sizes[-1] += n_total - chunk * p

        # map: усі виклики запускаються до звернення до .value,
        # тому воркери рахують одночасно
        t_par = time.time()
        mapped = []
        for i in xrange(p):
            print("map %d: %d points" % (i, sizes[i]))
            mapped.append(self.workers[i].mymap(sizes[i], seed + i))

        # reduce
        inside, worker_times = self.myreduce(mapped)
        t_par = time.time() - t_par

        pi_est = 4.0 * inside / n_total
        q = float(inside) / n_total
        std_err = 4.0 * math.sqrt(q * (1.0 - q) / n_total)
        t_total = time.time() - t_start

        self.write_output(n_total, p, inside, pi_est, std_err,
                          worker_times, t_par, t_total)
        print("Job Finished")

    @staticmethod
    @expose
    def mymap(n_points, seed):
        """Обчислення на воркері: кількість точок усередині чверті кола."""
        t0 = time.time()
        rnd = random.Random(seed).random
        inside = 0
        for _ in xrange(n_points):
            x = rnd()
            y = rnd()
            if x * x + y * y <= 1.0:
                inside += 1
        return [inside, time.time() - t0]

    @staticmethod
    @expose
    def myreduce(mapped):
        print("reduce")
        inside = 0
        worker_times = []
        for res in mapped:
            # асинхронний результат Pyro4 (FutureResult) -> .value
            val = res.value if hasattr(res, "value") else res
            inside += int(val[0])
            worker_times.append(float(val[1]))
        print("reduce done")
        return inside, worker_times

    def read_input(self):
        f = open(self.input_file_name, "r")
        lines = [l.strip() for l in f.readlines() if l.strip()]
        f.close()
        n_total = int(lines[0])
        seed = int(lines[1]) if len(lines) > 1 else 42
        return n_total, seed

    def write_output(self, n_total, p, inside, pi_est, std_err,
                     worker_times, t_par, t_total):
        f = open(self.output_file_name, "w")
        f.write("Monte Carlo pi estimation (PARCS)\n")
        f.write("Points N: %d\n" % n_total)
        f.write("Workers: %d\n" % p)
        f.write("Points inside: %d\n" % inside)
        f.write("Pi estimate: %.8f\n" % pi_est)
        f.write("Abs error |pi - est|: %.8f\n" % abs(math.pi - pi_est))
        f.write("Std error: %.8f\n" % std_err)
        f.write("95%% CI: [%.6f, %.6f]\n" % (pi_est - 1.96 * std_err,
                                              pi_est + 1.96 * std_err))
        f.write("Worker compute times: %s\n" %
                ", ".join("%.3f" % t for t in worker_times))
        f.write("Parallel compute+comm time: %.6f\n" % t_par)
        f.write("Total time: %.6f\n" % t_total)
        f.close()
        print("output done")
