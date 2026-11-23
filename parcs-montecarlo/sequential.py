# -*- coding: utf-8 -*-
"""Послідовна (еталонна) версія Монте-Карло для pi. Запускати на parcs-master:
    python sequential.py            (усі розміри)
    python sequential.py 10000000   (один розмір)
"""
from __future__ import print_function
import random
import time
import math
import sys

try:
    xrange
except NameError:
    xrange = range


def run_seq(n, seed=42):
    t0 = time.time()
    rnd = random.Random(seed).random
    inside = 0
    for _ in xrange(n):
        x = rnd()
        y = rnd()
        if x * x + y * y <= 1.0:
            inside += 1
    pi_est = 4.0 * inside / n
    dt = time.time() - t0
    print("Sequential N=%d: pi=%.8f, error=%.8f, time=%.4f s"
          % (n, pi_est, abs(math.pi - pi_est), dt))
    return dt


if __name__ == "__main__":
    sizes = [int(a) for a in sys.argv[1:]] or [10000000, 20000000, 40000000]
    for size in sizes:
        run_seq(size)
