# -*- coding: utf-8 -*-
"""Локальна перевірка solution.py без кластера: імітує воркерів PARCS процесами
і повертає асинхронні результати з атрибутом .value, як Pyro4."""
import sys
import multiprocessing as mp
import solution


class Future:
    def __init__(self, ar):
        self._ar = ar

    @property
    def value(self):
        return self._ar.get()


class FakeWorker:
    def __init__(self, pool):
        self.pool = pool

    def mymap(self, n, seed):
        return Future(self.pool.apply_async(solution.Solver.mymap, (n, seed)))


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000000
    with open("input_test.txt", "w") as f:
        f.write("%d\n42\n" % n)
    for p in (1, 2, 4):
        with mp.Pool(p) as pool:
            s = solution.Solver([FakeWorker(pool) for _ in range(p)],
                                "input_test.txt", "output_test_%d.txt" % p)
            s.solve()
        print(open("output_test_%d.txt" % p).read())
